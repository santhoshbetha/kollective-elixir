defmodule KollectiveWeb.Admin.ScholarIncidentController do
  use KollectiveWeb, :controller

  alias Kollective.Repo
  alias Kollective.Accounts.AuditLogs
  import Ecto.Query

  # 🛡️ PRIVILEGE PROTECTION PLUG: Restricts lookups exclusively to authorized operator staff accounts
  plug(:verify_moderator_clearance)

  # GET /api/v1/admin/incidents
  # Hydrates the Scholar Integrity Queue list panel inside the ModerationDashboard.
  alias Kollective.Moderation.ScholarIncident
  alias Kollective.Accounts.User
  alias Kollective.Database.MnesiaResolutionEngine

  def index(conn, _params) do
    query =
      from(i in ScholarIncident,
        where: i.status == "pending",
        order_by: [desc: i.inserted_at],
        select: %{
          incident_id: i.id,
          status: i.status,
          security_flag: %{
            type: i.flag_type,
            description: i.description
          },
          target_user: %{
            id: i.user_id,
            username: i.target_username
          },
          audit_payload: %{
            orcid_id: i.orcid_id,
            historical_publication_count: i.historical_count,
            scraped_publication_count: i.scraped_count,
            last_successful_sync: i.last_sync_at
          }
        }
      )

    incidents = Repo.all(query)

    formatted_incidents =
      Enum.map(incidents, fn inc ->
        id_str = to_string(inc.incident_id)

        Map.put(inc, :resolution_options, %{
          approve_restoration_endpoint: "/incidents/#{id_str}/resolve?action=restore",
          permanent_ban_endpoint: "/incidents/#{id_str}/resolve?action=ban"
        })
      end)

    json(conn, %{data: formatted_incidents})
  end

  def resolve(conn, %{"id" => id, "action" => action_type}) do
    admin = conn.assigns[:current_user] || conn.assigns[:user]

    if action_type in ["dismiss", "soft_delete", "hard_ban"] do
      case MnesiaResolutionEngine.resolve_incident(id, action_type, admin.id) do
        {:ok, status} ->
          json(conn, %{status: "success", final_status: status})

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Targeted incident record not found or expired."})

        _ ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to resolve incident through resolution engine."})
      end
    else
      timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

      case Repo.get(ScholarIncident, id) do
        %ScholarIncident{} = incident ->
          user = Repo.get(User, incident.user_id)

          {db_status, audit_action, alert_msg} =
            case action_type do
              "restore" ->
                if user do
                  user |> Ecto.Changeset.change(%{under_investigation: false}) |> Repo.update()
                end

                {"resolved_restored", "SCHOLAR_FLAG_DISMISS",
                 "Academic credentials cleared and restored."}

              "ban" ->
                if user do
                  user
                  |> Ecto.Changeset.change(%{badge_type: "suspended", under_investigation: false})
                  |> Repo.update()
                end

                {"resolved_banned", "SCHOLAR_PROFILE_BAN",
                 "Prohibited academic profile permanently terminated."}

              _ ->
                {"resolved_dismissed", "SCHOLAR_FLAG_DISMISS", "Incident resolved."}
            end

          incident
          |> Ecto.Changeset.change(%{
            status: db_status,
            resolved_at: timestamp,
            resolved_by_id: admin.id
          })
          |> Repo.update!()

          AuditLogs.create_audit_log(%{
            action: audit_action,
            target_type: "User",
            target_id: "@#{incident.target_username}",
            actor_id: admin.id,
            metadata: %{
              "incident_id" => to_string(id),
              "orcid_id" => incident.orcid_id,
              "role" => "moderator"
            }
          })

          json(conn, %{status: "success", message: alert_msg})

        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Targeted scholar incident record not found."})
      end
    end
  end

  # --- Private Security Interceptor Plug Guard ---
  defp verify_moderator_clearance(conn, _opts) do
    user = conn.assigns[:current_user] || conn.assigns[:user]

    if user &&
         (user.is_admin || user.is_moderator ||
            Map.get(user, :badge_type) in ["admin", "root", "moderator", "staff"]) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Access denied: Unauthorized operations clearance level."})
      |> halt()
    end
  end
end
