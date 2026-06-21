# lib/kollective_web/controllers/admin/moderation_controller.ex
defmodule KollectiveWeb.Admin.ModerationController do
  use KollectiveWeb, :controller
  alias Kollective.Moderation.Moderation

  # POST /api/admin/moderation/bulk_approve
  def bulk_approve(conn, %{"params" => approve_params}) do
    admin = conn.assigns.current_admin

    case Moderation.bulk_approve_pending(admin, approve_params) do
      {:ok, counts} ->
        json(conn, %{status: "success", data: counts})

      {:error, :empty_queue} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "There are no pending moderation items to approve."})

      {:error, :threshold_exceeded, total} ->
        # SAFETY GATE: Return a specific code so React triggers a "Are you absolutely sure?" dialog box
        conn
        |> put_status(:locked)
        |> json(%{
          error: "threshold_exceeded",
          message: "Warning: You are attempting to bulk-approve #{total} items at once. This might be a bot attack.",
          total_items: total
        })
    end
  end
end
