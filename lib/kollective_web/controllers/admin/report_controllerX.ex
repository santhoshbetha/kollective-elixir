# lib/kollective_web/controllers/admin/report_controller.ex
defmodule KollectiveWeb.Admin.ReportControllerX do
  use KollectiveWeb, :controller

  alias Kollective.Moderation.Moderation
  alias KollectiveWeb.ChangesetJSON

  # ─── NEW ACTION: FETCH COMPLIANCE TICKETS QUEUE ───
  # GET /api/v1/admin/reports?status=open&limit=30&cursor=01J0A...
  def index(conn, params) do
    # Read the query status selector toggle ("open" or "resolved") directly from params
    status = Map.get(params, "status", "open")

    # Fetch tickets with look-ahead cursor support in exactly one database pass
    reports = Moderation.list_compliance_reports(status, params)
    next_cursor = if length(reports) > 0, do: List.last(reports).id, else: nil

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data:
        Enum.map(reports, fn r ->
          %{
            id: to_string(r.id),
            category: r.category || "content_violation",
            status: r.status,
            preview_text: r.preview_text || "Flagged timeline item.",
            comment: r.comment || "",
            inserted_at: Calendar.strftime(r.inserted_at, "%Y-%m-%dT%H:%M:%SZ"),

            # Associated account metadata card tracking parameters
            reporter: if(r.reporter, do: r.reporter.username, else: "anonymous"),
            target_account: if(r.target_user, do: r.target_account.username, else: "unknown"),

            # Target item identification markers
            target_id: to_string(r.target_id),
            target_type: r.target_type || "Post"
          }
        end),
      next_cursor: to_string(next_cursor)
    })
  end

  # ─── NEW ACTION: COMPLIANCE TICKET INDIVIDUAL DETAIL VIEW ───
  # GET /api/v1/admin/reports/:id
  def show(conn, %{"id" => id}) do
    case Moderation.get_report(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{
          status: "error",
          error: "ticket_not_found",
          message: "Compliance report record does not exist."
        })

      report ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          data: %{
            id: to_string(report.id),
            category: report.category,
            status: report.status,
            preview_text: report.preview_text,
            comment: report.comment,
            inserted_at: Calendar.strftime(report.inserted_at, "%Y-%m-%dT%H:%M:%SZ"),
            reporter_id: to_string(report.reporter_id),
            target_id: to_string(report.target_id),
            target_type: report.target_type
          }
        })
    end
  end

  # POST /api/v1/admin/reports/:id/resolve
  def resolve(conn, %{"id" => id, "status" => status, "delete_content" => delete_content}) do
    # FIX: Swapped current_admin to current_user to align with your platform's session RAM maps
    admin = conn.assigns.current_user
    report = Moderation.get_report!(id)

    case Moderation.resolve_report(report, status, delete_content) do
      {:ok, _changes} ->
        insert_compliance_log(admin.id, "report_resolved_#{status}", report.id)

        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Report successfully resolved and actions filed."})

      {:error, _step, changeset, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ChangesetJSON.error(%{changeset: changeset}))
    end
  end

  # POST /api/v1/admin/reports/:report_id/kill_event
  def kill_flagged_event(conn, %{"report_id" => report_id}) do
    admin = conn.assigns.current_user

    case Moderation.admin_cancel_event(admin, report_id) do
      {:ok, :admin_cancelled} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Prohibited community event successfully expunged from all area timelines."
        })

      {:error, :event_already_deleted} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "invalid_action",
          message: "This event record has already been removed from the platform database."
        })
    end
  end

  # --- Private Logging Helper ---
  defp insert_compliance_log(admin_id, action, target_id) do
    # FIX: Updated namespace mapping path configuration cleanly
    %Kollective.Admins.Log{
      action: action,
      target_id: target_id,
      target_type: "Report",
      user_id: admin_id,
      metadata: %{resolved_at: DateTime.utc_now()}
    }
    |> Kollective.Repo.insert!()
  end
end
