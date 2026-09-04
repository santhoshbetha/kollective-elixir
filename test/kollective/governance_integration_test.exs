defmodule Kollective.GovernanceIntegrationTest do
  use Kollective.DataCase, async: true
  import Req.Test
  alias Kollective.Governance.Governance
  alias Kollective.Governance.{GeoNode, PincodeMapping, PoliticalOffice}

  setup do
    stub(Kollective.Services.GeocodioClient, fn conn ->
      case conn.query_params do
        %{"lat" => "12.9716", "lon" => "77.5946"} ->
          Req.Test.json(conn, %{
            "address" => %{
              "postcode" => "560001",
              "state_district" => "Bengaluru Urban"
            }
          })

        %{"lat" => "14.2224", "lon" => "76.4001"} ->
          Req.Test.json(conn, %{
            "address" => %{
              "postcode" => "577501",
              "state_district" => "Chitradurga"
            }
          })

        _ ->
          Req.Test.json(conn, %{})
      end
    end)

    # 1. Seed Global Rules Matrix (PoliticalOffice)
    Repo.insert!(%PoliticalOffice{
      country_code: "IN",
      office_id: "mp_lok_sabha",
      category: "Federal",
      title: "Member of Parliament",
      scope: "national_district",
      desc: "Lok Sabha"
    })

    Repo.insert!(%PoliticalOffice{
      country_code: "IN",
      office_id: "mla_ka",
      category: "State Legislative",
      title: "MLA (Karnataka)",
      scope: "state_district",
      desc: "Assembly",
      state_restriction: "Karnataka"
    })

    Repo.insert!(%PoliticalOffice{
      country_code: "IN",
      office_id: "corporator",
      category: "Urban Governance",
      title: "Municipal Corporator",
      scope: "city",
      desc: "Urban Ward",
      area_type: "urban"
    })

    Repo.insert!(%PoliticalOffice{
      country_code: "IN",
      office_id: "samiti_member",
      category: "Rural Governance",
      title: "Panchayat Samiti Member",
      scope: "sub_district",
      desc: "Rural Block",
      area_type: "rural"
    })

    # 2. Seed Relational LGD Tree (GeoNode) with spatial geometries
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

    rural_geom = %Geo.Polygon{
      coordinates: [[{76.0, 14.0}, {76.5, 14.0}, {76.5, 14.5}, {76.0, 14.5}, {76.0, 14.0}]],
      srid: 4326
    }

    chitradurga =
      Repo.insert!(%GeoNode{
        country_code: "IN",
        level: 2,
        name: "Chitradurga",
        local_type: "District",
        area_type: "rural",
        lgd_code: 575,
        parent_id: karnataka.id,
        geom: rural_geom
      })

    # Leaf Nodes (Level 4 Local Bodies)
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

    gram_panchayat =
      Repo.insert!(%GeoNode{
        country_code: "IN",
        level: 4,
        name: "Chitradurga Village GP",
        local_type: "Gram Panchayat",
        area_type: "rural",
        lgd_code: 249_114,
        parent_id: chitradurga.id
      })

    # 3. Seed Postal Directory Join Index (PincodeMapping)
    Repo.insert!(%PincodeMapping{pincode: "560001", geo_node_id: bbmp_ward.id})
    Repo.insert!(%PincodeMapping{pincode: "577501", geo_node_id: gram_panchayat.id})

    :ok
  end

  test "Direct PIN code lookup resolves urban boundaries and filters political matrix rows" do
    {:ok, result} = Governance.resolve_by_pincode("560001")

    assert result.metadata.pincode == "560001"

    # Verify that the correct level 4 node was unpacked through the join mapping
    local_body_names = Enum.map(result.local_bodies, & &1.name)
    assert "BBMP Ward 148" in local_body_names

    office_ids = Enum.map(result.offices, & &1.office_id)
    assert "mp_lok_sabha" in office_ids
    assert "mla_ka" in office_ids
    assert "corporator" in office_ids
    refute "samiti_member" in office_ids
  end

  test "Direct PIN code lookup resolves rural boundaries and filters regional layers" do
    {:ok, result} = Governance.resolve_by_pincode("577501")

    assert result.metadata.pincode == "577501"

    local_body_names = Enum.map(result.local_bodies, & &1.name)
    assert "Chitradurga Village GP" in local_body_names

    office_ids = Enum.map(result.offices, & &1.office_id)
    assert "mp_lok_sabha" in office_ids
    assert "mla_ka" in office_ids
    assert "samiti_member" in office_ids
    refute "corporator" in office_ids
  end

  test "TRACK B: GPS coordinates drop in Urban Bengaluru and filter for correct offices" do
    {:ok, result} =
      Governance.resolve_global_ballot("IN", %{
        "lat" => 12.9716,
        "lng" => 77.5946
      })

    assert result.metadata.pincode == "560001"

    office_ids = Enum.map(result.offices, & &1.office_id)
    assert "mp_lok_sabha" in office_ids
    assert "mla_ka" in office_ids
    assert "corporator" in office_ids
    refute "samiti_member" in office_ids
  end

  test "TRACK B: GPS coordinates drop in Rural Chitradurga and swap local ballot structures" do
    {:ok, result} =
      Governance.resolve_global_ballot("IN", %{
        "lat" => 14.2224,
        "lng" => 76.4001
      })

    assert result.metadata.pincode == "577501"

    office_ids = Enum.map(result.offices, & &1.office_id)
    assert "mp_lok_sabha" in office_ids
    assert "mla_ka" in office_ids
    assert "samiti_member" in office_ids
    refute "corporator" in office_ids
  end

  test "Database lookup processing executes well inside the required threshold boundaries" do
    # Warm-up call
    Governance.resolve_by_pincode("560001")

    {microseconds, {:ok, _result}} =
      :timer.tc(fn ->
        Governance.resolve_by_pincode("560001")
      end)

    milliseconds = microseconds / 1000.0

    IO.puts(
      "\n⏱️ High-Speed PIN Code Database Index Query Resolved in: #{Float.round(milliseconds, 2)} ms"
    )

    assert milliseconds < 100.0
  end

  test "Direct PIN lookup with an unmapped postcode gracefully fails over to the district fallback track" do
    {:ok, result} = Governance.resolve_by_pincode("999999", "Chitradurga")

    assert result.strategy_used == "district_fallback"
    assert result.metadata.fallback_used == true
    assert result.metadata.resolved_district == "Chitradurga"

    office_ids = Enum.map(result.offices, & &1.office_id)

    assert "mp_lok_sabha" in office_ids
    assert "mla_ka" in office_ids
    refute "corporator" in office_ids
  end
end
