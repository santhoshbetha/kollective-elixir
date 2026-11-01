# lib/kollective_web/controllers/relationship_controller.ex
defmodule KollectiveWeb.RelationshipController do
  use KollectiveWeb, :controller

  alias Kollective.Accounts.{Accounts, Users, UserRelationship}
  alias Kollective.Repo
  alias KollectiveWeb.Plugs.AuthorizeOrgSocialAction

  plug AuthorizeOrgSocialAction when action in [:toggle]

  # ─── ACTION 1: LIST ACTIVE SYSTEM BLOCKS / MUTES (SETTINGS VIEWPORTS) ───
  # GET /api/v1/relationships
  # Expected params: ?type=block or ?type=mute
  def index(conn, %{"type" => type}) when type in ["block", "mute"] do
    user = conn.assigns.current_user

    # 1. Fetch matching user profile entities in exactly one query pass
    flagged_users = Users.list_related_users(user.id, type)

    conn
    |> put_status(:ok)
    # 2. Phoenix 1.7 approach: Format via your unified AccountJSON module contract
    |> json(%{
      status: "success",
      data:
        KollectiveWeb.AccountJSON.index(%{
          users: flagged_users,
          for: user,
          embed_relationships: true,
          skip_visibility_check: true
        })
    })
  end

  def index(conn, _),
    do: conn |> put_status(:bad_request) |> json(%{error: "Invalid relationship listing type."})

  # ─── ACTION 2: UNIVERSAL SOCIAL GRAPH TOGGLE LINK SWITCHER ───
  # POST /api/v1/relationships/toggle
  # Expected payload: %{"target_id" => "01J0A..." or "username", "type" => "follow" | "block" | "mute"}
  def toggle(conn, %{"target_id" => target_id, "type" => type})
      when type in ["follow", "block", "mute"] do
    actor =
      if conn.assigns[:account_type] == :organization and conn.assigns[:current_organization] do
        conn.assigns[:current_organization]
      else
        conn.assigns.current_user
      end

    target_user = Accounts.get_user_profile(target_id)
    target_user_id = if target_user, do: target_user.id, else: target_id

    # Prevent users from triggering self-referencing social graph operations
    cond do
      is_nil(target_user) ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User account not found."})

      actor.id == target_user.id ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Self-referencing actions are blocked."})

      true ->
        # Routes directly through your unified atomic Ecto.Multi context wrappers
        case Users.toggle_relationship(actor, target_user_id, type) do
          {:ok, :created} ->
            json(conn, %{
              status: "success",
              action: "inserted",
              following: type == "follow",
              relationship_state: type,
              message: "Action successfully recorded."
            })

          {:ok, :deleted} ->
            json(conn, %{
              status: "success",
              action: "removed",
              following: false,
              relationship_state: "none",
              message: "Action successfully cleared."
            })

          {:error, _changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Transaction failed to map parameters."})
        end
    end
  end

  def toggle(conn, _),
    do:
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Prohibited configuration signature."})

  # ─── ACTION 3: EXPLICIT FOLLOW ACCOUNT (REST / MASTODON COMPATIBLE) ───
  # POST /api/v1/accounts/:id/follow
  def follow_account(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    target_user = Accounts.get_user_profile(id)

    cond do
      is_nil(target_user) ->
        conn |> put_status(:not_found) |> json(%{error: "Account not found."})

      user.id == target_user.id ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "You cannot follow yourself."})

      true ->
        case Repo.get_by(UserRelationship,
               source_id: user.id,
               target_id: target_user.id,
               type: "follow"
             ) do
          nil ->
            case Users.toggle_relationship(user, target_user.id, "follow") do
              {:ok, _} ->
                json(conn, %{
                  id: target_user.id,
                  username: target_user.username,
                  following: true,
                  relationship_state: "follow",
                  status: "success"
                })

              {:error, _} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: "Could not follow user."})
            end

          _existing ->
            json(conn, %{
              id: target_user.id,
              username: target_user.username,
              following: true,
              relationship_state: "follow",
              status: "success"
            })
        end
    end
  end

  # ─── ACTION 4: EXPLICIT UNFOLLOW ACCOUNT (REST / MASTODON COMPATIBLE) ───
  # POST /api/v1/accounts/:id/unfollow
  def unfollow_account(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    target_user = Accounts.get_user_profile(id)

    cond do
      is_nil(target_user) ->
        conn |> put_status(:not_found) |> json(%{error: "Account not found."})

      true ->
        case Repo.get_by(UserRelationship,
               source_id: user.id,
               target_id: target_user.id,
               type: "follow"
             ) do
          nil ->
            json(conn, %{
              id: target_user.id,
              username: target_user.username,
              following: false,
              relationship_state: "none",
              status: "success"
            })

          _existing ->
            case Users.toggle_relationship(user, target_user.id, "follow") do
              {:ok, _} ->
                json(conn, %{
                  id: target_user.id,
                  username: target_user.username,
                  following: false,
                  relationship_state: "none",
                  status: "success"
                })

              {:error, _} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: "Could not unfollow user."})
            end
        end
    end
  end

  # ─── ACTION 5: EXPLICIT MUTE / UNMUTE ACCOUNT ───
  # POST /api/v1/accounts/:id/mute
  def mute_account(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    target_user = Accounts.get_user_profile(id)

    cond do
      is_nil(target_user) ->
        conn |> put_status(:not_found) |> json(%{error: "Account not found."})

      user.id == target_user.id ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "You cannot mute yourself."})

      true ->
        case Users.mute_user(user, target_user) do
          {:ok, _} ->
            json(conn, %{
              id: target_user.id,
              username: target_user.username,
              muting: true,
              relationship_state: "mute",
              status: "success",
              success: true
            })

          {:error, _} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Could not mute user."})
        end
    end
  end

  # POST /api/v1/accounts/:id/unmute
  def unmute_account(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    target_user = Accounts.get_user_profile(id)

    cond do
      is_nil(target_user) ->
        conn |> put_status(:not_found) |> json(%{error: "Account not found."})

      true ->
        _ = Users.unmute_user(user, target_user)

        json(conn, %{
          id: target_user.id,
          username: target_user.username,
          muting: false,
          relationship_state: "none",
          status: "success",
          success: true
        })
    end
  end

  # ─── ACTION 6: EXPLICIT BLOCK / UNBLOCK ACCOUNT ───
  # POST /api/v1/accounts/:id/block
  def block_account(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    target_user = Accounts.get_user_profile(id)

    cond do
      is_nil(target_user) ->
        conn |> put_status(:not_found) |> json(%{error: "Account not found."})

      user.id == target_user.id ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "You cannot block yourself."})

      true ->
        case Users.block_user(user, target_user) do
          {:ok, _} ->
            json(conn, %{
              id: target_user.id,
              username: target_user.username,
              blocking: true,
              following: false,
              followed_by: false,
              relationship_state: "block",
              status: "success",
              success: true
            })

          {:error, _} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Could not block user."})
        end
    end
  end

  # POST /api/v1/accounts/:id/unblock
  def unblock_account(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    target_user = Accounts.get_user_profile(id)

    cond do
      is_nil(target_user) ->
        conn |> put_status(:not_found) |> json(%{error: "Account not found."})

      true ->
        _ = Users.unblock_user(user, target_user)

        json(conn, %{
          id: target_user.id,
          username: target_user.username,
          blocking: false,
          relationship_state: "none",
          status: "success",
          success: true
        })
    end
  end

  # GET /api/v1/blocks
  def blocks_index(conn, _params) do
    index(conn, %{"type" => "block"})
  end

  # GET /api/v1/mutes
  def mutes_index(conn, _params) do
    index(conn, %{"type" => "mute"})
  end

  # GET /api/v1/privacy/blocks
  def privacy_blocks_index(conn, _params) do
    user = conn.assigns.current_user
    flagged_users = Users.list_related_users(user.id, "block")

    serialized =
      KollectiveWeb.AccountJSON.index(%{
        users: flagged_users,
        for: user,
        embed_relationships: true,
        skip_visibility_check: true
      })
      |> Enum.map(fn u ->
        Map.merge(u, %{
          name: Map.get(u, :name) || Map.get(u, :display_name) || Map.get(u, :username),
          handle: Map.get(u, :handle) || "@#{Map.get(u, :username)}"
        })
      end)

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      blocked_users: serialized,
      data: serialized
    })
  end

  # GET /api/v1/privacy/mutes
  def privacy_mutes_index(conn, _params) do
    user = conn.assigns.current_user
    flagged_users = Users.list_related_users(user.id, "mute")

    serialized =
      KollectiveWeb.AccountJSON.index(%{
        users: flagged_users,
        for: user,
        embed_relationships: true,
        skip_visibility_check: true
      })
      |> Enum.map(fn u ->
        Map.merge(u, %{
          name: Map.get(u, :name) || Map.get(u, :display_name) || Map.get(u, :username),
          handle: Map.get(u, :handle) || "@#{Map.get(u, :username)}"
        })
      end)

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      muted_users: serialized,
      data: serialized
    })
  end

  # DELETE /api/v1/privacy/blocks/:account_id
  def privacy_unblock_account(conn, %{"account_id" => account_id}) do
    user = conn.assigns.current_user

    case Accounts.get_user_profile(account_id) do
      nil ->
        conn |> put_status(:ok) |> json(%{success: true, status: "success"})

      target_user ->
        _ = Users.unblock_user(user, target_user)

        conn
        |> put_status(:ok)
        |> json(%{
          success: true,
          status: "success",
          id: target_user.id,
          blocking: false,
          relationship_state: "none"
        })
    end
  end

  # DELETE /api/v1/privacy/mutes/:account_id
  def privacy_unmute_account(conn, %{"account_id" => account_id}) do
    user = conn.assigns.current_user

    case Accounts.get_user_profile(account_id) do
      nil ->
        conn |> put_status(:ok) |> json(%{success: true, status: "success"})

      target_user ->
        _ = Users.unmute_user(user, target_user)

        conn
        |> put_status(:ok)
        |> json(%{
          success: true,
          status: "success",
          id: target_user.id,
          muting: false,
          relationship_state: "none"
        })
    end
  end
end
