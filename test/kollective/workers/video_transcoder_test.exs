defmodule Kollective.Workers.VideoTranscoderTest do
  use Kollective.DataCase, async: true
  use Oban.Testing, repo: Kollective.Repo

  alias Kollective.Workers.VideoTranscoder
  alias Kollective.Posts.{Post, PostAttachment}
  alias Kollective.Repo
  import Kollective.Factory

  test "enqueues an Oban job in the media queue" do
    job = VideoTranscoder.new(%{"attachment_id" => "fake_id"})
    assert job.changes.queue == "media"
    assert job.changes.max_attempts == 3
    assert job.changes.args == %{"attachment_id" => "fake_id"}
  end

  test "perform/1 handles transcoding error gracefully when binary is missing or file invalid" do
    user = insert(:user)
    post = insert(:post, author: user, processing_status: :pending)

    attachment =
      Repo.insert!(%PostAttachment{
        id: Ecto.ULID.generate(),
        url: "https://example.com/test_video.mp4",
        media_type: "video/mp4",
        description: "Test video",
        user_id: user.id,
        post_id: post.id,
        is_processed: false
      })

    # Subscribe to PubSub notifications
    Phoenix.PubSub.subscribe(Kollective.PubSub, "post_details:#{post.id}")

    job = %Oban.Job{args: %{"attachment_id" => attachment.id}}
    result = VideoTranscoder.perform(job)

    # Should return an error tuple and update processing_status to failed
    assert {:error, _} = result
    updated_post = Repo.get!(Post, post.id)
    assert updated_post.processing_status == :failed

    assert_received :video_failed
  end

  test "perform/1 raises if attachment does not exist" do
    job = %Oban.Job{args: %{"attachment_id" => Ecto.ULID.generate()}}

    assert_raise Ecto.NoResultsError, fn ->
      VideoTranscoder.perform(job)
    end
  end
end
