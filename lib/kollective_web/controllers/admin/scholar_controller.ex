# lib/kollective_web/controllers/admin/scholar_controller.ex
defmodule KollectiveWeb.Admin.ScholarController do
  use KollectiveWeb, :controller

  alias Kollective.Voting.AdminResolution
  alias KollectiveWeb.ChangesetJSON

  @doc """
  POST /api/v1/admin/incidents/users/:user_id/restore
  Reinstates a penalized user profile back to verified Scholar status.
  Enforces admin accountability logging and handles binary UUID parameters safely .
  """
  def restore_scholar(conn, %{"user_id" => target_user_id}) do
    # 1. Grab the current logged-in administrator from your session memory assignments
    admin = conn.assigns.current_user

    # 2. Fire the atomic multi-step database restoration workflow
    # FIXED: Dropped String.to_integer/1 to safely maintain your binary_id UUID contract
    case AdminResolution.process_scholar_reinstatement(target_user_id, admin.id) do
      {:ok, restored_user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message:
            "User status cleanly reinstated to Scholar tier. Emerald Green shield re-activated.",
          data: %{
            user_id: to_string(restored_user.id),
            type: to_string(restored_user.type),
            badge_type: restored_user.badge_type || "verified_scholar",
            reinstated_by_admin: to_string(admin.id)
          }
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          status: "error",
          error: "user_not_found",
          message: "The targeting user ID record does not exist."
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        # FIXED: Expose explicit database constraint faults cleanly to the admin dashboard
        conn
        |> put_status(:unprocessable_entity)
        |> json(ChangesetJSON.error(%{changeset: changeset}))

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", error: "reinstatement_failed", message: to_string(reason)})
    end
  end
end
