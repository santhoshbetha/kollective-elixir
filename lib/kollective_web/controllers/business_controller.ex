# lib/kollective_web/controllers/local_discovery_controller.ex
defmodule KollectiveWeb.BusinessController do
  use KollectiveWeb, :controller
  alias Kollective.Businesses.Businesses

  action_fallback KollectiveWeb.FallbackController

  # POST /api/v1/businesses
  def create(conn, %{"business" => business_params}) do
    user = conn.assigns.current_user

    case Businesses.create_business(user, business_params) do
      {:ok, business} ->
        conn
        |> put_status(:created)
        |> json(%{
          status: "success",
          message: "Business registration successful. Verification is pending.",
          data: %{
            id: to_string(business.id),
            name: business.name,
            legal_structure: business.legal_structure,
            business_hours: Map.get(business.metadata || %{}, "business_hours", %{})
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        # Modern Warning-Free Alternative: Invoke formatting functions directly inside json/2
        |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))
    end
  end

  # POST /api/v1/business_proposals
  def create_proposal(conn, %{"proposal" => proposal_params}) do
    user = conn.assigns.current_user

    case Businesses.create_business_proposal(user, proposal_params) do
      {:ok, proposal} ->
        conn
        |> put_status(:created)
        |> json(%{
          status: "success",
          message: "Your community business proposal has been successfully published.",
          data: %{
            id: to_string(proposal.id),
            title: proposal.name,
            category: proposal.category,
            funding_details: Map.get(proposal.metadata || %{}, "funding_data", %{})
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        # Modern Warning-Free Alternative: Invoke formatting functions directly
        |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))
    end
  end

  # PATCH/PUT /api/v1/businesses/:id
  def update(conn, %{"id" => id, "business" => business_params}) do
    current_user = conn.assigns.current_user

    case Businesses.update_business(current_user, id, business_params) do
      {:ok, business} ->
        conn
        |> put_status(:ok)
        |> render(:show, business: business)

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Action rejected: You are not the registered operator of this entity."})

      {:error, :immutable_type_on_verified_entity} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "A verified corporate profile cannot switch structural entity definitions."
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))
    end
  end

  # DELETE /api/v1/businesses/:id
  def delete_business(conn, %{"id" => id}) do
    current_user = conn.assigns.current_user

    case Businesses.delete_business(current_user, id) do
      {:ok, _business} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Business infrastructure cleanly purged from cluster storage."
        })

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Purge terminal rejected: Insufficient structural permissions."})
    end
  end

  # PATCH/PUT /api/v1/business_proposals/:id
  def update_proposal(conn, %{"id" => id, "proposal" => proposal_params}) do
    user = conn.assigns.current_user

    case Businesses.update_business_proposal(user, id, proposal_params) do
      {:ok, proposal} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Your community business proposal has been successfully updated.",
          data: %{
            id: to_string(proposal.id),
            title: proposal.name,
            category: proposal.category,
            funding_details: Map.get(proposal.metadata || %{}, "funding_data", %{})
          }
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", message: "Business proposal not found."})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{status: "error", message: "You are not authorized to edit this proposal."})

      {:error, :bad_request} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", message: "Invalid operation target."})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))
    end
  end

  # DELETE /api/v1/business_proposals/:id
  def delete_proposal(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Businesses.delete_business_proposal(user, id) do
      {:ok, :deleted} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Your community business proposal has been successfully retracted."
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", message: "Business proposal not found."})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{status: "error", message: "You lack privileges to delete this resource."})

      {:error, :bad_request} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", message: "Invalid operation target."})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))
    end
  end

  # GET /api/v1/local_discovery/top-proposals
  def leaderboard(conn, _params) do
    user = conn.assigns.current_user
    top_ideas = Businesses.list_top_proposals(user)

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data:
        Enum.map(top_ideas, fn idea ->
          %{
            id: to_string(idea.id),
            name: idea.name,
            slug: idea.slug,
            bio: idea.bio,
            category: idea.category,
            sub_category: idea.sub_category,
            type: idea.type,
            verification_status: idea.verification_status,
            upvotes_count: idea.upvotes_count,
            inserted_at: Calendar.strftime(idea.inserted_at, "%Y-%m-%dT%H:%M:%SZ"),
            owner: %{
              id: to_string(idea.user.id),
              username: idea.user.username,
              avatar_url: idea.user.avatar_url
            }
          }
        end)
    })
  end

  # GET /api/v1/get_local_businesses?type=existing&scope=federal&category=food_beverage
  # GET /api/v1/get_local_businesses?type=proposals&scope=federal&category=food_beverage
  # Expected params: ?type=existing&scope=federal&category=food_beverage
  def index(conn, %{"type" => type} = params) when type in ["proposals", "existing"] do
    user = conn.assigns.current_user

    # Package query filters down into clean keyword options arrays
    opts = [
      scope: Map.get(params, "scope", "all"),
      category: Map.get(params, "category", "all")
    ]

    discovery_items = Businesses.list_local_businesses(user, type, opts)

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data:
        Enum.map(discovery_items, fn item ->
          %{
            id: to_string(item.id),
            name: item.name,
            category: item.category,
            sub_category: item.sub_category,
            type: item.type,
            verification_status: item.verification_status,
            inserted_at: Calendar.strftime(item.inserted_at, "%Y-%m-%dT%H:%M:%SZ"),
            owner: %{
              id: to_string(item.user.id),
              username: item.user.username,
              avatar_url: item.user.avatar_url
            }
          }
        end)
    })
  end

  # GET /api/v1/businesses/:id
  def show_business(conn, %{"id" => id}) do
    # Fetch and enforce that the record type strictly matches "existing"
    try do
      business = Businesses.get_business_by_type!(id, "existing")
      render_single_entity_json(conn, business)
    rescue
      Ecto.NoResultsError ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", message: "Business page not found."})
    end
  end

  # GET /api/v1/business_proposals/:id
  def show_proposal(conn, %{"id" => id}) do
    # Fetch and enforce that the record type strictly matches "proposals"
    try do
      proposal = Businesses.get_business_by_type!(id, "proposals")
      render_single_entity_json(conn, proposal)
    rescue
      Ecto.NoResultsError ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", message: "Business proposal not found."})
    end
  end

  # --- Private JSON Serialization Orchestrator ---
  # Reuses your exact owner formatting and maps detailed corporate metrics
  defp render_single_entity_json(conn, item) do
    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data: %{
        id: to_string(item.id),
        name: item.name,
        description: item.description,
        category: item.category,
        sub_category: item.sub_category,
        type: item.type,
        verification_status: item.verification_status,
        upvotes_count: item.upvotes_count,
        comments_count: item.comments_count,
        inserted_at: Calendar.strftime(item.inserted_at, "%Y-%m-%dT%H:%M:%SZ"),

        # Physical Contact Layout Array Properties
        contact_details: %{
          address: item.address,
          city: item.city,
          state: item.state,
          zip: item.zip,
          country: item.country,
          email: item.email,
          phone: item.phone,
          website: item.website
        },

        # Operational Corporate Metrics (Directly maps values or holds safe fallbacks)
        corporate_details: %{
          legal_structure: item.legal_structure,
          year_established: item.year_established,
          number_of_employees: item.number_of_employees,
          profile_image_url: item.profile_image_url
        },

        # Dynamic JSONB Data Layer Blocks (Exposes flexible funding fields)
        funding_details: Map.get(item.metadata || %{}, "funding_data", %{}),
        additional_metadata: Map.delete(item.metadata || %{}, "funding_data"),

        # Geographic Location Properties
        district_l1: item.district_l1,
        district_l2: item.district_l2,
        district_l3: item.district_l3,

        # Unified Owner Struct Serialization Node
        owner: %{
          id: to_string(item.user.id),
          username: item.user.username,
          avatar_url: item.user.avatar_url
        }
      }
    })
  end
end
