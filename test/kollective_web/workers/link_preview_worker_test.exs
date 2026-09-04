# test/kollective/workers/link_preview_worker_test.exs
defmodule Kollective.Workers.LinkPreviewWorkerTest do
  use Kollective.DataCase, async: true
  use Oban.Testing, repo: Kollective.Repo
  import Kollective.Factory

  import Mox

  # Make sure mocks verify upon completion of each test
  setup :verify_on_exit!

  test "successfully crawls mock website body and updates the database row" do
    post = insert(:post)
    target_url = "https://example.com"

    # 1. Mock the HTTP response payload cleanly
    Kollective.HTTPClientMock
    |> expect(:get, fn ^target_url, _opts ->
      {:ok,
       %Req.Response{
         status: 200,
         body: """
         <html>
           <head>
             <meta property="og:title" content="Fake Title" />
             <meta property="og:description" content="Fake Description Text" />
           </head>
         </html>
         """
       }}
    end)

    # 2. Programmatically schedule the Oban processing row
    %{"post_id" => post.id, "url" => target_url}
    |> Kollective.Workers.LinkPreviewWorker.new()
    |> Oban.insert!()

    # 3. Drain the queue synchronously within the secure DB connection pool
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :media)

    # 4. Assert the database caches updated successfully
    updated_post = Kollective.Repo.get!(Kollective.Posts.Post, post.id)
    assert updated_post.link_title == "Fake Title"
    assert updated_post.link_description == "Fake Description Text"
  end
end
