# test/kollective_web/controllers/emoji_json_test.exs
defmodule KollectiveWeb.EmojiJSONTest do
  use KollectiveWeb.ConnCase, async: true

  alias KollectiveWeb.EmojiJSON

  describe "EmojiJSON serialization" do
    test "grouped/1 organizes emojis by category" do
      emojis = [
        %{
          shortcode: "party_parrot",
          url: "https://example.com/parrot.gif",
          static_url: nil,
          category: "Animals"
        },
        %{
          shortcode: "rocket",
          url: "https://example.com/rocket.png",
          static_url: "https://example.com/rocket.png",
          category: "Objects"
        },
        %{
          shortcode: "custom_logo",
          url: "https://example.com/logo.png",
          static_url: nil,
          category: nil
        }
      ]

      result = EmojiJSON.grouped(emojis)

      assert result.status == "success"
      categories = result.categories

      assert Map.has_key?(categories, "Animals")
      assert Map.has_key?(categories, "Objects")
      assert Map.has_key?(categories, "Custom")

      [parrot] = categories["Animals"]
      assert parrot.shortcode == "party_parrot"
      assert parrot.static_url == "https://example.com/parrot.gif"
    end

    test "data/1 handles single emoji map" do
      item = %{
        shortcode: "fire",
        url: "https://example.com/fire.png",
        static_url: "https://example.com/fire_s.png"
      }

      data = EmojiJSON.data(item)

      assert data.shortcode == "fire"
      assert data.url == "https://example.com/fire.png"
      assert data.static_url == "https://example.com/fire_s.png"
    end
  end
end
