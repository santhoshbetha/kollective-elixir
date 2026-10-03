defmodule KollectiveWeb.Presence do
  @moduledoc """
  ⚡ REAL-TIME DISTRIBUTED PRESENCE TRACKER
  Manages clustering active-user tracking nodes across channels natively.
  """
  use Phoenix.Presence,
    otp_app: :kollective,
    pubsub_server: Kollective.PubSub

  alias Kollective.Accounts.Accounts

  @doc """
  Metadata Fetch Enhancer Interceptor.
  Automatically intercepts raw socket IDs tracked in memory and preloads
  rich user records (usernames, avatars) in a single database pass [INDEX].
  """
  def fetch(_topic, presences) do
    # 1. Extract all active user IDs from the map keys
    user_ids = Map.keys(presences)

    # 2. Single-pass batch query to avoid heavy N+1 database operations
    users_maps =
      if user_ids != [] do
        Accounts.list_users_by_ids(user_ids)
        |> Map.new(fn user -> {to_string(user.id), user} end)
      else
        %{}
      end

    # 3. Decorate the presence metadata payload with readable UI fields
    for {user_id, %{metas: metas}} <- presences, into: %{} do
      user = Map.get(users_maps, user_id)

      meta_decoration = %{
        username: (user && user.username) || "anonymous",
        avatar: (user && user.avatar_url) || "/default-avatar.jpg",
        badge_type: (user && user.badge_type) || "citizen",
        online_at: inspect(System.system_time(:second))
      }

      # Merge the profile decoration maps into every active device socket meta
      decorated_metas = Enum.map(metas, &Map.merge(&1, meta_decoration))

      {user_id, %{metas: decorated_metas}}
    end
  end
end
