defmodule KollectiveWeb.Admin.ReportController do
  use KollectiveWeb, :controller

  alias Kollective.Moderation.Moderation
  alias Kollective.Accounts.AuditLogs
  alias KollectiveWeb.ChangesetJSON

  @doc """
  GET /api/v1/admin/reports?status=open&limit=30
  Fetches compliance tickets with look-ahead cursor support in one database pass [INDEX].
  """
  def index(conn, params) do
    status = Map.get(params, "status", "open")
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

            # Safeguards against broken field lookups if relations are empty [INDEX]
            reporter: if(r.reporter, do: r.reporter.username, else: "anonymous"),
            target_account: if(r.target_user, do: r.target_user.username, else: "unknown"),
            target_id: to_string(r.target_id),
            target_type: r.target_type || "Post"
          }
        end),
      next_cursor: to_string(next_cursor)
    })
  end

  @doc """
  GET /api/v1/admin/reports/:id
  """
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

  @doc """
  POST /api/v1/admin/reports/:id/resolve
  🚀 PARAMETER REMAPPER INTERCEPTOR: Translates incoming frontend string actions
  into explicit moderation engine states, executing the underlying transactions safely [INDEX].
  """
  def resolve(conn, %{"id" => id, "action" => frontend_action} = params) do
    admin = conn.assigns.current_user || conn.assigns[:user]
    report = Moderation.get_report!(id)
    notes = Map.get(params, "notes", "Processed via Operations Desk UI Dashboard.")

    # Convert frontend actions to your backend context options [INDEX]
    {status, delete_content, audit_action} =
      case frontend_action do
        "soft_delete" ->
          {"resolved", true, "MODERATION_SOFT_DELETE"}

        "shadow_ban" ->
          {"resolved", false, "MODERATION_SHADOW_BAN"}

        "hard_ban" ->
          {"resolved", false, "MODERATION_HARD_BAN"}

        "dismiss" ->
          {"dismissed", false, "MODERATION_DISMISS"}

        _ ->
          {Map.get(params, "status", "resolved"), Map.get(params, "delete_content", false),
           "MODERATION_RESOLVE"}
      end

    case Moderation.resolve_report(report, status, delete_content) do
      {:ok, _changes} ->
        # 1. Backwards compatibility: file your legacy system log entry [INDEX]
        insert_compliance_log(admin.id, "report_resolved_#{status}", report.id)

        # 2. 🚀 NEW CENTRALIZED GOVERNANCE SYSTEM LEDGER LOG:
        # Pushes updates directly to your real-time root dashboard screens [INDEX]!
        AuditLogs.create_audit_log(%{
          action: audit_action,
          target_type: report.target_type || "Report",
          target_id: "@#{params["target_account"] || report.id}",
          actor_id: admin.id,
          metadata: %{
            "report_id" => to_string(report.id),
            "resolution_notes" => notes,
            "role" => "moderator"
          }
        })

        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Report successfully resolved and actions filed."})

      {:error, _step, changeset, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ChangesetJSON.error(%{changeset: changeset}))
    end
  end

  @doc """
  POST /api/v1/admin/reports/:report_id/kill_event
  """
  def kill_flagged_event(conn, %{"report_id" => report_id}) do
    admin = conn.assigns.current_user || conn.assigns[:user]

    case Moderation.admin_cancel_event(admin, report_id) do
      {:ok, :admin_cancelled} ->
        # Log event cancellation to system audit trail
        AuditLogs.create_audit_log(%{
          action: "EXPUNGE_EVENT",
          target_type: "Event",
          target_id: to_string(report_id),
          actor_id: admin.id,
          metadata: %{"role" => "moderator"}
        })

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

  # --- Legacy Private Logging Helper ---
  defp insert_compliance_log(admin_id, action, target_id) do
    %Kollective.Admins.Log{
      action: action,
      target_id: to_string(target_id),
      target_type: "Report",
      user_id: admin_id,
      metadata: %{resolved_at: DateTime.utc_now()}
    }
    |> Kollective.Repo.insert!()
  end
end
