defmodule KollectiveWeb.PoliticalDistrictControllerTest do
  use KollectiveWeb.ConnCase, async: true
  import Kollective.Factory

  setup :authenticate_user

  describe "GET /api/v1/districts/:id/news" do
    test "returns district news feed", %{conn: conn, user: user} do
      parent = insert(:political_district, name: "Texas", level: 2)
      district = insert(:political_district, name: "District 1", level: 1, parent_id: parent.id)

      user =
        user
        |> Ecto.Changeset.change(%{
          district_l1_id: district.id,
          district_l2_id: parent.id,
          district_l3_id: district.id,
          state: "TX"
        })
        |> Kollective.Repo.update!()

      conn = assign(conn, :current_user, user)

      response =
        conn
        |> get(~p"/api/v1/districts/#{district.id}/news", %{"scope" => "local"})
        |> json_response(200)

      assert response["data"]["district"]["id"] == district.id
      assert response["data"]["district"]["name"] == "District 1"
      assert response["data"]["district"]["parent"]["name"] == "Texas"
      assert response["data"]["scope"] == "local"
      assert is_list(response["data"]["posts"])
    end
  end
end
