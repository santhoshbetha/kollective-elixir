defmodule KollectiveWeb.BusinessController do
  use KollectiveWeb, :controller
  alias Kollective.Businesses.Businesses
  alias KollectiveWeb.BusinessJSON

  action_fallback KollectiveWeb.FallbackController

  # POST /api/v1/businesses
  def create(conn, params) do
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

  # POST /api/v1/business_proposals
  def create_proposal(conn, params) do
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

  # GET /api/v1/get_local_businesses?type=existing&scope=federal&category=food_beverage
  # GET /api/v1/get_local_businesses?type=proposals&scope=federal&category=food_beverage
  # Expected params: ?type=existing&scope=federal&category=food_beverage
  def index(conn, %{"type" => type} = params) when type in ["proposals", "existing"] do
    user = conn.assigns.current_user

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
end
