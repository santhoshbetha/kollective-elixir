# lib/kollective_web/controllers/api/v1/candidacy_auth_controller.ex
defmodule KollectiveWeb.CandidacyAuthController do
  use KollectiveWeb, :controller

  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Accounts.User
  alias Kollective.Campaigns.CandidacyApplication

  action_fallback KollectiveWeb.FallbackController

  @doc """
  Processes a peer-to-peer vouching signature from a local constituent.
  When vouches hit the magic number (3), it triggers automatic phase promotion.
  """
  def cast_vouch(conn, %{"application_id" => app_id}) do
    voucher_id = conn.assigns[:current_user_id] || (conn.assigns[:current_user] && conn.assigns[:current_user].id)
    voucher = Repo.get!(User, voucher_id)

    Repo.transaction(fn ->
      # 1. Fetch active application file row inside a database lock boundary
      app =
        CandidacyApplication
        # 👈 Target by ID
        |> where(id: ^app_id)
        # 👈 Lock the row query
        |> lock("FOR UPDATE")
        # 👈 Execute and fetch the struct
        |> Repo.one!()
        |> Repo.preload([:user, :vouching_users])

      # 2. Strict Constraint Guards: Prevent cross-region vouching manipulation
      cond do
        app.user_id == voucher_id ->
          Repo.rollback(:cannot_vouch_for_self)

        app.user.state != voucher.state ->
          Repo.rollback(:must_reside_in_same_state)

        Enum.any?(app.vouching_users, &(&1.id == voucher_id)) ->
          Repo.rollback(:already_vouch_signed)

        app.status != "pending_vouches" ->
          Repo.rollback(:application_not_collecting_vouches)

        true ->
          # 3. Log the unique join signature row directly on disk
          {:ok, app_id_bin} = Ecto.ULID.dump(app.id)
          {:ok, voucher_id_bin} = Ecto.ULID.dump(voucher_id)

          Repo.insert_all("candidacy_vouches", [
            [application_id: app_id_bin, vouching_user_id: voucher_id_bin]
          ])

          # 4. Check Vouch Milestone Counter: If it hits 3, advance the status path automatically
          new_vouch_count = app.vouches_count + 1
          new_status = if new_vouch_count >= 3, do: "under_jury_review", else: "pending_vouches"

          app
          |> CandidacyApplication.changeset(%{vouches_count: new_vouch_count, status: new_status})
          |> Repo.update!()
      end
    end)
    |> case do
      {:ok, updated_app} -> json(conn, updated_app)
      {:error, reason} -> conn |> put_status(:bad_request) |> json(%{error: to_string(reason)})
    end
  end

  @doc """
  Administrative / Jury execution endpoint: Approves the working-class verification card.
  Atomically mutates the master user schema field `is_candidate: true`.
  """
  def approve_application(conn, %{"id" => app_id}) do
    # Ensure current user is an authorized platform Vanguard operator
    admin_id = conn.assigns[:current_user_id] || (conn.assigns[:current_user] && conn.assigns[:current_user].id)
    admin = Repo.get!(User, admin_id)

    if admin.is_admin || admin.role in [:admin, :moderator] || to_string(admin.role) == "Vanguard" do
      Repo.transaction(fn ->
        app = Repo.get!(CandidacyApplication, app_id)

        # 1. Mutate the application file parameters status to approved
        app
        |> CandidacyApplication.changeset(%{status: "approved"})
        |> Repo.update!()

        # 2. ⚡ ATOMIC USER UPGRADE: Flip the core schema flag switches directly
        target_user = Repo.get!(User, app.user_id)

        target_user
        |> Ecto.Changeset.change(%{is_candidate: true, is_verified_candidate: true})
        |> Repo.update!()
      end)
      |> case do
        {:ok, _} ->
          conn
          |> put_status(:ok)
          |> json(%{message: "Citizen candidacy portfolio approved and deployed cleanly."})

        {:error, _} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Transaction write fault."})
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Action restricted to Vanguard panel members."})
    end
  end

  # lib/kollective_web/controllers/api/v1/candidacy_auth_controller.ex

  @doc """
  Processes a fresh candidacy application portfolio packet.
  Enforces a strict constraint block: Limit one active application per citizen account profile.
  """
  def create_application(conn, %{"candidate_application" => app_params, "proof" => proof_plug}) do
    user_id = conn.assigns[:current_user_id] || (conn.assigns[:current_user] && conn.assigns[:current_user].id)
    office_level = Map.get(app_params, "office_level")

    alias Kollective.Repo
    alias Kollective.Campaigns.CandidacyApplication
    import Ecto.Query

    # 1. 🛡️ CONSTRAINT GUARD: Check if this user already holds a pending or approved application
    existing_app =
      CandidacyApplication
      |> where(
        [a],
        a.user_id == ^user_id and a.status in ["pending_vouches", "under_jury_review", "approved"]
      )
      |> Repo.one()

    if is_nil(existing_app) do
      # 2. Upload file stream through the asset pipeline
      case Kollective.Videos.Uploader.upload_video(proof_plug) do
        {:ok, stored_proof_url} ->
          full_attrs =
            app_params
            |> Map.put("employment_proof_url", stored_proof_url)
            |> Map.put("user_id", user_id)
            |> Map.put("status", "pending_vouches")

          %CandidacyApplication{}
          |> CandidacyApplication.changeset(full_attrs)
          |> Repo.insert()
          |> case do
            {:ok, saved_app} ->
              conn
              |> put_status(:created)
              |> json(saved_app)

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)})
          end

        {:error, _} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "File upload write failure."})
      end
    else
      conn
      |> put_status(:conflict)
      |> json(%{
        error:
          "Profile modification blocked. You already hold an active campaign application on file."
      })
    end
  end
end
