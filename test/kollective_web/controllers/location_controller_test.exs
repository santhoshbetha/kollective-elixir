defmodule KollectiveWeb.LocationControllerTest do
  use KollectiveWeb.ConnCase, async: true
  import Req.Test
  alias Kollective.Repo
  alias Kollective.Governance.{GeoNode, PincodeMapping, PoliticalOffice}

  setup do
    stub(Kollective.Services.GeocodioClient, fn conn ->
      json(conn, %{
        "address" => %{
          "postcode" => "560001",
          "state_district" => "Bengaluru Urban"
        }
      })
    end)

    mp =
      Repo.insert!(%PoliticalOffice{
        country_code: "IN",
        office_id: "mp_lok_sabha",
        category: "Federal",
        title: "Member of Parliament",
        scope: "national_district",
        desc: "Lok Sabha"
      })

    mla =
      Repo.insert!(%PoliticalOffice{
        country_code: "IN",
        office_id: "mla_ka",
        category: "State Legislative",
        title: "MLA (Karnataka)",
        scope: "state_district",
        desc: "Assembly",
        state_restriction: "Karnataka"
      })

    corporator =
      Repo.insert!(%PoliticalOffice{
        country_code: "IN",
        office_id: "corporator",
        category: "Urban Governance",
        title: "Municipal Corporator",
        scope: "city",
        desc: "Urban Ward",
        area_type: "urban"
      })

    karnataka =
      Repo.insert!(%GeoNode{
        country_code: "IN",
        level: 1,
        name: "Karnataka",
        local_type: "State",
        lgd_code: 29
      })

    bengaluru_geom = %Geo.Polygon{
      coordinates: [[{77.5, 12.9}, {77.7, 12.9}, {77.7, 13.1}, {77.5, 13.1}, {77.5, 12.9}]],
      srid: 4326
    }

    bengaluru_urban =
      Repo.insert!(%GeoNode{
        country_code: "IN",
        level: 2,
        name: "Bengaluru Urban",
        local_type: "District",
        area_type: "urban",
        lgd_code: 572,
        parent_id: karnataka.id,
        geom: bengaluru_geom
      })

    bbmp_ward =
      Repo.insert!(%GeoNode{
        country_code: "IN",
        level: 4,
        name: "BBMP Ward 148",
        local_type: "Urban Local Body",
        area_type: "urban",
        lgd_code: 247_812,
        parent_id: bengaluru_urban.id
      })

    Repo.insert!(%PincodeMapping{pincode: "560001", geo_node_id: bbmp_ward.id})

    {:ok, mp: mp, mla: mla, corporator: corporator}
  end

  describe "POST /api/v1/resolve-offices" do
    test "resolves offices via PIN code for India", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/resolve-offices", %{
          "country_code" => "IN",
          "pincode" => "560001"
        })

      assert json = json_response(conn, 200)
      assert json["status"] == "success"
      assert json["strategy_used"] == "pincode_exact"
      assert json["metadata"]["pincode"] == "560001"

      office_ids = Enum.map(json["offices"], & &1["office_id"])
      assert "mp_lok_sabha" in office_ids
      assert "mla_ka" in office_ids
      assert "corporator" in office_ids
    end

    test "resolves offices via GPS coordinates", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/resolve-offices", %{
          "country_code" => "IN",
          "lat" => 12.9716,
          "lng" => 77.5946
        })

      assert json = json_response(conn, 200)
      assert json["status"] == "success"
      assert json["metadata"]["pincode"] == "560001"

      office_ids = Enum.map(json["offices"], & &1["office_id"])
      assert "mp_lok_sabha" in office_ids
    end

    test "returns 422 when location parameters are missing", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/resolve-offices", %{
          "country_code" => "IN"
        })

      assert json = json_response(conn, 422)
      assert json["status"] == "error"
      assert json["error"] =~ "Missing valid location context parameters"
    end

    test "returns 400 when country_code is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/resolve-offices", %{})

      assert json = json_response(conn, 400)
      assert json["status"] == "error"
      assert json["error"] =~ "Missing mandatory 'country_code'"
    end
  end
end
