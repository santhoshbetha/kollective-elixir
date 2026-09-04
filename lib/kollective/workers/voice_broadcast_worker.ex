defmodule Kollective.Workers.VoiceBroadcastWorker do
  use Oban.Worker, queue: :notifications
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Accounts.User
  alias Kollective.Posts.Post
  alias Kollective.Notifications.Notification

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"post_id" => post_id, "author_id" => author_id}}) do
    # 1. Fetch the post to read its true computed origin targeting bounds
    case Repo.get(Post, post_id) do
      nil ->
        # Gracefully handle race condition if post was deleted before worker ran
        :ok

      post ->
        # 2. Query target audience by matching against overlapping dynamic district fields
        user_ids = fetch_targeted_user_ids(post, author_id)

        if length(user_ids) > 0 do
          timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

          # 3. Build state schemas for structural batch persistence
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

          # Batch insert to PostgreSQL safely
          Repo.insert_all(Notification, notifications)

          # 4. 📣 REAL-TIME WEBSOCKET PUSH
          # Broadcast out to individual user notification streams
          socket_payload = %{
            id: System.unique_integer([:positive]),
            type: "voice_alert",
            post_id: post_id,
            message: "A high-priority voice broadcast was issued in your district!",
            created_at: timestamp
          }

          Enum.each(user_ids, fn user_id ->
            Phoenix.PubSub.broadcast(
              Kollective.PubSub,
              "user_notifications:#{user_id}",
              {:new_notification, socket_payload}
            )
          end)
        end

        :ok
    end
  end

  # --- Private Query Helpers ---

  defp fetch_targeted_user_ids(post, author_id) do
    # Start with a base query checking country bounds and ensuring author is omitted
    base_query =
      from(u in User,
        where: u.country == ^post.origin_country,
        where: u.id != ^author_id,
        select: u.id
      )

    # Inject macro logic to check overlapping district bounds dynamically
    base_query
    |> filter_by_districts(post)
    |> Repo.all()
  end

  # If all targeted tiers are blank, fallback safely or limit by state
  defp filter_by_districts(
         query,
         %{origin_district_l1: nil, origin_district_l2: nil, origin_district_l3: nil} = post
       ) do
    if post.origin_state do
      from(u in query, where: u.state == ^post.origin_state)
    else
      query
    end
  end

  # Dynamically evaluate district overlaps using sequential OR statements
  defp filter_by_districts(query, post) do
    # Convert string fields from Post columns to match foreign key integers stored in User columns
    # Your targeting function assigns user.district_l1_id directly to these fields,
    # so we parse or treat them directly as foreign key references.
    l1_target = parse_id(post.origin_district_l1)
    l2_target = parse_id(post.origin_district_l2)
    l3_target = parse_id(post.origin_district_l3)

    from(u in query,
      where:
        (not is_nil(^l1_target) and u.district_l1_id == ^l1_target) or
          (not is_nil(^l2_target) and u.district_l2_id == ^l2_target) or
          (not is_nil(^l3_target) and u.district_l3_id == ^l3_target)
    )
  end

  defp parse_id(nil), do: nil
  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, _} -> int
      :error -> nil
    end
  end
end
