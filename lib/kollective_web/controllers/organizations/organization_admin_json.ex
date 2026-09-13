defmodule KollectiveWeb.OrganizationAdminJSON do
  @moduledoc """
  JSON serializer for organization admin endpoints (pending members, role changes, join requests).
  """
  alias Kollective.Accounts.OrganizationMembership

  @doc """
  Renders list of pending members.
  """
  def pending_members(%{pending_members: list}), do: pending_members(list)

  def pending_members(pending_list) when is_list(pending_list) do
    %{
      status: "success",
      data: Enum.map(pending_list, &pending_member_data/1)
    }
  end

  @doc """
  Serializes a single pending member item.
  """
  def pending_member_data(%OrganizationMembership{} = m) do
    %{
      membership_id: to_string(m.id),
      role: m.role,
      inserted_at: format_iso8601(m.inserted_at),
      user: serialize_user(m.user)
    }
  end

  def pending_member_data(m) when is_map(m) do
    %{
      membership_id: to_string(Map.get(m, :membership_id) || Map.get(m, :id)),
      role: Map.get(m, :role),
      inserted_at: format_iso8601(Map.get(m, :inserted_at)),
      user: serialize_user(Map.get(m, :user))
    }
  end

  @doc """
  Renders a generic action success response.
  """
  def action_success(message) do
    %{
      status: "success",
      message: message
    }
  end

  defp serialize_user(%Ecto.Association.NotLoaded{}), do: nil
  defp serialize_user(nil), do: nil

  defp serialize_user(user) when is_map(user) do
    %{
      id: to_string(Map.get(user, :id)),
      username: Map.get(user, :username),
      avatar_url: Map.get(user, :avatar_url)
    }
  end

  defp format_iso8601(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%dT%H:%M:%SZ")
  defp format_iso8601(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%Y-%m-%dT%H:%M:%SZ")
  defp format_iso8601(val) when is_binary(val), do: val
  defp format_iso8601(_), do: nil
end
