defmodule KollectiveWeb.ActionControllerTest do
  use KollectiveWeb.ConnCase, async: true

  import Kollective.Factory

  describe "unauthenticated action endpoints" do
    test "GET /api/v1/actions returns 401", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/actions")
      assert conn.status == 401
      assert json_response(conn, 401)["message"] =~ "must log in"
    end

    test "POST /api/v1/actions returns 401", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/actions", %{})
      assert conn.status == 401
      assert json_response(conn, 401)["message"] =~ "must log in"
    end
  end

  describe "authenticated action endpoints" do
    setup :authenticate_user

    test "GET /api/v1/actions lists collective actions filtered by scope and category", %{
      conn: conn,
      user: user
    } do
      city = insert(:city)
      user = user |> Ecto.Changeset.change(%{city_id: city.id}) |> Kollective.Repo.update!()
      conn = assign(conn, :current_user, user)

      # Insert events with collective action categories
      event1 =
        insert(:event,
          user: user,
          category: "protest",
          target_scope: :local,
          origin_city: city,
          origin_city_id: city.id,
          timezone: "UTC",
          event_status: "published",
          title: "March for climate change",
          start_time: DateTime.utc_now()
        )

      event2 =
        insert(:event,
          user: user,
          category: "rally",
          target_scope: :local,
          origin_city: city,
          origin_city_id: city.id,
          timezone: "UTC",
          event_status: "published",
          title: "Local candidate rally",
          start_time: DateTime.utc_now()
        )

      # Standard informational event (should NOT be returned in list_collective_actions)
      _event3 =
        insert(:event,
          user: user,
          category: "standard",
          target_scope: :local,
          origin_city: city,
          origin_city_id: city.id,
          timezone: "UTC",
          event_status: "published",
          title: "Standard board meeting",
          start_time: DateTime.utc_now()
        )

      response =
        conn
        |> get(~p"/api/v1/actions", %{"category" => "protest", "scope" => "local"})
        |> json_response(200)

      assert response["status"] == "success"
      assert is_list(response["data"])
      assert length(response["data"]) == 1
      assert hd(response["data"])["id"] == to_string(event1.id)

      response_all =
        conn
        |> get(~p"/api/v1/actions", %{"category" => "all", "scope" => "local"})
        |> json_response(200)

      ids = Enum.map(response_all["data"], & &1["id"])
      assert to_string(event1.id) in ids
      assert to_string(event2.id) in ids
    end

    test "POST /api/v1/actions successfully launches a new grassroots action", %{
      conn: conn,
      user: _user
    } do
      params = %{
        "event" => %{
          "title" => "Rally for Civic Awareness",
          "description" => "Let us coordinate and raise awareness.",
          "category" => "protest",
          "participation_format" => "in_person",
          "join_mode" => "free",
          "location_name" => "Main Plaza Town Hall Square",
          "street" => "789 Plaza St",
          "start_time" =>
            DateTime.utc_now() |> DateTime.add(7200, :second) |> DateTime.to_iso8601()
        }
      }

      response =
        conn
        |> post(~p"/api/v1/actions", params)
        |> json_response(201)

      assert response["status"] == "success"
      assert response["message"] =~ "Grassroots action successfully initiated"
      assert response["data"]["name"] == "Rally for Civic Awareness"
      assert response["data"]["category"] == "protest"
    end

    test "POST /api/v1/actions allows creating an online action without physical venue or address", %{
      conn: conn
    } do
      params = %{
        "action" => %{
          "title" => "Digital Privacy Coalition Strategy Call",
          "description" => "Coordinate decentralized digital security efforts across states.",
          "category" => "meeting",
          "participation_format" => "online_virtual",
          "join_mode" => "free",
          "meetingLink" => "https://kollective.social/stream/digital-privacy",
          "start_time" =>
            DateTime.utc_now() |> DateTime.add(7200, :second) |> DateTime.to_iso8601()
        }
      }

      response =
        conn
        |> post(~p"/api/v1/actions", params)
        |> json_response(201)

      assert response["status"] == "success"
      assert response["data"]["name"] == "Digital Privacy Coalition Strategy Call"
      assert response["data"]["type"] == "Meeting"
      assert response["data"]["meetingLink"] == "https://kollective.social/stream/digital-privacy"
      assert response["data"]["address"] == nil
    end

    test "POST /api/v1/actions fails validation when creating an in-person action without venue or address", %{
      conn: conn
    } do
      params = %{
        "action" => %{
          "title" => "Direct Action In-Person Gathering",
          "description" => "Assembling for community justice.",
          "category" => "protest",
          "participation_format" => "in_person",
          "join_mode" => "free",
          "start_time" =>
            DateTime.utc_now() |> DateTime.add(7200, :second) |> DateTime.to_iso8601()
        }
      }

      response =
        conn
        |> post(~p"/api/v1/actions", params)
        |> json_response(422)

      assert Map.has_key?(response, "errors")
      assert Map.has_key?(response["errors"], "location_name") or
               Map.has_key?(response["errors"], "street")
    end

    test "GET /api/v1/actions filters by 60-mile radius PostGIS boundary for local vs state vs country", %{
      conn: conn,
      user: user
    } do
      # Set user location in Austin, TX
      user =
        user
        |> Ecto.Changeset.change(%{
          location: "POINT(-97.7431 30.2672)",
          state: "TX",
          country: "US",
          city_id: nil
        })
        |> Kollective.Repo.update!()

      conn = assign(conn, :current_user, user)

      # Action 1: Austin, TX (0 miles away - strictly local)
      local_action =
        insert(:event,
          user: user,
          category: "protest",
          target_scope: :local,
          title: "Austin Housing Rights Rally",
          event_status: "published",
          origin_state: "TX",
          origin_country: "US",
          timezone: "UTC",
          start_time: DateTime.utc_now() |> DateTime.add(86400, :second),
          location: %Geo.Point{coordinates: {-97.7431, 30.2672}, srid: 4326}
        )

      # Action 2: San Antonio, TX (~75 miles away - outside 60-mile local radius, but in TX)
      state_action =
        insert(:event,
          user: user,
          category: "rally",
          target_scope: :state,
          title: "San Antonio Workers Assembly",
          event_status: "published",
          origin_state: "TX",
          origin_country: "US",
          timezone: "UTC",
          start_time: DateTime.utc_now() |> DateTime.add(86400 * 2, :second),
          location: %Geo.Point{coordinates: {-98.4936, 29.4241}, srid: 4326}
        )

      # Action 3: San Francisco, CA (out of state - country/world level)
      country_action =
        insert(:event,
          user: user,
          category: "town_hall",
          target_scope: :world,
          title: "Pacific Coastal Ecology Forum",
          event_status: "published",
          origin_state: "CA",
          origin_country: "US",
          timezone: "UTC",
          start_time: DateTime.utc_now() |> DateTime.add(86400 * 3, :second),
          location: %Geo.Point{coordinates: {-122.4194, 37.7749}, srid: 4326}
        )

      # 1. Local scope: only Austin action within 60 miles
      local_resp =
        conn
        |> get(~p"/api/v1/actions", %{"scope" => "local"})
        |> json_response(200)

      local_ids = Enum.map(local_resp["data"], & &1["id"])
      assert to_string(local_action.id) in local_ids
      refute to_string(state_action.id) in local_ids
      refute to_string(country_action.id) in local_ids

      # 2. State scope: both Austin and San Antonio actions (in TX), not CA
      state_resp =
        conn
        |> get(~p"/api/v1/actions", %{"scope" => "state"})
        |> json_response(200)

      state_ids = Enum.map(state_resp["data"], & &1["id"])
      assert to_string(local_action.id) in state_ids
      assert to_string(state_action.id) in state_ids
      refute to_string(country_action.id) in state_ids

      # 3. Country scope: all three actions within US
      country_resp =
        conn
        |> get(~p"/api/v1/actions", %{"scope" => "country"})
        |> json_response(200)

      country_ids = Enum.map(country_resp["data"], & &1["id"])
      assert to_string(local_action.id) in country_ids
      assert to_string(state_action.id) in country_ids
      assert to_string(country_action.id) in country_ids
    end

    test "GET /api/v1/actions/:id returns action details", %{conn: conn, user: user} do
      action =
        insert(:event,
          user: user,
          category: "protest",
          target_scope: :local,
          timezone: "UTC",
          event_status: "published",
          title: "Public Rally for Climate",
          description: "Full description of the climate rally.",
          location_name: "Capitol Grounds",
          street: "1100 Congress Ave",
          start_time: DateTime.utc_now()
        )

      response =
        conn
        |> get(~p"/api/v1/actions/#{action.id}")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["data"]["id"] == to_string(action.id)
      assert response["data"]["title"] == "Public Rally for Climate"
      assert response["data"]["description"] == "Full description of the climate rally."
      assert response["data"]["rsvp"] == "None"
    end

    test "POST /api/v1/actions/:id/rsvp toggles Attend and Interested states", %{
      conn: conn,
      user: user
    } do
      action =
        insert(:event,
          user: user,
          category: "town_hall",
          target_scope: :local,
          timezone: "UTC",
          event_status: "published",
          title: "Community Town Hall",
          start_time: DateTime.utc_now()
        )

      # 1. Attend action
      resp_attend =
        conn
        |> post(~p"/api/v1/actions/#{action.id}/rsvp", %{"status" => "Attending"})
        |> json_response(200)

      assert resp_attend["status"] == "success"
      assert resp_attend["isAttending"] == true
      assert resp_attend["rsvp"] == "Attending"

      # 2. Check GET /actions shows updated user_rsvp_status
      get_resp =
        conn
        |> get(~p"/api/v1/actions", %{"scope" => "all"})
        |> json_response(200)

      action_in_list = Enum.find(get_resp["data"], &(&1["id"] == to_string(action.id)))
      assert action_in_list["rsvp"] == "Attending"
      assert action_in_list["user_rsvp_status"] == "Attending"

      # 3. Switch to Interested
      resp_interest =
        conn
        |> post(~p"/api/v1/actions/#{action.id}/rsvp", %{"status" => "Interested"})
        |> json_response(200)

      assert resp_interest["status"] == "success"
      assert resp_interest["isInterested"] == true
      assert resp_interest["isAttending"] == false
      assert resp_interest["rsvp"] == "Interested"

      # 4. Remove RSVP (None)
      resp_remove =
        conn
        |> post(~p"/api/v1/actions/#{action.id}/rsvp", %{"status" => "None"})
        |> json_response(200)

      assert resp_remove["status"] == "success"
      assert resp_remove["code"] == "removed"
      assert resp_remove["isAttending"] == false
      assert resp_remove["isInterested"] == false
      assert resp_remove["rsvp"] == "None"
    end

    test "POST /api/v1/actions/:id/rsvp blocks organization non-admins with 403 and permits admins", %{
      conn: _conn,
      user: user
    } do
      action =
        insert(:event,
          user: user,
          category: "protest",
          target_scope: :local,
          event_status: "published",
          title: "Protest Action",
          start_time: DateTime.utc_now()
        )

      org = insert(:user, type: :organization, username: "clean_org_#{System.unique_integer([:positive])}")

      # 1. Non-admin member (contributor)
      non_admin = insert(:user, username: "non_admin_#{System.unique_integer([:positive])}")
      {:ok, _membership} =
        Kollective.Repo.insert(%Kollective.Accounts.OrganizationMembership{
          user_id: non_admin.id,
          organization_id: org.id,
          role: :contributor,
          status: :approved
        })

      non_admin_token = Kollective.Accounts.Accounts.generate_organization_session_token(non_admin, org.id)

      resp_non_admin =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{non_admin_token}")
        |> post(~p"/api/v1/actions/#{action.id}/rsvp", %{"status" => "Attending"})

      assert resp_non_admin.status == 403
      json = json_response(resp_non_admin, 403)
      assert json["error"] == "forbidden"
      assert json["message"] =~ "Only administrators can perform social actions"

      # 2. Admin member
      {:ok, _admin_membership} =
        Kollective.Repo.insert(%Kollective.Accounts.OrganizationMembership{
          user_id: user.id,
          organization_id: org.id,
          role: :admin,
          status: :approved
        })

      admin_token = Kollective.Accounts.Accounts.generate_organization_session_token(user, org.id)

      resp_admin =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{admin_token}")
        |> post(~p"/api/v1/actions/#{action.id}/rsvp", %{"status" => "Attending"})

      assert resp_admin.status == 200
      admin_json = json_response(resp_admin, 200)
      assert admin_json["status"] == "success"
    end
  end
end

