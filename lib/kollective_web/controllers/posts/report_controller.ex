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
    do_create_report(conn, post_id, report_params)
  end

  def create(conn, params) do
    report_params = Map.get(params, "report", params)

    post_id =
      cond do
        is_binary(params["post_id"]) ->
          params["post_id"]

        is_list(report_params["status_ids"]) and length(report_params["status_ids"]) > 0 ->
          List.first(report_params["status_ids"])

        is_binary(report_params["post_id"]) ->
          report_params["post_id"]

        true ->
          nil
      end

    do_create_report(conn, post_id, report_params)
  end

  defp do_create_report(conn, post_id, report_params) do
    # Handle user session extraction safely across multi-source variants
    user = conn.assigns[:current_user] || conn.assigns[:user]

    category =
      Map.get(report_params, "category") ||
        Map.get(report_params, "reason") ||
        "content_violation"

    account_id =
      Map.get(report_params, "account_id") ||
        Map.get(report_params, "author_id") ||
        Map.get(report_params, "target_user_id")

    comment =
      Map.get(report_params, "comment") ||
        Map.get(report_params, "details") ||
        ""

    status_ids =
      case Map.get(report_params, "status_ids") do
        ids when is_list(ids) -> ids
        _ -> if post_id, do: [post_id], else: []
      end

    # Enrich payload attributes with geofenced tracking tags and current node names strings
    enriched_params =
      report_params
      |> Map.put("category", category)
      |> Map.put("reason", Map.get(report_params, "reason") || category)
      |> Map.put("account_id", account_id)
      |> Map.put("author_id", account_id)
      |> Map.put("comment", comment)
      |> Map.put("details", comment)
      |> Map.put("status_ids", status_ids)
      |> Map.put("origin_node_atom", Atom.to_string(Node.self()))
      |> Map.put("country_code", String.upcase(Map.get(user, :country_code) || Map.get(user, :country) || "GLOBAL"))
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
          success: true,
          report_id: to_string(report.id),
          category: report.category,
          suppressed_status_ids: status_ids,
          suppressed_account_id: account_id,
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
