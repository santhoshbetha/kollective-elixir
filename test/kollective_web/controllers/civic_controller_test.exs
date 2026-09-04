defmodule KollectiveWeb.CivicControllerTest do
  use KollectiveWeb.ConnCase, async: true

  import Req.Test

  setup :authenticate_user

  describe "POST /api/civic/update_precinct_node" do
    test "successfully updates user's political boundaries with valid address", %{
      conn: conn,
      user: user
    } do
      # Stub Geocodio API response
      stub(Kollective.Services.GeocodioClient, fn conn ->
        json(conn, %{
          "results" => [
            %{
              "formatted_address" => "1106 Congress Ave, Austin, TX 78701",
              "address_components" => %{
                "type" => "city",
                "county" => "Travis County",
                "city" => "Austin",
                "state" => "TX"
              },
              "fields" => %{
                "congressional_districts" => [
                  %{"district_number" => "10"}
                ],
                "state_legislative_districts" => %{
                  "senate" => [%{"district_number" => "14"}],
                  "house" => [%{"district_number" => "46"}]
                },
                "school_districts" => %{
                  "unified" => %{"name" => "Austin ISD"}
                },
                "disclosures" => %{
                  "local_jurisdiction" => %{
                    "district" => "District 9"
                  }
                }
              }
            }
          ]
        })
      end)

      conn =
        post(conn, ~p"/api/civic/update_precinct_node", %{
          "address" => "1106 Congress Ave, Austin, TX 78701"
        })

      assert response = json_response(conn, 200)
      assert response["data"]["street_address"] == "1106 Congress Ave, Austin, TX 78701"
      assert response["data"]["county"] == "Travis County"
      assert response["data"]["city_name"] == "Austin"
      assert response["data"]["state"] == "TX"
      assert response["data"]["city_council_district_code"] == "District 9"
      assert response["data"]["school_district_code"] == "Austin ISD"

      # Verify database is updated
      updated_user = Kollective.Repo.get!(Kollective.Accounts.User, user.id)
      assert updated_user.street_address == "1106 Congress Ave, Austin, TX 78701"
      assert updated_user.county == "Travis County"
      assert updated_user.city_name == "Austin"
      assert updated_user.state == "TX"
      assert updated_user.city_council_district_code == "District 9"
      assert updated_user.school_district_code == "Austin ISD"
      assert not is_nil(updated_user.district_l1_id)
      assert not is_nil(updated_user.district_l2_id)
      assert not is_nil(updated_user.district_l3_id)
    end

    test "returns 422 if GeocodioClient fails", %{conn: conn} do
      # Stub Geocodio API failure
      stub(Kollective.Services.GeocodioClient, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      conn =
        post(conn, ~p"/api/civic/update_precinct_node", %{
          "address" => "Some Invalid Address"
        })

      assert response = json_response(conn, 422)
      assert response["error"] == "Failed to resolve political boundaries"
    end
  end
end
