defmodule KollectiveWeb.AuditLogJSON do
  @moduledoc """
  JSON serializer for organization audit logs.
  """
  alias Kollective.Accounts.AuditLog

  @doc """
  Renders a collection of audit logs.
  """
  def index(%{audit_logs: audit_logs}) when is_list(audit_logs) do
    %{data: Enum.map(audit_logs, &data/1)}
  end

  def index(%{logs: logs}) when is_list(logs) do
    %{data: Enum.map(logs, &data/1)}
  end

  def index(audit_logs) when is_list(audit_logs) do
    %{data: Enum.map(audit_logs, &data/1)}
  end

  @doc """
  Renders a single audit log entry.
  """
  def show(%{audit_log: log}), do: %{data: data(log)}
  def show(%{log: log}), do: %{data: data(log)}
  def show(%AuditLog{} = log), do: %{data: data(log)}
  def show(log) when is_map(log), do: %{data: data(log)}

  @doc """
  Formats an audit log struct or map for API consumers.
  """
  def data(%AuditLog{} = log) do
    %{
      id: to_string(log.id),
      action: to_string(log.action),
      target_type: log.target_type,
      target_id: log.target_id,
      metadata: log.metadata || %{},
      inserted_at: format_datetime(log.inserted_at),
      actor: render_actor(log.actor)
    }
  end

  def data(log) when is_map(log) do
    %{
      id: to_string(Map.get(log, :id)),
      action: to_string(Map.get(log, :action)),
      target_type: Map.get(log, :target_type),
      target_id: Map.get(log, :target_id),
      metadata: Map.get(log, :metadata) || %{},
      inserted_at: format_datetime(Map.get(log, :inserted_at)),
      actor: render_actor(Map.get(log, :actor))
    }
  end

  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp format_datetime(val), do: val

  defp render_actor(%Ecto.Association.NotLoaded{}), do: nil
  defp render_actor(nil), do: %{username: "System", name: "System Event"}

  defp render_actor(user) when is_map(user) do
    %{
      id: to_string(Map.get(user, :id)),
      name: Map.get(user, :display_name),
      username: Map.get(user, :username)
    }
  end
end
