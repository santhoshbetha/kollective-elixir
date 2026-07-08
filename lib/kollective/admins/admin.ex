defmodule Kollective.Admins.Admin do
  import Ecto.Query
  alias Kollective.Admins.Log, as: AdminLog

  def send_logged_global_alert(admin, %{"message" => msg, "level" => level}) do
    Ecto.Multi.new()
    # 1. Create the Audit Log entry
    |> Ecto.Multi.insert(:log, %AdminLog{
      user_id: admin.id,
      action: "global_alert",
      target_type: "broadcast",
      metadata: %{message: msg, level: level}
    })
    |> Kollective.Repo.transaction()
    |> case do
      {:ok, %{log: log}} ->
        # 2. Only broadcast to users AFTER the log is successfully saved
        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          "admin:alerts",
          {:emergency_broadcast,
           %{
             message: msg,
             level: level,
             # Use the Log ID as the alert ID
             id: log.id
           }}
        )

        {:ok, log}

      {:error, _step, changeset, _} ->
        {:error, changeset}
    end
  end

  # JSONB containment operator in your query to filter logs by details->>'level'.

  def list_logs_by_level(level) do
    Log
    |> where([l], fragment("?.details @> ?", l, ^%{level: level}))
    |> order_by(desc: :inserted_at)
    |> preload(:admin)
    |> Kollective.Repo.all()
  end
end
