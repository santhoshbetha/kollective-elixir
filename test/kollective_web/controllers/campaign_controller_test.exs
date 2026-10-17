defmodule KollectiveWeb.CampaignControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Videos.CandidateVideo

  setup %{conn: conn} do
    user = insert(:user, is_candidate: true)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:current_user_id, user.id)
      |> assign(:user, user)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, user: user}
  end

  describe "CampaignController index_pitches" do
    test "streams ranked pitches for district and stage", %{conn: conn, user: user} do
      video =
        %CandidateVideo{
          office_level: "municipal",
          district_code: "austin_tx",
          sub_local_name: "City Council Place 1",
          video_url: "https://example.com/pitch.mp4",
          votes_count: 10,
          user_id: user.id
        }
        |> Repo.insert!()

      conn = get(conn, ~p"/api/v1/campaigns/pitches", %{"level" => "municipal", "code" => "austin_tx", "stage" => "public"})
      assert json = json_response(conn, 200)
      assert is_list(json)
      ids = Enum.map(json, & &1["id"])
      assert to_string(video.id) in ids
    end
  end

  describe "CampaignController vote_pitch" do
    test "increments pitch vote count atomically", %{conn: conn, user: user} do
      video =
        %CandidateVideo{
          office_level: "municipal",
          district_code: "austin_tx",
          sub_local_name: "City Council Place 1",
          video_url: "https://example.com/pitch.mp4",
          votes_count: 5,
          user_id: user.id
        }
        |> Repo.insert!()

      conn = post(conn, ~p"/api/v1/campaigns/pitches/#{video.id}/vote", %{"delta" => 1})
      assert json_response(conn, 200)["votes_count"] == 6

      reloaded = Repo.get!(CandidateVideo, video.id)
      assert reloaded.votes_count == 6
    end

    test "decrements pitch vote count with delta -1", %{conn: conn, user: user} do
      video =
        %CandidateVideo{
          office_level: "municipal",
          district_code: "austin_tx",
          sub_local_name: "City Council Place 1",
          video_url: "https://example.com/pitch.mp4",
          votes_count: 5,
          user_id: user.id
        }
        |> Repo.insert!()

      conn = post(conn, ~p"/api/v1/campaigns/pitches/#{video.id}/vote", %{"delta" => -1})
      assert json_response(conn, 200)["votes_count"] == 4
    end

    test "returns 404 for non-existent video id", %{conn: conn} do
      fake_id = Ecto.ULID.generate()
      conn = post(conn, ~p"/api/v1/campaigns/pitches/#{fake_id}/vote", %{"delta" => 1})
      assert json_response(conn, 404)["error"] =~ "unresolved"
    end
  end
end
