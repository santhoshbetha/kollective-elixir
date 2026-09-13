# test/kollective_web/controllers/hashtag_json_test.exs
defmodule KollectiveWeb.HashtagJSONTest do
  use KollectiveWeb.ConnCase, async: true

  alias KollectiveWeb.HashtagJSON

  describe "HashtagJSON serialization" do
    test "trending/1 serializes list of trending tags" do
      tags = [
        %{id: "01TAG1", name: "elixir", score: 100},
        %{id: "01TAG2", name: "phoenix", trending_score: 85}
      ]

      result = HashtagJSON.trending(tags)

      assert %{data: items} = result
      assert length(items) == 2

      [tag1, tag2] = items
      assert tag1.name == "elixir"
      assert tag1.score == 100
      assert tag2.name == "phoenix"
      assert tag2.score == 85
    end

    test "missing_tag_error/0 returns structured 400 error map" do
      err = HashtagJSON.missing_tag_error()

      assert err.status == "error"
      assert err.code == "missing_tag_parameter"
      assert err.message =~ "provide a valid 'tag'"
    end
  end
end
