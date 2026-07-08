# District Auto-Suggest
# 2. The Auto-Suggest Controller
# This endpoint allows your frontend to send an address string and get back the suggested district IDs to populate the user's profile form.

# lib/kollective_web/controllers/district_controller.ex
defmodule KollectiveWeb.DistrictController do
  use KollectiveWeb, :controller
  alias Kollective.External.CivicService

  # GET /api/districts/lookup?address=123+Main+St+Austin+TX
  def lookup(conn, %{"address" => address}) do
    case CivicService.find_districts_by_address(address) do
      {:ok, districts} ->
        json(conn, %{data: districts})

      {:error, reason} ->
        conn |> put_status(:bad_request) |> json(%{error: reason})
    end
  end
end
