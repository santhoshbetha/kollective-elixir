# lib/kollective_web/controllers/locations/district_controller.ex
defmodule KollectiveWeb.DistrictController do
  use KollectiveWeb, :controller
  alias Kollective.External.CivicService
  alias KollectiveWeb.LocationJSON

  # GET /api/districts/lookup?address=123+Main+St+Austin+TX
  def lookup(conn, %{"address" => address}) do
    case CivicService.find_districts_by_address(address) do
      {:ok, districts} ->
        conn
        |> put_status(:ok)
        |> json(LocationJSON.districts(districts))

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: reason})
    end
  end
end
