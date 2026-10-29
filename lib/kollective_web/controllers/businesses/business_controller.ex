defmodule KollectiveWeb.BusinessController do
  use KollectiveWeb, :controller
  alias Kollective.Businesses.Businesses
  alias KollectiveWeb.BusinessJSON
  alias KollectiveWeb.Plugs.RequirePersonalAccount

  @s3_engine Application.compile_env(:kollective, :s3_engine, ExAws.S3)

  action_fallback KollectiveWeb.FallbackController

  plug RequirePersonalAccount when action in [:create, :create_proposal]

  # POST /api/v1/businesses
  def create(conn, params) do
    if RequirePersonalAccount.is_organization_actor?(conn) do
      conn
      |> put_status(:forbidden)
      |> json(%{
        error: "forbidden",
        message: "Organizations cannot register businesses or submit proposals. Please switch to your personal profile."
      })
    else
      business_params = Map.get(params, "business", params)
      user = conn.assigns.current_user

      case Businesses.create_business(user, business_params) do
        {:ok, business} ->
          conn
          |> put_status(:created)
          |> json(%{
            status: "success",
            message: "Business registration successful. Verification is pending.",
            data: BusinessJSON.registration_data(business)
          })

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          # Modern Warning-Free Alternative: Invoke formatting functions directly inside json/2
          |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))
      end
    end
  end

  # POST /api/v1/business_proposals
  def create_proposal(conn, params) do
    if RequirePersonalAccount.is_organization_actor?(conn) do
      conn
      |> put_status(:forbidden)
      |> json(%{
        error: "forbidden",
        message: "Organizations cannot register businesses or submit proposals. Please switch to your personal profile."
      })
    else
      proposal_params = Map.get(params, "proposal", params)
      user = conn.assigns.current_user

      case Businesses.create_business_proposal(user, proposal_params) do
        {:ok, proposal} ->
          conn
          |> put_status(:created)
          |> json(%{
            status: "success",
            message: "Your community business proposal has been successfully published.",
            data: BusinessJSON.proposal_data(proposal)
          })

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          # Modern Warning-Free Alternative: Invoke formatting functions directly
          |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))
      end
    end
  end

  # PATCH/PUT /api/v1/businesses/:id
  def update(conn, %{"id" => id} = params) do
    business_params = Map.get(params, "business", Map.delete(params, "id"))
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
  def update_proposal(conn, %{"id" => id} = params) do
    proposal_params = Map.get(params, "proposal", Map.delete(params, "id"))
    user = conn.assigns.current_user

    case Businesses.update_business_proposal(user, id, proposal_params) do
      {:ok, proposal} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Your community business proposal has been successfully updated.",
          data: BusinessJSON.proposal_data(proposal)
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
      data: BusinessJSON.leaderboard(top_ideas)
    })
  end

  # GET /api/v1/businesses
  # GET /api/v1/business_proposals
  # Expected params: ?type=existing&scope=federal&category=food_beverage (type optional)
  def index(conn, params) do
    user = conn.assigns.current_user

    type =
      case Map.get(params, "type") do
        t when t in ["proposals", "existing"] ->
          t

        _ ->
          if List.last(conn.path_info) == "business_proposals", do: "proposals", else: "existing"
      end

    # Package query filters down into clean keyword options arrays
    opts = [
      scope: Map.get(params, "scope", "all"),
      category: Map.get(params, "category", "all"),
      sub_category: Map.get(params, "sub_category"),
      lat: Map.get(params, "lat") || Map.get(params, "latitude"),
      lng: Map.get(params, "lng") || Map.get(params, "longitude") || Map.get(params, "lon"),
      radius: Map.get(params, "radius") || Map.get(params, "distance"),
      radius_miles: Map.get(params, "radius_miles") || Map.get(params, "distance_miles"),
      radius_meters: Map.get(params, "radius_meters")
    ]

    discovery_items = Businesses.list_local_businesses(user, type, opts)

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data: BusinessJSON.index(discovery_items)
    })
  end

  # GET /api/v1/businesses/:id
  def show_business(conn, %{"id" => id}) do
    # Fetch and enforce that the record type strictly matches "existing"
    try do
      business = Businesses.get_business_by_type!(id, "existing")

      conn
      |> put_status(:ok)
      |> json(%{
        status: "success",
        data: BusinessJSON.data(business)
      })
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

      conn
      |> put_status(:ok)
      |> json(%{
        status: "success",
        data: BusinessJSON.data(proposal)
      })
    rescue
      Ecto.NoResultsError ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", message: "Business proposal not found."})
    end
  end

  # GET /api/v1/businesses/media/presign
  # GET /api/v1/businesses/:id/media/presign
  def presign_media(conn, params) do
    user = conn.assigns.current_user
    filename = Map.get(params, "filename", "business.jpg")
    content_type = Map.get(params, "content_type", "image/jpeg")

    cleaned_ext = Path.extname(filename) |> String.downcase()
    cleaned_ext = if cleaned_ext == "", do: ".jpg", else: cleaned_ext
    unique_name = "business_#{System.system_time(:second)}_#{System.unique_integer([:positive])}#{cleaned_ext}"
    relative_path = "businesses/#{user.id}/#{unique_name}"
    file_key = Kollective.Storage.object_key(relative_path)

    upload_url =
      cond do
        Mix.env() == :e2e ->
          "/media/#{file_key}"

        @s3_engine != ExAws.S3 ->
          case @s3_engine.presigned_url(s3_config(), :put, Kollective.Storage.bucket_name(), file_key,
                 expires_in: 900,
                 query_params: [{"Content-Type", content_type}]
               ) do
            {:ok, url} -> url
            _ -> "/media/#{file_key}"
          end

        has_r2_credentials?() ->
          case @s3_engine.presigned_url(s3_config(), :put, Kollective.Storage.bucket_name(), file_key,
                 expires_in: 900,
                 query_params: [{"Content-Type", content_type}]
               ) do
            {:ok, url} -> url
            _ -> "/media/#{file_key}"
          end

        true ->
          "/media/#{file_key}"
      end

    final_asset_url = "#{Kollective.Storage.cdn_domain()}/#{file_key}"

    json(conn, %{
      status: "success",
      upload_url: upload_url,
      final_asset_url: final_asset_url
    })
  end

  # POST /api/v1/businesses/:id/images
  def add_image(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user
    image_url = params["image_url"] || params["url"] || params["image"]

    if is_nil(image_url) or String.trim(to_string(image_url)) == "" do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Image URL is required."})
    else
      case Businesses.add_business_image(user, id, image_url) do
        {:ok, business} ->
          conn
          |> put_status(:ok)
          |> json(%{
            status: "success",
            message: "Image added successfully.",
            data: BusinessJSON.data(business)
          })

        {:error, :unauthorized} ->
          conn
          |> put_status(:forbidden)
          |> json(%{error: "Action rejected: You are not the registered operator of this entity."})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))
      end
    end
  end

  # DELETE /api/v1/businesses/:id/images
  def delete_image(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user
    image_url = params["image_url"] || params["url"] || params["image"]

    if is_nil(image_url) or String.trim(to_string(image_url)) == "" do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Image URL is required."})
    else
      case Businesses.delete_business_image(user, id, image_url) do
        {:ok, business} ->
          conn
          |> put_status(:ok)
          |> json(%{
            status: "success",
            message: "Image deleted successfully.",
            data: BusinessJSON.data(business)
          })

        {:error, :unauthorized} ->
          conn
          |> put_status(:forbidden)
          |> json(%{error: "Action rejected: You are not the registered operator of this entity."})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))
      end
    end
  end

  defp has_r2_credentials? do
    key = System.get_env("R2_ACCESS_KEY_ID") || Application.get_env(:ex_aws, :access_key_id)
    secret = System.get_env("R2_SECRET_ACCESS_KEY") || Application.get_env(:ex_aws, :secret_access_key)
    is_binary(key) and key != "" and is_binary(secret) and secret != ""
  end

  defp s3_config do
    if @s3_engine == ExAws.S3 do
      ExAws.Config.new(:s3)
    else
      %{}
    end
  end
end
