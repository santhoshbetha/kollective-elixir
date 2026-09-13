# test/kollective_web/controllers/emoji_controller_test.exs
defmodule KollectiveWeb.EmojiControllerTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Repo
  alias Kollective.Posts.CustomEmoji

  setup %{conn: conn} do
    user = Kollective.Factory.insert(:user)

    authenticated_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:current_scope, %{user: user})

    {:ok, conn: authenticated_conn, user: user}
  end

  describe "index/2 (GET /api/v1/custom_emojis)" do
    test "returns grouped custom emojis serialized via EmojiJSON", %{conn: conn} do
      %CustomEmoji{
        shortcode: "party_parrot",
        url: "https://r2.dev/parrot.gif",
        static_url: "https://r2.dev/parrot.png",
        category: "Animals"
      }
      |> Repo.insert!()

      response =
        conn
        |> get(~p"/api/v1/custom_emojis")
        |> json_response(200)

      assert response["status"] == "success"
      assert is_map(response["categories"])
      assert Map.has_key?(response["categories"], "Animals")

      [parrot] = response["categories"]["Animals"]
      assert parrot["shortcode"] == "party_parrot"
      assert parrot["url"] == "https://r2.dev/parrot.gif"
    end
  end
end
