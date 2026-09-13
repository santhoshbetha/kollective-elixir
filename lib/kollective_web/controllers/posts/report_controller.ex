# lib/kollective_web/controllers/posts/report_controller.ex
defmodule KollectiveWeb.ReportController do
  use KollectiveWeb, :controller

  alias Kollective.Moderation.Moderation
  alias KollectiveWeb.ChangesetJSON

  # POST /api/v1/posts/:post_id/report
  def create(conn, %{"post_id" => post_id, "report" => report_params}) do
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
