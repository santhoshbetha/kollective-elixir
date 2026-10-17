# lib/kollective_web/controllers/posts/report_controller.ex
defmodule KollectiveWeb.ReportController do
  use KollectiveWeb, :controller

  alias Kollective.Moderation.Moderation
  alias KollectiveWeb.ChangesetJSON
  alias Kollective.Workers.IncidentDistributionWorker

  @doc """
  POST /api/v1/posts/:post_id/report
  Submits an infraction report, triggers localized user feed muting, and enqueues
  asymmetric multi-node background streaming workers instantly.
  """
  def create(conn, %{"post_id" => post_id, "report" => report_params}) do
    # Handle user session extraction safely across multi-source variants
    user = conn.assigns[:current_user] || conn.assigns[:user]

    # Enrich payload attributes with geofenced tracking tags and current node names strings
    enriched_params =
      report_params
      |> Map.put("origin_node_atom", Atom.to_string(Node.self()))
      |> Map.put("country_code", String.upcase(user.country_code || "GLOBAL"))
      |> Map.put("reporter_id", user.id)

    # 1️⃣ Execute your existing transaction-safe creation & auto-mute pipeline logic block
    case Moderation.create_report(user, post_id, enriched_params) do
      {:ok, report} ->
        # 🚀 2. NON-BLOCKING DISTRIBUTED MESH HANDOFF TRIGGER:
        # Enqueue the multi-node distributed routing process to run in the background.
        # This keeps user response speeds high without suffering cross-network latency blocks.
        %{
          "incident_id" => to_string(report.id),
          "origin_node" => Atom.to_string(Node.self())
        }
        |> IncidentDistributionWorker.new()
        |> Oban.insert!()

        conn
        |> put_status(:created)
        |> json(%{
          status: "success",
          message: "Content reported. The post has been hidden from your timeline."
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        # Route validations failures through your unified JSON contract
        |> json(ChangesetJSON.error(changeset))
    end
  end

  # POST /api/v1/posts/:post_id/report
  # Report post by user
  def createX(conn, %{"post_id" => post_id, "report" => report_params}) do
    user = conn.assigns.current_user

    # Invokes your transaction-safe multi-tier creation and auto-mute logic block
    case Moderation.create_report(user, post_id, report_params) do
      {:ok, _report} ->
        conn
        |> put_status(:created)
        |> json(%{
          status: "success",
          message: "Content reported. The post has been hidden from your timeline."
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        # Route errors cleanly through your core ChangesetJSON contract
        |> json(ChangesetJSON.error(changeset))
    end
  end
end
