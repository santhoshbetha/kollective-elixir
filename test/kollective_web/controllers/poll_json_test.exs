# test/kollective_web/controllers/poll_json_test.exs
defmodule KollectiveWeb.PollJSONTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Polls.Poll
  alias Kollective.Polls.PollOption
  alias KollectiveWeb.PollJSON

  describe "PollJSON serialization" do
    test "data/1 formats poll with options and percentages" do
      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      options = [
        %PollOption{id: "01OPT100000000000000000000", title: "Option A", votes_count: 3},
        %PollOption{id: "01OPT200000000000000000000", title: "Option B", votes_count: 1}
      ]

      poll = %Poll{
        id: "01HXYZPOLL0000000000000000",
        expires_at: future,
        expired: false,
        multiple: false,
        non_anonymous: true,
        votes_count: 4,
        options: options
      }

      data = PollJSON.data(poll)

      assert data.id == "01HXYZPOLL0000000000000000"
      assert data.votes_count == 4
      assert data.expired == false
      assert data.multiple == false
      assert data.non_anonymous == true
      assert length(data.options) == 2

      [opt1, opt2] = data.options
      assert opt1.title == "Option A"
      assert opt1.votes_count == 3
      assert opt1.percent == 75.0

      assert opt2.title == "Option B"
      assert opt2.votes_count == 1
      assert opt2.percent == 25.0
    end

    test "data/1 handles empty options and 0 votes gracefully" do
      poll = %Poll{
        id: "01HXYZPOLL0000000000000000",
        expires_at: ~U[2026-01-01 00:00:00Z],
        expired: true,
        multiple: false,
        non_anonymous: false,
        votes_count: 0,
        options: []
      }

      data = PollJSON.data(poll)
      assert data.options == []
      assert data.votes_count == 0
      assert data.expired == true
    end

    test "show/1 wraps data under %{data: ...}" do
      poll = %Poll{
        id: "01HXYZPOLL0000000000000000",
        expires_at: ~U[2026-01-01 00:00:00Z],
        options: []
      }

      result = PollJSON.show(%{poll: poll})
      assert result.data.id == "01HXYZPOLL0000000000000000"
    end
  end
end
