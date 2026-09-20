defmodule Kollective.Accounts.Organizations do
  @moduledoc """
  The Organizations context.
  Handles organization membership, invitations, role modifications, and ownership transfers.
  """
  import Ecto.Query, warn: false
  alias Kollective.Repo
  alias Ecto.Multi
  alias Kollective.Accounts.{User, OrganizationMembership}
  alias Kollective.Workers.OrgNotificationWorker
  alias Kollective.Accounts.AuditLog
  alias Kollective.OrganizationMailer

  # Define expiration constant
  @invite_expiry_days 7

  @doc """
  Allows a real-world user to request access to an organization actor profile.
  """
  def request_organization_join(user_id, organization_id) do
    # Verify the target is actually an organization account type
    case Repo.get(User, organization_id) do
      %User{type: :organization} ->
        %OrganizationMembership{}
        |> OrganizationMembership.changeset(%{
          user_id: user_id,
          organization_id: organization_id,
          status: :pending,
          role: :contributor
        })
        |> Repo.insert()

      _ ->
        {:error, :invalid_target_account}
    end
  end

  @doc """
  Allows an organization administrator to approve or reject a pending request.
  """
  def process_join_request(%User{} = manager, membership_id, action)
      when action in [:approved, :rejected] do
    membership = Repo.get!(OrganizationMembership, membership_id)

    # 1. ENFORCE OWNERSHIP SECURITY: Verify the manager is an approved ADMIN of the organization
    is_admin? =
      Repo.exists?(
        from(m in OrganizationMembership,
          where:
            m.organization_id == ^membership.organization_id and m.user_id == ^manager.id and
              m.role == :admin and m.status == :approved
        )
      )

    if not is_admin? do
      {:error, :unauthorized}
    else
      Multi.new()
      # Step A: Atomic status update switch
      |> Multi.update(
        :membership,
        OrganizationMembership.changeset(membership, %{status: action})
      )
      # Step B: ASYNC LIFE-CYCLE SCHEDULING (Offload heavy Swoosh emails entirely to an Oban queue)
      |> Multi.run(:enqueue_email, fn _repo, _changes ->
        %{
          "user_id" => membership.user_id,
          "organization_id" => membership.organization_id,
          "action" => Atom.to_string(action)
        }
        |> OrgNotificationWorker.new()
        |> Oban.insert!()

        {:ok, :notified}
      end)
      |> Repo.transaction()
    end
  end

  @doc """
  Fetches all organization accounts a specific user is authorized to post under.
  """
  def list_authorized_organizations(user_id) do
    from(u in User,
      join: m in OrganizationMembership,
      on: m.organization_id == u.id,
      where: m.user_id == ^user_id and m.status == :approved,
      select: %{id: u.id, username: u.username, badge_type: u.badge_type}
    )
    |> Repo.all()
  end

  @doc """
  Searches for organization accounts matching a query string.
  """
  def search_organizations_by_type(query_str) when is_binary(query_str) do
    if String.trim(query_str) == "" do
      []
    else
      search_term = "%#{String.downcase(query_str)}%"

      from(u in User,
        where: u.type == :organization,
        where:
          fragment(
            "LOWER(?) LIKE ? or LOWER(?) LIKE ?",
            u.username,
            ^search_term,
            u.display_name,
            ^search_term
          ),
        order_by: [asc: u.username],
        limit: 20
      )
      |> Repo.all()
    end
  end

  @doc """
  Finds a user by email and creates a pending membership (invitation) for an organization.
  """
  def create_invite(org_id, email, role) do
    case Repo.get_by(User, email: email) do
      nil ->
        {:error, :user_not_found}

      user ->
        org = Repo.get!(User, org_id)
        attrs = %{organization_id: org_id, user_id: user.id, role: role, status: "pending"}

        # Wrap everything in a transaction to ensure database consistency
        Repo.transaction(fn ->
          case insert_or_update_invite(attrs) do
            {:ok, membership} ->
              # 1. Asynchronous Email Delivery
              Task.start(fn ->
                recipient_name = Map.get(user, :display_name) || user.username
                org_name = Map.get(org, :display_name) || org.username

                OrganizationMailer.invite_notification_email(
                  user.email,
                  recipient_name,
                  org_name,
                  role
                )
                |> OrganizationMailer.deliver()
              end)

              # 2. Real-Time In-App WebSocket Broadcast
              # This targets the global channel topic for the explicit user account
              KollectiveWeb.Endpoint.broadcast!(
                "users_socket:#{user.id}",
                "new_invitation_received",
                %{
                  id: membership.id,
                  org_name: org.display_name,
                  role: role
                }
              )

              membership

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)
    end
  end

  # Internal upsert database abstraction
  defp insert_or_update_invite(attrs) do
    %OrganizationMembership{}
    |> OrganizationMembership.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:role, :status, :updated_at]},
      conflict_target: [:user_id, :organization_id],
      returning: true
    )
  end

  @doc """
  Resends an invitation notification to the invited user.
  """
  def resend_invite(org_id, invite_id) do
    case Repo.get_by(OrganizationMembership, id: invite_id) do
      nil ->
        {:error, :invalid_invite}

      membership when membership.organization_id != org_id ->
        {:error, :unauthorized}

      membership ->
        %{
          user_id: membership.user_id,
          organization_id: membership.organization_id,
          action: "invite"
        }
        |> OrgNotificationWorker.new()
        |> Oban.insert!()

        {:ok, membership}
    end
  end

  @doc """
  Removes a membership invitation.
  """
  def remove_invite(org_id, invite_id) do
    case Repo.get_by(OrganizationMembership, id: invite_id) do
      nil ->
        {:error, :invalid_invite}

      membership when membership.organization_id != org_id ->
        {:error, :unauthorized}

      membership ->
        membership
        |> OrganizationMembership.changeset(%{status: :removed})
        |> Repo.update()
    end
  end

  @doc """
  Lists all pending invitations for a specific user.
  Applies the same expiration cutoff safety when users inspect their personal invitation list.
  """
  def list_pending_invitations(user_id) do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-@invite_expiry_days, :day)

    OrganizationMembership
    |> where([m], m.user_id == ^user_id and m.status == :pending)
    # <-- Active comparison guard
    |> where([m], m.inserted_at > ^cutoff_time)
    |> preload([:organization])
    |> Repo.all()
  end

  @doc """
  Filters memberships to only include pending items created within the last 7 days.
  """
  def list_pending_org_invites(org_id) do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-@invite_expiry_days, :day)

    OrganizationMembership
    |> where([m], m.organization_id == ^org_id and m.status == :pending)
    # Ecto date comparison logic: inserted_at must be strictly greater than our cutoff_time
    |> where([m], m.inserted_at > ^cutoff_time)
    |> preload([:user])
    |> Repo.all()
  end

  @doc """
  Accepts a pending invitation by switching its status to approved.
  """
  def accept_invitation(user_id, membership_id) do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-@invite_expiry_days, :day)

    # Query ensures an invitation cannot be grabbed if it falls older than the cutoff threshold
    query =
      from m in OrganizationMembership,
        where: m.id == ^membership_id and m.user_id == ^user_id and m.status == :pending,
        where: m.inserted_at > ^cutoff_time

    case Repo.one(query) do
      nil ->
        # If the record is missing or expired, reject cleanly
        {:error, :not_found}

      membership ->
        membership
        |> Ecto.Changeset.change(%{status: :approved})
        |> Repo.update()
    end
  end

  @doc """
  Declines an invitation by removing the pending membership record entirely.
  """
  def decline_invitation(user_id, membership_id) do
    case Repo.get_by(OrganizationMembership,
           id: membership_id,
           user_id: user_id,
           status: :pending
         ) do
      nil ->
        {:error, :not_found}

      membership ->
        Repo.delete(membership)
    end
  end

  @doc """
  Transfers ownership of an organization from current owner to a new owner atomically.
  """
  def transfer_ownership(org_id, current_owner_id, new_owner_id) do
    Multi.new()
    |> Multi.update_all(:demote_old, update_role_query(org_id, current_owner_id, :admin), [])
    |> Multi.update_all(:promote_new, update_role_query(org_id, new_owner_id, :owner), [])
    |> Repo.transaction()
  end

  @doc """
  Builds an update query for changing an organization member's role.
  """
  def update_role_query(org_id, user_id, new_role) do
    role_atom =
      cond do
        is_atom(new_role) -> new_role
        is_binary(new_role) -> String.to_existing_atom(new_role)
        true -> new_role
      end

    from(m in OrganizationMembership,
      where: m.organization_id == ^org_id and m.user_id == ^user_id,
      update: [set: [role: ^role_atom]]
    )
  end

  @doc """
  Checks if a user is an approved owner of the specified organization.
  """
  def is_owner?(org_id, user_id) do
    Repo.exists?(
      from(m in OrganizationMembership,
        where:
          m.organization_id == ^org_id and m.user_id == ^user_id and m.role == :owner and
            m.status in [:approved, :active]
      )
    )
  end

  @doc """
  Gets an organization membership for a given user ID and organization ID.
  """
  def get_organization_membership_by_user(user_id, org_id) do
    Repo.get_by(OrganizationMembership, user_id: user_id, organization_id: org_id)
  end

  @doc """
  Counts the number of approved owners in an organization.
  """
  def count_organization_owners(org_id) do
    Repo.one(
      from(m in OrganizationMembership,
        where: m.organization_id == ^org_id and m.role == :owner and m.status == :approved,
        select: count(m.id)
      )
    ) || 0
  end

  @doc """
  Updates an organization membership record.
  """
  def update_organization_membership(%OrganizationMembership{} = membership, attrs) do
    membership
    |> OrganizationMembership.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns a paginated list of audit logs for a specific organization.
  """
  def list_audit_logs(org_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    AuditLog
    |> where([a], a.organization_id == ^org_id)
    # Newest events first
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    # Preload the human who took the action
    |> preload([:actor])
    |> Repo.all()
  end

  @doc """
  Lists all active members belonging to a specific organization.
  """
  def list_active_members(org_id) do
    OrganizationMembership
    |> where([m], m.organization_id == ^org_id and m.status in [:approved, :active])
    # Preload human account data for React to render names
    |> preload([:user])
    |> Repo.all()
  end

  def remove_member(org_id, target_user_id, actor_id) do
    membership =
      Repo.get_by(OrganizationMembership, organization_id: org_id, user_id: target_user_id)

    cond do
      is_nil(membership) ->
        {:error, :not_found}

      membership.role in [:owner, "owner"] ->
        # Absolute owners must transfer ownership first
        {:error, :cannot_remove_owner}

      true ->
        Ecto.Multi.new()
        # 1. Delete the membership (or turn status to "terminated")
        |> Ecto.Multi.delete(:kick_member, membership)
        # 2. Append an Audit Track for compliance
        |> Ecto.Multi.insert(:audit_logging, fn _changes ->
          %AuditLog{}
          |> AuditLog.changeset(%{
            action: "member_removed",
            target_type: "User",
            target_id: target_user_id,
            actor_id: actor_id,
            organization_id: org_id,
            metadata: %{prior_role: membership.role}
          })
        end)
        |> Repo.transaction()
    end
  end

  @doc """
  Deletes an organization and automatically purges all related histories
  (memberships, posts, audit logs) via cascading database constraints.
  """
  def delete_organization(org_id) do
    case Repo.get(User, org_id) do
      nil ->
        {:error, :not_found}

      %User{} = org ->
        Multi.new()
        |> Multi.delete_all(
          :purge_posts,
          from(p in Kollective.Posts.Post, where: p.organization_id == ^org.id)
        )
        |> Multi.delete(:delete_org, org)
        |> Repo.transaction()
        |> case do
          {:ok, %{delete_org: deleted_org}} ->
            {:ok, deleted_org}

          {:error, _step, error, _changes} ->
            {:error, error}
        end
    end
  end

  @doc """
  Fetches an active or approved membership for a user in an organization with preloaded organization.
  """
  def get_active_membership(user_id, org_id) do
    with {:ok, valid_user_id} <- Ecto.ULID.cast(user_id),
         {:ok, valid_org_id} <- Ecto.ULID.cast(org_id) do
      cache_key = "membership:#{valid_user_id}:#{valid_org_id}"

      case Cachex.get(:kollective_cache, cache_key) do
        {:ok, %OrganizationMembership{} = membership} ->
          membership

        _ ->
          case Repo.one(
                 from(
                   m in OrganizationMembership,
                   where: m.user_id == ^valid_user_id and m.organization_id == ^valid_org_id,
                   where: m.status in [:approved, :active]
                 )
               ) do
            nil ->
              nil

            %OrganizationMembership{} = membership ->
              loaded = Repo.preload(membership, :organization)
              Cachex.put(:kollective_cache, cache_key, loaded)
              loaded
          end
      end
    else
      _ -> nil
    end
  end

  @doc """
  Returns a list of fine-grained string permissions based on the membership role.
  """
  def permissions_for_role(role) when role in [:owner, "owner"],
    do: ["posts:create", "posts:publish", "team:manage", "billing:manage"]

  def permissions_for_role(role)
      when role in [:admin, "admin", "lead organizer", "Lead Organizer"],
      do: ["posts:create", "posts:publish", "team:manage"]

  def permissions_for_role(role) when role in [:editor, "editor", "Editor"],
    do: ["posts:create", "posts:publish"]

  def permissions_for_role(role) when role in [:contributor, "contributor", "Contributor"],
    do: ["posts:create"]

  def permissions_for_role(_), do: []

  @doc """
  Fetches all active organization memberships for a specific user.
  Preloads the associated organization user record in a single optimized query.
  """
  def list_active_memberships(user_id) do
    from(m in OrganizationMembership,
      where: m.user_id == ^user_id and m.status in [:active, :approved],
      # 🚀 Preloads the organization profile details efficiently
      preload: [:organization]
    )
    # Executed against your database repo
    |> Repo.all()
  end
end
