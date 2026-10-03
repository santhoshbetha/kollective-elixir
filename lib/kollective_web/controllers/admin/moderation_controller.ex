# lib/kollective_web/controllers/admin/moderation_controller.ex
defmodule KollectiveWeb.Admin.ModerationController do
  use KollectiveWeb, :controller
  alias Kollective.Moderation.Moderation
  alias Kollective.Posts.Posts

  # POST /api/admin/moderation/bulk_approve
  def bulk_approve(conn, %{"params" => approve_params}) do
    admin = conn.assigns[:current_admin] || conn.assigns[:current_user] || conn.assigns[:user]

    case Moderation.bulk_approve_pending(admin, approve_params) do
      {:ok, counts} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", data: counts})

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
          message:
            "Warning: You are attempting to bulk-approve #{total} items at once. This might be a bot attack.",
          total_items: total
        })
    end
  end

  # POST /api/v1/admin/posts/:id/reject (Soft Rejection Lock)
  def reject_post(conn, %{"id" => id, "reason" => reason}) do
    admin = conn.assigns[:current_admin] || conn.assigns[:current_user] || conn.assigns[:user]

    # Call the code cleanly from your central Posts data context
    case Posts.reject_post(admin, id, reason) do
      {:ok, post} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", data: %{id: post.id, status: post.status}})

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Failed to reject content."})
    end
  end

  # POST /api/v1/admin/posts/:id/appeal
  def appeal_post(conn, %{"id" => id, "reason" => reason}) do
    admin = conn.assigns[:current_admin] || conn.assigns[:current_user] || conn.assigns[:user]

    # Call the code cleanly from your central Posts data context
    case Posts.appeal_post(admin, id, reason) do
      {:ok, post} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", data: %{id: post.id, status: post.status}})

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Failed to appeal content."})
    end
  end

  # POST /api/v1/admin/posts/:id/restore (Restore Content)
  def restore_post(conn, %{"id" => id}) do
    admin = conn.assigns[:current_admin] || conn.assigns[:current_user] || conn.assigns[:user]

    # Call the code cleanly from your central Posts data context
    case Posts.restore_post(admin, id) do
      {:ok, _post} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Content successfully restored to public feeds."})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          status: "error",
          error: "forbidden",
          message: "You are not authorized to restore this post."
        })

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Failed to restore content."})
    end
  end

  # DELETE /api/v1/admin/posts/:id (Hard Kill Switch)
  def kill_post(conn, %{"id" => id}) do
    admin = conn.assigns[:current_admin] || conn.assigns[:current_user] || conn.assigns[:user]

    case Moderation.admin_delete_post(admin, id) do
      {:ok, _post} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Content hard-purged from system timelines."})

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Failed to hard-purge content."})
    end
  end

  # POST /api/v1/admin/comments/:comment_id/override
  # Expected params payload: %{"status" => "approved", "reason" => "False positive flag on crowd photo."}
  def override_comment_moderation(conn, %{
        "comment_id" => comment_id,
        "status" => status,
        "reason" => reason
      }) do
    # Securely verified admin user block
    admin = conn.assigns[:current_admin] || conn.assigns[:current_user] || conn.assigns[:user]

    case Moderation.admin_override_image(admin, comment_id, %{
           "status" => status,
           "reason" => reason
         }) do
      {:ok, comment} ->
        json(conn, %{
          status: "success",
          message: "Image moderation state successfully forced to: #{comment.moderation_status}"
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          status: "error",
          message: "Failed to override image moderation state.",
          details: changeset
        })
    end
  end
end
