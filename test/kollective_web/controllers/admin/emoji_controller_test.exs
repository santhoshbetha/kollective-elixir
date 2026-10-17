defmodule KollectiveWeb.Admin.AdminEmojiControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Posts.CustomEmoji

  setup %{conn: conn} do
    admin = insert(:user, is_admin: true, is_moderator: true, badge_type: "moderator")

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, admin)
      |> assign(:user, admin)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, admin: admin}
  end

  describe "AdminEmojiController presign" do
    test "generates presigned upload tickets for gif and static preview", %{conn: conn} do
      params = %{
        "shortcode" => "kollective_rocket",
        "content_type" => "image/gif"
      }

      conn = get(conn, ~p"/api/v1/admin/custom_emojis/presign", params)
      assert %{"status" => "success"} = json_response(conn, 200)

      resp = json_response(conn, 200)
      assert resp["upload_url_gif"] =~ "custom_emojis/kollective_rocket.gif"
      assert resp["upload_url_static"] =~ "custom_emojis/kollective_rocket_static.png"
      assert resp["final_url"] =~ "custom_emojis/kollective_rocket.gif"
      assert resp["final_static_url"] =~ "custom_emojis/kollective_rocket_static.png"
    end
  end

  describe "AdminEmojiController create" do
    test "successfully registers new custom emoji into database", %{conn: conn} do
      payload = %{
        "emoji" => %{
          "shortcode" => "super_star",
          "url" => "https://cdn.kollective.app/custom_emojis/super_star.gif",
          "static_url" => "https://cdn.kollective.app/custom_emojis/super_star_static.png",
          "category" => "Achievements"
        }
      }

      conn = post(conn, ~p"/api/v1/admin/custom_emojis", payload)
      assert %{"status" => "success", "data" => data} = json_response(conn, 201)

      assert data["shortcode"] == "super_star"
      assert data["category"] == "Achievements"

      stored = Repo.get_by(CustomEmoji, shortcode: "super_star")
      assert stored != nil
      assert stored.url == "https://cdn.kollective.app/custom_emojis/super_star.gif"
    end

    test "returns 422 when required fields are missing", %{conn: conn} do
      payload = %{
        "emoji" => %{
          "shortcode" => ""
        }
      }

      conn = post(conn, ~p"/api/v1/admin/custom_emojis", payload)
      assert json_response(conn, 422)["errors"] != nil
    end
  end
end
