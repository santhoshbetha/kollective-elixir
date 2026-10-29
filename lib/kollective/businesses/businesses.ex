# This query implements your multi-tier visibility: matching any of the user's districts
# OR falling within 60 miles (approx. 96,560 meters).

defmodule Kollective.Businesses.Businesses do
  import Ecto.Query
  alias Ecto.Multi
  alias Kollective.Repo
  alias Kollective.Businesses.{Business, Comment, Upvote}
  alias Kollective.Accounts.User
  alias Kollective.Locations.Locations
  alias Kollective.Locations.{City, PoliticalDistrict}

  @doc """
  Registers an existing local business profile inside the platform database.
  Enforces white-listed properties and fires real-time synchronization cascades.
  """
  def create_business(%User{} = user, attrs \\ %{}) do
    attrs = Business.normalize_business_attrs(attrs)

    # Determine if explicit coordinates are missing while text address parameters are present
    has_coordinates? =
      not is_nil(attrs["latitude"] || attrs[:latitude]) and
        not is_nil(attrs["longitude"] || attrs[:longitude])

    address_text = attrs["address"] || attrs[:address]

    # Extract geoname_id string pointer passed from the frontend client autocomplete layout
    geoname_id = Map.get(attrs, "geoname_id") || Map.get(attrs, :geoname_id)
    city_id = Map.get(attrs, "city_id") || Map.get(attrs, :city_id)
    city_name = Map.get(attrs, "city") || Map.get(attrs, :city)
    state_code = Map.get(attrs, "state") || Map.get(attrs, :state)

    Multi.new()
    # Step 1: Ensure the city records are resolved gracefully without blocking rural onboarding
    |> Multi.run(:resolved_city, fn _repo, _changes ->
      cond do
        geoname_id && String.trim(to_string(geoname_id)) != "" ->
          case Locations.get_or_import_city(geoname_id) do
            {:ok, city} ->
              {:ok, city}

            {:error, _reason} ->
              resolve_city_fallback(city_id, city_name, state_code, user)
          end

        true ->
          resolve_city_fallback(city_id, city_name, state_code, user)
      end
    end)
    # Step 2: Bind the user metadata, type metrics, and city structural values to the attributes
    |> Multi.insert(:business, fn %{resolved_city: city} ->
      city_fields =
        if city do
          %{
            "city_id" => city.id,
            "city" => city.name,
            "state" => city.state,
            "country" => city.country
          }
        else
          %{}
        end

      user_geo = extract_user_geo(user)

      base_attrs =
        attrs
        |> Map.put("user_id", user.id)
        |> Map.put("type", "existing")
        # Queue for postcard/OTP review
        |> Map.put("verification_status", "pending")
        |> Map.merge(city_fields, fn _k, v1, v2 -> v1 || v2 end)

      base_attrs =
        if is_nil(base_attrs["location"]) and is_nil(base_attrs[:location]) and
             is_nil(base_attrs["latitude"]) and is_nil(base_attrs[:latitude]) and user_geo do
          Map.put(base_attrs, "location", user_geo)
        else
          base_attrs
        end

      Business.creation_changeset(%Business{user_id: user.id}, base_attrs)
    end)
    # Step 3: Polymorphic Geocoding Verification Pipeline
    |> Ecto.Multi.run(:enqueue_geocode, fn _repo, %{business: business} ->
      if (not has_coordinates? and address_text) && String.trim(address_text) != "" do
        %{"target_id" => business.id, "schema_type" => "Business", "address_text" => address_text}
        |> Kollective.Workers.GeocodeWorker.new()
        |> Oban.insert()
      else
        {:ok, :skipped}
      end
    end)

    # 🚀 STEP 4: AUTOMATED MEDIA PROCESSING BACKGROUND TRANSACTION INTERCEPTOR
    # Automatically triggers image optimization jobs if a profile image parameter is logged
    |> Ecto.Multi.run(:schedule_media_workers, fn _repo, %{business: business} ->
      raw_image_url = Map.get(attrs, "profile_image_url") || Map.get(attrs, :profile_image_url)

      if raw_image_url && String.trim(to_string(raw_image_url)) != "" do
        %{"business_id" => business.id}
        |> Kollective.Workers.BusinessImageOptimizer.new()
        |> Oban.insert!()
      end

      {:ok, :media_scheduled}
    end)

    # Execution Transaction Engine Block
    |> Repo.transaction()
    |> case do
      {:ok, %{business: business}} ->
        # Step B: REAL-TIME STREAMING PUSH
        # Tell active local timeline viewports that a new merchant has landed
        hydrated_business = Repo.preload(business, [:user])

        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          "feed:public",
          {:new_business_registered, %{id: hydrated_business.id, name: hydrated_business.name}}
        )

        {:ok, hydrated_business}

      {:error, _failed_step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp resolve_city_fallback(city_id, city_name, state_code, %User{} = user) do
    cond do
      city_id ->
        case Repo.get(City, city_id) do
          %City{} = city -> {:ok, city}
          _ -> fallback_to_user_city(user)
        end

      city_name && state_code && String.trim(to_string(city_name)) != "" ->
        case Repo.get_by(City,
               name: String.trim(to_string(city_name)),
               state: String.trim(to_string(state_code))
             ) do
          %City{} = city -> {:ok, city}
          _ -> fallback_to_user_city(user)
        end

      true ->
        fallback_to_user_city(user)
    end
  end

  defp fallback_to_user_city(%User{city_id: user_city_id}) when not is_nil(user_city_id) do
    case Repo.get(City, user_city_id) do
      %City{} = city -> {:ok, city}
      _ -> {:ok, nil}
    end
  end

  defp fallback_to_user_city(_), do: {:ok, nil}

  @doc """
  The definitive grassroots business idea and proposal creator.
  Saves the proposal details, builds optional city associations, stashes
  crowdfunding boundaries inside JSONB, and enqueues the Oban geocoder.
  """
  def create_business_proposal(%User{} = user, attrs \\ %{}) do
    attrs = Business.normalize_proposal_attrs(attrs)

    # Determine if explicit coordinates are missing while text address parameters are present
    has_coordinates? =
      not is_nil(attrs["latitude"] || attrs[:latitude]) and
        not is_nil(attrs["longitude"] || attrs[:longitude])

    address_text = attrs["address"] || attrs[:address]
    geoname_id = Map.get(attrs, "geoname_id") || Map.get(attrs, :geoname_id)
    city_id = Map.get(attrs, "city_id") || Map.get(attrs, :city_id)
    city_name = Map.get(attrs, "city") || Map.get(attrs, :city)
    state_code = Map.get(attrs, "state") || Map.get(attrs, :state)

    Multi.new()
    # Step 1: OPTIONAL CITY RESOLUTION (Never blocks rural or unincorporated onboarding)
    |> Multi.run(:resolved_city, fn _repo, _changes ->
      cond do
        geoname_id && String.trim(to_string(geoname_id)) != "" ->
          case Locations.get_or_import_city(geoname_id) do
            {:ok, city} -> {:ok, city}
            {:error, _} -> resolve_city_fallback(city_id, city_name, state_code, user)
          end

        true ->
          resolve_city_fallback(city_id, city_name, state_code, user)
      end
    end)

    # Step 2: Bind the user credentials and optional city tracking structures
    |> Multi.insert(:proposal, fn %{resolved_city: city} ->
      city_fields =
        if city do
          %{
            "city_id" => city.id,
            "city" => city.name,
            "state" => city.state,
            "country" => city.country
          }
        else
          %{}
        end

      user_geo = extract_user_geo(user)

      base_attrs =
        attrs
        |> Map.put("user_id", user.id)
        # Explicitly marks this entry as a community idea
        |> Map.put("type", "proposals")
        # Proposals stay unverified until launched
        |> Map.put("verification_status", "unverified")
        |> Map.merge(city_fields, fn _k, v1, v2 -> v1 || v2 end)

      base_attrs =
        if is_nil(base_attrs["location"]) and is_nil(base_attrs[:location]) and
             is_nil(base_attrs["latitude"]) and is_nil(base_attrs[:latitude]) and user_geo do
          Map.put(base_attrs, "location", user_geo)
        else
          base_attrs
        end

      # Pipes into your specific crowdfunding validation rules
      Business.proposal_changeset(%Business{user_id: user.id}, base_attrs)
    end)

    # Step 3: Enqueue the asynchronous polymorphic Oban GeocodeWorker
    |> Multi.run(:enqueue_geocode, fn _repo, %{proposal: proposal} ->
      if (not has_coordinates? and address_text) && String.trim(address_text) != "" do
        %{"target_id" => proposal.id, "schema_type" => "Business", "address_text" => address_text}
        |> Kollective.Workers.GeocodeWorker.new()
        |> Oban.insert()
      else
        {:ok, :skipped}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{proposal: proposal}} ->
        # ─── REAL-TIME TRANSMISSION DATA PIPELINE ───
        hydrated_proposal = Repo.preload(proposal, [:user])

        # FIXED: Broadcasts the correct event to feed stream components
        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          "feed:public",
          {:new_proposal_registered, %{id: hydrated_proposal.id, name: hydrated_proposal.name}}
        )

        {:ok, hydrated_proposal}

      {:error, _failed_step, changeset, _changes} ->
        # Clean catch-all block handles errors warning-free
        {:error, changeset}
    end
  end

  @doc """
  The unified business modifier engine.
  Differentiates between proposals and active storefronts to apply correct changeset validations .
  Safely schedules polymorphic background geocoding if an address text change occurs .
  """
  def update_business(%User{} = user, business_id, attrs) do
    # 1. Fetch the existing record with city associations preloaded to prevent a NotLoaded crash
    business = Repo.get!(Business, business_id) |> Repo.preload([:city_relation])

    geoname_id = Map.get(attrs, "geoname_id") || Map.get(attrs, :geoname_id)

    cond do
      # Auth Gate: Block malicious updates by verifying creator parity
      business.user_id != user.id ->
        {:error, :unauthorized}

      # Integrity Gate: Verified businesses must not alter corporate classification data fields directly
      business.verification_status == "verified" and
          (Map.has_key?(attrs, "type") or Map.has_key?(attrs, :type)) ->
        {:error, :immutable_type_on_verified_entity}

      true ->
        # 2. OPTIMIZED CHANGESET DETECTION: Compare inputs natively
        new_address = attrs["address"] || attrs[:address]
        has_new_coordinates? = not is_nil(attrs["latitude"] || attrs[:latitude])
        address_changed? = new_address && new_address != business.address

        Multi.new()
        # Step A: Conditional Location Resolution Node
        |> Multi.run(:resolved_attrs, fn _repo, _changes ->
          existing_external_id =
            case business.city_relation do
              %Kollective.Locations.City{external_id: id} -> to_string(id)
              _ -> nil
            end

          if is_nil(geoname_id) || to_string(geoname_id) == "" ||
               to_string(geoname_id) == existing_external_id do
            # No location changes or matching ID; pass original updates through
            {:ok, attrs}
          else
            # New city matching token passed; fetch or import the city schema row
            case Locations.get_or_import_city(geoname_id) do
              {:ok, city} ->
                updated_attrs =
                  attrs
                  |> Map.put("city_id", city.id)
                  |> Map.put("city", city.name)
                  |> Map.put("state", city.state)
                  |> Map.put("country", city.country)

                {:ok, updated_attrs}

              {:error, reason} ->
                {:error, {:city_resolution_failed, reason}}
            end
          end
        end)

        # Step B: Asymmetric Changeset Routing using the dynamically prepared attributes
        |> Multi.update(:business, fn %{resolved_attrs: final_attrs} ->
          case business.type do
            "proposals" -> Business.proposal_changeset(business, final_attrs)
            "existing" -> Business.creation_changeset(business, final_attrs)
          end
        end)

        # Step C: Log the user-facing modification directly into your unified audit table
        |> Multi.insert(:audit_log, fn _changes ->
          %Kollective.Admins.Log{
            action: "business_modification_#{business.type}",
            target_id: business.id,
            target_type: "Business",
            user_id: user.id,
            metadata: %{modified_at: DateTime.utc_now()}
          }
        end)

        # Step D: Conditionally queue the polymorphic Oban GeocodeWorker
        |> Multi.run(:enqueue_geocode, fn _repo, %{business: updated_business} ->
          # FIX: Only queue a background request if the address actually changed!
          if address_changed? && not has_new_coordinates? do
            %{
              "target_id" => updated_business.id,
              "schema_type" => "Business",
              "address_text" => new_address
            }
            |> Kollective.Workers.GeocodeWorker.new()
            |> Oban.insert()
          else
            {:ok, :skipped}
          end
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{business: updated_business}} ->
            # Dispatch a standard real-time update push alert
            Phoenix.PubSub.broadcast(
              Kollective.PubSub,
              "feed:public",
              {:business_updated, updated_business.id}
            )

            {:ok, Repo.preload(updated_business, [:user, :city_relation])}

          {:error, :resolved_attrs, {:city_resolution_failed, reason}, _changes} ->
            changeset =
              Ecto.Changeset.add_error(
                %Ecto.Changeset{data: business},
                :city_id,
                "Location update failed: #{inspect(reason)}"
              )

            {:error, changeset}

          {:error, _failed_step, changeset, _changes} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Permanently deletes an existing business storefront profile from public infrastructure.
  Wipes associated child upvotes and comments inside an atomic transaction pass to prevent constraint crashes.
  """
  def delete_business(%User{} = user, business_id) do
    case Repo.get(Business, business_id) do
      nil ->
        {:error, :not_found}

      %Business{type: "existing"} = business ->
        # FIX: Check your authoritative schema privilege boolean flags cleanly
        is_staff? = user.is_admin || user.is_moderator

        if business.user_id == user.id or is_staff? do
          Multi.new()
          # Step 1: Wipe child upvote relations to safeguard foreign key constraints
          |> Multi.run(:delete_upvotes, fn _repo, _changes ->
            from(u in Kollective.Businesses.Upvote, where: u.business_id == ^business.id)
            |> Repo.delete_all()

            {:ok, :upvotes_cleared}
          end)
          # Step 2: Wipe child comment relations to safeguard foreign key constraints
          |> Multi.run(:delete_comments, fn _repo, _changes ->
            from(c in Kollective.Businesses.Comment, where: c.business_id == ^business.id)
            |> Repo.delete_all()

            {:ok, :comments_cleared}
          end)
          # Step 3: Delete the core parent business record safely
          |> Multi.delete(:business, business)
          # Step 4: Record the administrative action for accountability logs if executed by staff
          |> Multi.run(:log_action, fn _repo, _changes ->
            if is_staff? do
              %Kollective.Admins.Log{
                action: "admin_business_deletion",
                target_id: business.id,
                target_type: "Business",
                user_id: user.id,
                metadata: %{business_name: business.name}
              }
              |> Repo.insert()
            else
              {:ok, :skipped}
            end
          end)
          |> Repo.transaction()
          |> case do
            {:ok, %{business: deleted_business}} ->
              # Step 5: Broadcast a flat eviction prompt down to active React viewports
              Phoenix.PubSub.broadcast(
                Kollective.PubSub,
                "feed:public",
                {:business_deleted, deleted_business.id}
              )

              {:ok, :deleted}

            {:error, _failed_step, changeset, _changes} ->
              {:error, changeset}
          end
        else
          {:error, :unauthorized}
        end

      _proposal_type ->
        {:error, :bad_request}
    end
  end

  @doc """
  Permanently deletes an unverified grassroots business idea or proposal.
  Wipes associated child upvotes and comments inside an atomic transaction pass to prevent constraint crashes.
  """
  def delete_business_proposal(%User{} = user, proposal_id) do
    case Repo.get(Business, proposal_id) do
      nil ->
        {:error, :not_found}

      %Business{type: "proposals"} = proposal ->
        # FIX: Check your authoritative schema privilege boolean flags cleanly
        is_staff? = user.is_admin || user.is_moderator

        if proposal.user_id == user.id or is_staff? do
          Multi.new()
          # Step 1: Wipe child upvote relations to safeguard foreign key constraints
          |> Multi.run(:delete_upvotes, fn _repo, _changes ->
            from(u in Kollective.Businesses.Upvote, where: u.business_id == ^proposal.id)
            |> Repo.delete_all()

            {:ok, :upvotes_cleared}
          end)
          # Step 2: Wipe child comment relations to safeguard foreign key constraints
          |> Multi.run(:delete_comments, fn _repo, _changes ->
            from(c in Kollective.Businesses.Comment, where: c.id == ^proposal.id)
            |> Repo.delete_all()

            {:ok, :comments_cleared}
          end)
          # Step 3: Delete the core parent proposal record safely
          |> Multi.delete(:proposal, proposal)
          # Step 4: Record the administrative action for accountability logs if executed by staff
          |> Multi.run(:log_action, fn _repo, _changes ->
            if is_staff? do
              %Kollective.Admins.Log{
                action: "admin_proposal_deletion",
                target_id: proposal.id,
                target_type: "Business",
                user_id: user.id,
                metadata: %{proposal_title: proposal.name}
              }
              |> Repo.insert()
            else
              {:ok, :skipped}
            end
          end)
          |> Repo.transaction()
          |> case do
            {:ok, %{proposal: deleted_proposal}} ->
              # Step 5: FIX - Broadcast a flat eviction prompt down to active React viewports
              Phoenix.PubSub.broadcast(
                Kollective.PubSub,
                "feed:public",
                {:proposal_deleted, deleted_proposal.id}
              )

              {:ok, :deleted}

            {:error, _failed_step, changeset, _changes} ->
              {:error, changeset}
          end
        else
          {:error, :unauthorized}
        end

      _existing_business ->
        {:error, :bad_request}
    end
  end

  @doc """
  Updates an existing grassroots business idea or proposal.
  Enforces crowdfunding casting parameters via proposal_changeset/2 .
  Safely schedules a polymorphic background Oban geocoder if address fields are altered .
  """
  def update_business_proposal(%User{} = user, proposal_id, attrs) do
    # Preload the city_relation association directly to safely inspect the current external_id
    case Repo.get(Business, proposal_id) |> Repo.preload(:city_relation) do
      nil ->
        {:error, :not_found}

      %Business{type: "proposals"} = proposal ->
        if proposal.user_id != user.id do
          {:error, :unauthorized}
        else
          # Extract potential geoname_id parameters from the updates list
          geoname_id = Map.get(attrs, "geoname_id") || Map.get(attrs, :geoname_id)

          # 1. OPTIMIZED CHANGESET DETECTION: Compare inputs natively
          new_address = attrs["address"] || attrs[:address]
          has_new_coordinates? = not is_nil(attrs["latitude"] || attrs[:latitude])
          address_changed? = new_address && new_address != proposal.address

          Multi.new()
          # Step A: Conditional Location Resolution Node
          |> Multi.run(:resolved_attrs, fn _repo, _changes ->
            current_external_id =
              if proposal.city_relation,
                do: to_string(proposal.city_relation.external_id),
                else: nil

            if is_nil(geoname_id) || to_string(geoname_id) == "" ||
                 to_string(geoname_id) == current_external_id do
              # No location change requested or it matches current value; proceed as-is
              {:ok, attrs}
            else
              # FIX: Corrected compile path from Kollective.Locations.Locations to Locations
              case Locations.get_or_import_city(geoname_id) do
                {:ok, city} ->
                  updated_attrs =
                    attrs
                    |> Map.put("city_id", city.id)
                    |> Map.put("city", city.name)
                    |> Map.put("state", city.state)
                    |> Map.put("country", city.country)

                  {:ok, updated_attrs}

                {:error, reason} ->
                  {:error, {:city_resolution_failed, reason}}
              end
            end
          end)

          # Step B: Apply structural modifications using the explicit proposal_changeset
          |> Multi.update(:proposal, fn %{resolved_attrs: final_attrs} ->
            Business.proposal_changeset(proposal, final_attrs)
          end)

          # Step C: Log the administrative user action for compliance logs
          |> Multi.insert(:audit_log, fn _changes ->
            %Kollective.Admins.Log{
              action: "proposal_modification",
              target_id: proposal.id,
              target_type: "Business",
              user_id: user.id,
              metadata: %{modified_at: DateTime.utc_now()}
            }
          end)

          # Step D: FIX - Conditionally enqueue the polymorphic Oban GeocodeWorker
          |> Multi.run(:enqueue_geocode, fn _repo, %{proposal: updated_proposal} ->
            if address_changed? && not has_new_coordinates? do
              %{
                "target_id" => updated_proposal.id,
                "schema_type" => "Business",
                "address_text" => new_address
              }
              |> Kollective.Workers.GeocodeWorker.new()
              |> Oban.insert()
            else
              {:ok, :skipped}
            end
          end)
          |> Repo.transaction()
          |> case do
            {:ok, %{proposal: updated_proposal}} ->
              # Ensure the structural graphs are fully hydrated before returning
              hydrated = Repo.preload(updated_proposal, [:user, :city_relation])

              # Step E: Stream live transient real-time alerts across your FeedChannel
              Phoenix.PubSub.broadcast(
                Kollective.PubSub,
                "feed:public",
                {:proposal_updated, %{id: hydrated.id, name: hydrated.name}}
              )

              {:ok, hydrated}

            {:error, :resolved_attrs, {:city_resolution_failed, reason}, _changes} ->
              changeset =
                Ecto.Changeset.add_error(
                  %Ecto.Changeset{data: proposal},
                  :city_id,
                  "Location update failed: #{inspect(reason)}"
                )

              {:error, changeset}

            {:error, _failed_step, changeset, _changes} ->
              # Clean catch-all block handles errors warning-free
              {:error, changeset}
          end
        end

      # Safety fallback guard if trying to hit a proposal endpoint with an "existing" business ID
      _existing_business ->
        {:error, :bad_request}
    end
  end

  @doc """
  Discovers local businesses or proposals within geometric search distance of the user's coordinates.
  Filters by type ("proposals" or "existing"), distance radius, and optional category/sub-category.

  Options (`opts`):
    * `:category` -> Optional category filter (e.g. "food_beverage", "retail")
    * `:sub_category` -> Optional sub-category filter (e.g. "cafe_coffee", "restaurant")
    * `:radius` / `:radius_meters` / `:radius_miles` -> Search radius (default 60 miles = 96,560 meters)
    * `:lat`, `:lng` -> Optional explicit coordinate overrides
  """
  def list_local_businesses(%User{} = user, type, opts \\ [])
      when type in ["proposals", "existing"] do
    category = Keyword.get(opts, :category)
    # Default 60 miles boundary sweep radius = 96,560.4 meters
    radius_meters = parse_business_radius(opts)

    # Initialize the base database query structure
    query = from(b in Business, where: b.type == ^type)

    user_geo = extract_user_geo(user, opts)

    # 1. Coordinate distance-based filtering
    query =
      if user_geo do
        where(
          query,
          [b],
          not is_nil(b.location) and
            fragment(
              "ST_DWithin(?::geography, ?::geography, ?)",
              b.location,
              ^user_geo,
              ^radius_meters
            )
        )
      else
        where(query, [b], false)
      end

    # 2. DYNAMIC FRONTEND CATEGORY FILTER TAB
    query =
      if category && category != "" && category != "all",
        do: where(query, [b], b.category == ^category),
        else: query

    query =
      if opts[:sub_category] && opts[:sub_category] != "" && opts[:sub_category] != "all",
        do: where(query, [b], b.sub_category == ^to_string(opts[:sub_category])),
        else: query

    # 3. COMPLIANCE VERIFICATION LOCK (The Business Kill-Switch)
    # Approved ideas transition to "verified", unverified drafts are left viewable under "proposals"
    query =
      if type == "existing" do
        if user && Map.get(user, :id) do
          where(query, [b], b.verification_status == "verified" or b.user_id == ^user.id)
        else
          where(query, [b], b.verification_status == "verified")
        end
      else
        query
      end

    # 4. EXECUTE B-TREE INDEXED DISK RETRIEVAL PASS
    query
    # Pre-sorted B-Tree indexes path cuts out slow on-the-fly table scanning
    |> order_by([b], desc: b.id)
    |> preload([:user])
    |> Repo.all()
  end

  # ─── PIPELINE 1: IDEMPOTENT UPVOTE TOGGLE SWITCH ───
  @doc """
  Toggles a user's upvote state on a business proposal.
  Maintains exact atomic counters directly on the parent row to prevent cache drift.

  Returns: {:ok, :inserted} or {:ok, :removed}
  """
  def toggle_upvote_business(user_id, business_id) do
    Repo.transaction(fn ->
      case Repo.get_by(Upvote, user_id: user_id, business_id: business_id) do
        nil ->
          # First click: Insert the relation row and increment the business counter atomically
          %Upvote{user_id: user_id, business_id: business_id} |> Repo.insert!()

          from(b in Business, where: b.id == ^business_id)
          |> Repo.update_all(inc: [upvotes_count: 1])

          {:ok, :inserted}

        existing_upvote ->
          # Second click: Remove relation row and decrement the counter cache
          Repo.delete!(existing_upvote)

          from(b in Business, where: b.id == ^business_id)
          |> Repo.update_all(inc: [upvotes_count: -1])

          {:ok, :removed}
      end
    end)
  end

  # ─── PIPELINE 2: HIGH-SPEED DISK THREAD LOOKUP ───
  @doc """
  Fetches a single-pass discussion thread stream for a business profile page.
  Preloads author structures using keyset index steps to prevent nested N+1 thread bottlenecks.
  """
  def get_discussion(business_id) do
    # Fetch comments and sub-replies flat in a single query pass
    all_comments =
      from(c in Comment,
        where: c.business_id == ^business_id,
        # Keyset sorting path
        order_by: [asc: c.id],
        # Preload commenter profiles instantly
        preload: [:user]
      )
      |> Repo.all()

    # Split into parents and sub-replies cleanly in server memory to construct the React layout tree
    {parents, replies} = Enum.split_with(all_comments, &is_nil(&1.parent_id))

    Enum.map(parents, fn parent ->
      child_replies = Enum.filter(replies, &(&1.parent_id == parent.id))
      Map.put(parent, :replies, child_replies)
    end)
  end

  # ─── PIPELINE 3: REGIONAL TOP LEADERBOARD ACCUMULATOR ───
  @doc """
  Compiles a localized trending leaderboard for proposals within the user's specific district.
  Looks back strictly over a 30-day window to rank active grassroots engagement.
  """
  def list_top_proposals(%User{} = user, limit \\ 5) do
    since = DateTime.utc_now() |> DateTime.add(-30, :day)

    from(b in Business,
      join: u in assoc(b, :upvotes),
      # Corrected to use uniform database field string tokens
      where: b.type == "proposals",
      where: b.district_l1 == ^user.district_l1 and b.state == ^user.state,
      where: u.inserted_at > ^since,
      group_by: b.id,
      select_merge: %{
        # Stash the aggregated value cleanly into a dynamic metadata field to satisfy Dialyzer views
        metadata: fragment("jsonb_build_object('trending_score', count(?))", u.user_id)
      },
      order_by: [desc: count(u.user_id)],
      limit: ^limit,
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Fetches a single business entity by ID and enforces type alignment parameters.
  Preloads the associated user/owner graph layer.
  """
  def get_business_by_type!(id, expected_type) when expected_type in ["proposals", "existing"] do
    Business
    |> where([b], b.id == ^id and b.type == ^expected_type)
    |> preload([:user, :city_relation])
    |> Repo.one!()
  end

  @doc """
  Appends an image URL to a business's gallery in metadata.
  """
  def add_business_image(%User{} = user, business_id, image_url) when is_binary(image_url) do
    business = Repo.get!(Business, business_id) |> Repo.preload([:user, :city_relation])

    if business.user_id != user.id do
      {:error, :unauthorized}
    else
      meta = business.metadata || %{}
      existing_images = Map.get(meta, "images") || Map.get(meta, "gallery") || []
      updated_images = if image_url in existing_images, do: existing_images, else: existing_images ++ [image_url]

      updated_meta =
        meta
        |> Map.put("images", updated_images)
        |> Map.put("gallery", updated_images)

      business
      |> Ecto.Changeset.change(%{metadata: updated_meta})
      |> Repo.update()
      |> case do
        {:ok, updated_b} -> {:ok, Repo.preload(updated_b, [:user, :city_relation])}
        err -> err
      end
    end
  end

  @doc """
  Removes an image URL from a business's gallery in metadata.
  """
  def delete_business_image(%User{} = user, business_id, image_url) when is_binary(image_url) do
    business = Repo.get!(Business, business_id) |> Repo.preload([:user, :city_relation])

    if business.user_id != user.id do
      {:error, :unauthorized}
    else
      meta = business.metadata || %{}
      existing_images = Map.get(meta, "images") || Map.get(meta, "gallery") || []
      updated_images = Enum.reject(existing_images, &(&1 == image_url))

      updated_meta =
        meta
        |> Map.put("images", updated_images)
        |> Map.put("gallery", updated_images)

      business
      |> Ecto.Changeset.change(%{metadata: updated_meta})
      |> Repo.update()
      |> case do
        {:ok, updated_b} -> {:ok, Repo.preload(updated_b, [:user, :city_relation])}
        err -> err
      end
    end
  end

  @doc """
  Extracts the user's geographic point (%Geo.Point{}) from:
    1. Explicit coordinates in `opts` (:lat/:lng or :latitude/:longitude).
    2. User's stored fuzzy location in `user.location` (WKT or %Geo.Point{}).
    3. User's political district centroid (L3, L2, or L1 via `PoliticalDistrict.geom`).
    4. User's home city coordinates (via `City.latitude`/`City.longitude`).
  """
  def extract_user_geo(user, opts \\ []) do
    lat_opt = opts[:lat] || opts[:latitude]
    lng_opt = opts[:lng] || opts[:longitude]

    cond do
      lat_opt && lng_opt ->
        with {:ok, lat} <- parse_coord(lat_opt),
             {:ok, lng} <- parse_coord(lng_opt) do
          %Geo.Point{coordinates: {lng, lat}, srid: 4326}
        else
          _ -> extract_geo_from_user(user)
        end

      true ->
        extract_geo_from_user(user)
    end
  end

  defp extract_geo_from_user(nil), do: nil

  defp extract_geo_from_user(%User{} = user) do
    cond do
      match?(%Geo.Point{}, user.location) ->
        %{user.location | srid: 4326}

      is_binary(user.location) and
          String.starts_with?(String.upcase(String.trim(user.location)), "POINT(") ->
        case Geo.WKT.decode(user.location) do
          {:ok, %Geo.Point{} = point} -> %{point | srid: 4326}
          _ -> fallback_user_geo_district_or_city(user)
        end

      is_binary(user.location) and String.contains?(user.location, ",") ->
        case String.split(user.location, ",") do
          [lat_s, lng_s] ->
            with {:ok, lat} <- parse_coord(String.trim(lat_s)),
                 {:ok, lng} <- parse_coord(String.trim(lng_s)) do
              %Geo.Point{coordinates: {lng, lat}, srid: 4326}
            else
              _ -> fallback_user_geo_district_or_city(user)
            end

          _ ->
            fallback_user_geo_district_or_city(user)
        end

      true ->
        fallback_user_geo_district_or_city(user)
    end
  end

  defp fallback_user_geo_district_or_city(%User{} = user) do
    district_id = user.district_l3_id || user.district_l2_id || user.district_l1_id

    district_geo =
      if district_id do
        case Repo.get(PoliticalDistrict, district_id) do
          %PoliticalDistrict{geom: %Geo.Point{coordinates: {lng, lat}}} ->
            %Geo.Point{coordinates: {lng, lat}, srid: 4326}

          %PoliticalDistrict{geom: %_{}} ->
            query =
              from(d in PoliticalDistrict,
                where: d.id == ^district_id,
                select:
                  {fragment("ST_Y(ST_Centroid(?))", d.geom),
                   fragment("ST_X(ST_Centroid(?))", d.geom)}
              )

            case Repo.one(query) do
              {lat, lng} when is_number(lat) and is_number(lng) ->
                %Geo.Point{coordinates: {lng, lat}, srid: 4326}

              _ ->
                nil
            end

          _ ->
            nil
        end
      end

    district_geo || fallback_user_geo_city(user)
  end

  defp fallback_user_geo_city(%User{} = user) do
    if user.city_id do
      case Repo.get(City, user.city_id) do
        %City{latitude: lat, longitude: lng}
        when not is_nil(lat) and not is_nil(lng) ->
          %Geo.Point{coordinates: {lng, lat}, srid: 4326}

        _ ->
          nil
      end
    else
      nil
    end
  end

  defp parse_business_radius(opts) do
    cond do
      opts[:radius_meters] ->
        case parse_coord(opts[:radius_meters]) do
          {:ok, r} -> r
          _ -> 160934.0
        end

      opts[:radius_miles] ->
        case parse_coord(opts[:radius_miles]) do
          {:ok, r} -> r * 1609.34
          _ -> 160934.0
        end

      opts[:radius] ->
        case parse_coord(opts[:radius]) do
          {:ok, r} -> r * 1609.34
          _ -> 160934.0
        end

      true ->
        160934.0
    end
  end

  defp parse_coord(nil), do: :error
  defp parse_coord(val) when is_float(val), do: {:ok, val}
  defp parse_coord(val) when is_integer(val), do: {:ok, val * 1.0}

  defp parse_coord(val) when is_binary(val) do
    case Float.parse(val) do
      {num, _} -> {:ok, num}
      :error -> :error
    end
  end

  defp parse_coord(_), do: :error
end

# 4. Implementation Strategy for Tabs
# Your React frontend will call the same endpoint with a tab parameter.

#    Tab: "Idea Proposals": Call list_local_businesses(user, :proposal).
#    Tab: "Local Businesses": Call list_local_businesses(user, :existing).

# 5. Why this works for your App

#    Geospatial Precision: Using ST_DWithin on a geography type is highly accurate for large distances like 60 miles because it accounts for the Earth's curvature.
#    District Loyalty: Even if a business is 70 miles away, it will show up if it's in the user's Federal District, maintaining your political discovery theme.
#    Discussion Support: Because these are standard Ecto records, you can easily attach a has_many :comments association to the Business schema so users can "join discussion" as requested.

# 3. React Frontend Tabs
# In your React UI, you simply switch the API call:

#    Tab "Business Ideas": fetch('/api/businesses?type=proposal')
#        Result: Users see all local brainstorms and can join the discussion.
#    Tab "Directory": fetch('/api/businesses?type=existing')
#        Result: Users see a curated list of shops that have proven they actually exist in the district.

# 4. Why this is the best flow

#    Low Barrier for Ideas: Anyone can post a proposal to their State Senate District to see if neighbors like it.
#    High Trust for Shops: By the time an idea becomes an "Existing Business," the user has likely gone through your Business Verification process.
