defmodule Kollective.Workers.VoiceBroadcastWorker do
  use Oban.Worker, queue: :notifications
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Accounts.User
  alias Kollective.Notifications.Notification

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "post_id" => post_id,
          "district" => district,
          "country" => country,
          "author_id" => author_id
        }
      }) do
    # 1. Find all users in that specific Federal District (excluding the author)
    user_ids =
      from(u in User,
        where: u.district_l1 == ^district and u.country == ^country,
        where: u.id != ^author_id,
        select: u.id
      )
      |> Repo.all()

    # 2. Batch insert notifications
    timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

    notifications =
      Enum.map(user_ids, fn user_id ->
        %{
          user_id: user_id,
          actor_id: author_id,
          post_id: post_id,
          type: "voice_alert",
          inserted_at: timestamp,
          updated_at: timestamp
        }
      end)

    # Insert all at once (Postgres limit is usually ~65k parameters)
    Repo.insert_all(Notification, notifications)

    :ok
  end
end
