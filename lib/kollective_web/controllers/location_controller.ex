defmodule KollectiveWeb.LocationController do
  use KollectiveWeb, :controller
  alias Kollective.Governance.Governance

  @doc """
  Main gateway route endpoint to resolve available ballot positions.
  Ingests coordinates, raw text addresses, or 6-digit PIN codes.
  """
  def resolve_offices(conn, %{"country_code" => country_code} = params) do
    cc = String.upcase(country_code)

    cond do
      # Track A: User passed raw GPS coordinates (Lat/Lng)
      Map.has_key?(params, "lat") and Map.has_key?(params, "lng") ->
        # Pass coordinates directly to the multi-country polymorphic dispatcher
        case Governance.resolve_global_ballot(cc, params) do
          {:ok, results} ->
            conn
            |> put_view(KollectiveWeb.LocationJSON)
            |> render(:offices, payload: results)

          {:error, reason} ->
            conn
            |> put_status(:not_found)
            |> json(%{status: "error", error: reason})
        end

      # Track B: High-Speed PIN Code Input Route (Optimized explicitly for India)
      cc == "IN" and Map.has_key?(params, "pincode") ->
        pincode = String.trim(params["pincode"])
        # Pull optional fallback text tokens if sent from an address parser frontend block
        fallback_district = Map.get(params, "district")

        # Invoke our dual-track PIN code + District fallback context function
        case Governance.resolve_by_pincode(pincode, fallback_district) do
          {:ok, results} ->
            conn
            |> put_view(KollectiveWeb.LocationJSON)
            |> render(:offices, payload: results)

          {:error, reason} ->
            conn
            |> put_status(:not_found)
            |> json(%{status: "error", error: reason})
        end

      # Track C: Standard Global Text Address Query Route (e.g., US Google Civic Strategy)
      Map.has_key?(params, "address") ->
        case Governance.resolve_global_ballot(cc, params) do
          {:ok, results} ->
            conn
            |> put_view(KollectiveWeb.LocationJSON)
            |> render(:offices, payload: results)

          {:error, reason} ->
            conn
            |> put_status(:not_found)
            |> json(%{status: "error", error: reason})
        end

      true ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          status: "error",
          error: "Missing valid location context parameters (lat/lng, pincode, or address)."
        })
    end
  end

  # Fallback catch-all for requests completely missing structural country definitions
  def resolve_offices(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      status: "error",
      error: "Missing mandatory 'country_code' identification key parameter."
    })
  end
end
