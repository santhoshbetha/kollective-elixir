# lib/kollective/workers/comment_mentions_worker.ex
defmodule Kollective.Workers.CommentMentionsWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  import Ecto.Query
  alias Kollective.Repo
  # Adjust to match your application user schema
  alias Kollective.Accounts.User
  # Adjust to match your application comment schema
  alias Kollective.Comments.Comment
  alias Kollective.Notifications.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"comment_id" => comment_id}}) do
    # Fetch the comment with its author details preloaded
    case Repo.get(Comment, comment_id) |> Repo.preload([:user]) do
      nil ->
        {:error, :comment_not_found}

      comment ->
        content_text = comment.content || ""

        if String.trim(content_text) != "" do
          # 1. Extract raw unique username strings
          mentioned_usernames = extract_usernames_from_text(content_text)

          if Enum.any?(mentioned_usernames) do
            # 2. BATCH LOOKUP: Fetch all matching user profiles in a single query pass
            mentioned_users = Repo.all(from u in User, where: u.username in ^mentioned_usernames)

            # 3. Iterate through found users and dispatch alerts via the unified pipeline
            Enum.each(mentioned_users, fn mentioned_user ->
              # SELF-NOTIFICATION GUARD
              if mentioned_user.id != comment.user_id do
                Notifications.notify(
                  mentioned_user.id,
                  comment.user_id,
                  "mention",
                  %{
                    post_id: nil,
                    event_id: comment.event_id,
                    target_id: comment.id,
                    target_type: "Comment"
                  },
                  %{
                    post_id: nil,
                    preview: "✍️ @#{comment.user.username} tagged you in an event discussion."
                  }
                )
              end
            end)
          end
        end

        :ok
    end
  end

  defp extract_usernames_from_text(text) do
    ~r/@([a-zA-Z0-9_]+)/
    |> Regex.scan(text)
    |> Enum.map(fn [_, username] -> String.downcase(username) end)
    |> Enum.uniq()
  end
end
