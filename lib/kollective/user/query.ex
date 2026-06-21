defmodule Kollective.User.Query do
  @moduledoc """
  Standalone User query builder module. Builds query filters dynamically.

    ## Example:
        query = Kollective.User.Query.build(%{username: "alice"})
        another_query = Kollective.User.Query.build(query, %{email: "bob@example.com"})
        Kollective.Repo.all(query)
  """
  import Ecto.Query
  alias Kollective.Config
  alias Kollective.Accounts.User

  @type criteria ::
          %{
            query: String.t(),
            tags: [String.t()],
            name: String.t(),
            email: String.t(),
            local: boolean(),
            external: boolean(),
            active: boolean(),
            deactivated: boolean(),
            need_approval: boolean(),
            unconfirmed: boolean(),
            is_admin: boolean(),
            is_moderator: boolean(),
            is_suggested: boolean(),
            is_discoverable: boolean(),
            super_users: boolean(),
            staff: boolean(),
            is_privileged: atom(),
            invisible: boolean(),
            followers: User.t(),
            friends: User.t(),
            username: [String.t()] | String.t(),
            order_by: term(),
            select: term(),
            limit: pos_integer(),
            birthday_day: pos_integer()
          }
          | map()

  @ilike_criteria [:username, :name, :query]
  @equal_criteria [:email]
  @contains_criteria [:username]

  @spec build(Ecto.Query.t(), criteria()) :: Ecto.Query.t()
  def build(query \\ base_query(), criteria) do
    prepare_query(query, criteria)
  end

   @spec paginate(Ecto.Query.t(), pos_integer(), pos_integer()) :: Ecto.Query.t()
  def paginate(query, page, page_size) do
    from(u in query,
      limit: ^page_size,
      offset: ^((page - 1) * page_size)
    )
  end

  defp base_query do
    from(u in User)
  end

  defp prepare_query(query, criteria) do
    Enum.reduce(criteria, query, &compose_query/2)
  end

  # --- String matching pipelines (Fuzzy or Exact) ---
  defp compose_query({key, value}, query)
       when key in @ilike_criteria and is_binary(value) and value != "" do
    # Treat generic search keyword parameters as a username look-up target
    real_key = if key == :query, do: :username, else: key
    from(u in query, where: ilike(field(u, ^real_key), ^"%#{value}%"))
  end

  defp compose_query({key, value}, query)
       when key in @equal_criteria and is_binary(value) and value != "" do
    from(u in query, where: ^[{key, value}])
  end

  defp compose_query({key, values}, query) when key in @contains_criteria and is_list(values) do
    from(u in query, where: field(u, ^key) in ^values)
  end

  # --- Relationship Graphs (Swapped to your local UserRelationship schema) ---
  defp compose_query({:followers, %User{id: id}}, query) do
      # Users who actively follow this specific account ID
      from(u in query,
        where: u.id != ^id,
        join: r in "user_relationships",
        on: r.target_id == ^id and r.source_id == u.id and r.type == "follow"
      )
    end

    defp compose_query({:friends, %User{id: id}}, query) do
      # Accounts that this specific user explicitly tracks
      from(u in query,
        where: u.id != ^id,
        join: r in "user_relationships",
        on: r.source_id == ^id and r.target_id == u.id and r.type == "follow"
      )
    end

  # --- Structural Permissions & Role Filters (Unified Staff & Super Users) ---
  defp compose_query({:is_admin, bool}, query) do
    from(u in query, where: u.is_admin == ^bool)
  end

  defp compose_query({:is_moderator, bool}, query) do
    from(u in query, where: u.is_moderator == ^bool)
  end

  defp compose_query({:staff, false}, query) do
    from(u in query, where: u.is_admin == false and u.is_moderator == false)
  end

  defp compose_query({key, _}, query) when key in [:super_users, :staff] do
    # Shared fast logic pathway isolating elite elevated workspace actors
    from(u in query, where: u.is_admin == true or u.is_moderator == true)
  end

  # --- Account Status Flags ---
  defp compose_query({:active, false}, query) do
    from(u in query, where: u.is_active == false or u.is_approved == false or u.is_confirmed == false)
  end

  defp compose_query({:active, _}, query) do
    from(u in query,
      where: u.is_active == true and u.is_approved == true and u.is_confirmed == true
    )
  end

  defp compose_query({:deactivated, false}, query) do
    from(u in query, where: u.is_active == true)
  end

  defp compose_query({:deactivated, true}, query) do
    from(u in query, where: u.is_active == false)
  end

  defp compose_query({:confirmation_pending, bool}, query) do
    from(u in query, where: u.is_confirmed != ^bool)
  end

  defp compose_query({:need_approval, false}, query) do
    from(u in query, where: u.is_approved == true)
  end

  defp compose_query({:need_approval, _}, query) do
    from(u in query, where: u.is_approved == false)
  end

  defp compose_query({:unconfirmed, _}, query) do
    from(u in query, where: u.is_confirmed == false)
  end

  # --- Discovery Meta Parameters ---

  defp compose_query({:invisible, bool}, query) when is_boolean(bool) do
    from(u in query, where: u.invisible == ^bool)
  end

  defp compose_query({:is_suggested, bool}, query) do
    from(u in query, where: u.is_suggested == ^bool)
  end

  defp compose_query({:is_discoverable, bool}, query) do
    from(u in query, where: u.is_discoverable == ^bool)
  end

  defp compose_query({:accepts_email_list, bool}, query) do
    from(u in query, where: u.accepts_email_list == ^bool)
  end

  defp compose_query({:tags, tags}, query) when is_list(tags) and length(tags) > 0 do
    from(u in query, where: fragment("? && ?", u.tags, ^tags))
  end

  defp compose_query({:birthday_day, day}, query) do
    from(u in query,
      where: u.show_birthday == true and not is_nil(u.birthday) and fragment("date_part('day', ?)", u.birthday) == ^day
    )
  end

  # --- Formatting and Structural Overrides ---

  defp compose_query({:order_by, key}, query) do
    order_by(query, [u], field(u, ^key))
  end

  defp compose_query({:select, keys}, query) do
    select(query, [u], ^keys)
  end

  defp compose_query({:limit, limit}, query) do
    limit(query, ^limit)
  end

  defp compose_query({:local, _}, query), do: location_query(query, true)
  defp compose_query({:external, _}, query), do: location_query(query, false)

  defp compose_query(_unsupported_param, query), do: query

  defp location_query(query, local) do
    from(u in query, where: u.local == ^local)
  end

end
