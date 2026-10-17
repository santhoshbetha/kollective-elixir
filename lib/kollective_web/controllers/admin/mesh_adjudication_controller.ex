defmodule KollectiveWeb.Admin.MeshAdjudicationController do
  use KollectiveWeb, :controller
  require Logger

  alias Kollective.Repo
  alias Kollective.Moderation.ModerationAppeal
  alias Kollective.Moderation.Incident

  @doc """
  POST /api/v1/admin/moderation_appeals/:id/adjudicate
  Processes an administrative court verdict, modifying Ecto disk arrays [INDEX]
  and purging active transaction records from distributed Mnesia rings concurrently [INDEX].
  """
  def adjudicate(conn, %{"id" => appeal_id, "resolution" => resolution}) do
    operator = conn.assigns[:current_user] || conn.assigns[:user]
    status_target = if resolution == "approve", do: "approved", else: "rejected"

    Repo.transaction(fn ->
      # 1️⃣ Fetch full historical contextual records out of SQL tables [INDEX]
      case Repo.get(ModerationAppeal, appeal_id) do
        nil ->
          Repo.rollback(:appeal_not_found)

        appeal ->
          # Update the global tracking status parameter of the appeal [INDEX]
          appeal_changeset = Ecto.Changeset.change(appeal, %{status: status_target})
          {:ok, updated_appeal} = Repo.update(appeal_changeset)

          # 2️⃣ If the appeal is approved, restore the original content [INDEX]
          if status_target == "approved" do
            case Repo.get(Incident, appeal.incident_id) do
              nil ->
                :ok

              incident ->
                incident_changeset =
                  Ecto.Changeset.change(incident, %{status: "resolved_restored"})

                {:ok, _} = Repo.update(incident_changeset)
            end
          end

          # 3️⃣ 🚀 PURGE REPLICATED TRANSACTION CHIPS FROM MNESIA CORES [INDEX]
          # Removes the active ticket context frame across all libcluster server network interfaces [INDEX]
          _ =
            :mnesia.transaction(fn ->
              :mnesia.delete({:distributed_appeals, to_string(appeal_id)})
              :mnesia.delete({:scholar_incidents, to_string(appeal.incident_id)})
            end)

          # 4️⃣ Out-of-band push notification dispatch rules
          dispatch_resolution_push(updated_appeal, status_target)

          # 5️⃣ Log permanent operational footprint track to Audit registers [INDEX]
          # Kollective.Accounts.AuditLogs.log_action(%{
          #   actor_username: operator.username,
          #   action: "appeal_adjudication_#{status_target}",
          #   target_identifier: to_string(appeal_id),
          #   node_name: Atom.to_string(Node.self())
          # })
          _ =
            Kollective.Accounts.AuditLogs.create_audit_log(%{
              actor_id: operator.id,
              action: "appeal_adjudication_#{status_target}",
              target_type: "Appeal",
              target_id: to_string(appeal_id),
              metadata: %{
                "note" => "Appeal adjudicated #{status_target}.",
                "node_name" => Atom.to_string(Node.self()),
                "actor_username" => operator.username
              }
            })
      end
    end)
    |> case do
      {:ok, _} ->
        json(conn, %{
          status: "success",
          message: "Verdicts registered. Operational telemetry updated across regions."
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Transaction rolled back.", reason: inspect(reason)})
    end
  end

  defp dispatch_resolution_push(appeal, status) do
    # Trigger out-of-band notification relays [INDEX]
    KollectiveWeb.Endpoint.broadcast(
      "user_notifications:#{appeal.user_id}",
      "appeal_resolved_event",
      %{
        "appeal_id" => to_string(appeal.id),
        "verdict" => status,
        "message" =>
          "Sovereign High Court processed your dispute. Status tracking state: #{String.upcase(status)}."
      }
    )
  end
end
