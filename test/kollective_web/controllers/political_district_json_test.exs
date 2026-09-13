defmodule KollectiveWeb.PoliticalDistrictJSONTest do
  use KollectiveWeb.ConnCase, async: true
  alias KollectiveWeb.PoliticalDistrictJSON
  alias Kollective.Locations.PoliticalDistrict
  alias Kollective.Accounts.User

  describe "PoliticalDistrictJSON.news/1" do
    test "renders correctly with a district struct" do
      parent = %PoliticalDistrict{
        id: "01HXYZPARENT0000000000000",
        name: "Texas",
        level: 2,
        parent: nil
      }

      district = %PoliticalDistrict{
        id: "01HXYZCHILD00000000000000",
        name: "District 1",
        level: 1,
        parent: parent
      }

      user = %User{
        id: "01HXYZUSER000000000000000",
        last_read_at: nil,
        district_l1_id: "01HXYZCHILD00000000000000",
        state: "TX",
        country: "US"
      }

      meta = %{page_number: 1, total_pages: 5}

      result =
        PoliticalDistrictJSON.news(%{
          district: district,
          posts: [],
          meta: meta,
          scope: "local",
          current_user: user
        })

      assert result.data.scope == "local"
      assert result.data.district.id == "01HXYZCHILD00000000000000"
      assert result.data.district.name == "District 1"
      assert result.data.district.parent.id == "01HXYZPARENT0000000000000"
      assert result.data.pagination.current_page == 1
      assert result.data.pagination.total_pages == 5
      assert result.data.badges.local == false
      assert result.data.badges.state == false
    end

    test "handles nil district and unloaded parent gracefully" do
      district = %PoliticalDistrict{
        id: "01HXYZCHILD00000000000000",
        name: "District 1",
        level: 1,
        parent: %Ecto.Association.NotLoaded{}
      }

      user = %User{
        id: "01HXYZUSER000000000000000",
        last_read_at: nil
      }

      result =
        PoliticalDistrictJSON.news(%{
          district: district,
          posts: [],
          meta: %{page_number: 1, total_pages: 1},
          scope: "world",
          current_user: user
        })

      assert result.data.district.id == "01HXYZCHILD00000000000000"
      assert result.data.district.parent == nil
    end

    test "handles nil district parameter" do
      user = %User{
        id: "01HXYZUSER000000000000000",
        last_read_at: nil
      }

      result =
        PoliticalDistrictJSON.news(%{
          district: nil,
          posts: [],
          meta: %{page_number: 1, total_pages: 1},
          scope: "world",
          current_user: user
        })

      assert result.data.district == nil
    end
  end

  describe "PoliticalDistrictJSON.show/1 and index/1" do
    test "show/1 formats single district" do
      district = %PoliticalDistrict{
        id: "01HXYZCHILD00000000000000",
        name: "District 1",
        level: 1,
        parent: nil
      }

      result = PoliticalDistrictJSON.show(%{district: district})
      assert result.data.id == "01HXYZCHILD00000000000000"
      assert result.data.name == "District 1"

      result_bare = PoliticalDistrictJSON.show(district)
      assert result_bare.data.id == "01HXYZCHILD00000000000000"
    end

    test "index/1 formats list of districts" do
      district = %PoliticalDistrict{
        id: "01HXYZCHILD00000000000000",
        name: "District 1",
        level: 1,
        parent: nil
      }

      result = PoliticalDistrictJSON.index(%{districts: [district]})
      assert length(result.data) == 1
      assert hd(result.data).name == "District 1"

      result_list = PoliticalDistrictJSON.index([district])
      assert length(result_list.data) == 1
    end
  end
end
