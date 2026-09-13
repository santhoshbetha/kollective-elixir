defmodule KollectiveWeb.InvitationJSON do
  @moduledoc """
  JSON serializer for organization invitations.
  """
  alias Kollective.Accounts.OrganizationMembership

  @doc """
  Renders a collection of organization invitations.
  """
  def index(%{invitations: invitations}) when is_list(invitations) do
    %{data: Enum.map(invitations, &data/1)}
  end

  def index(invitations) when is_list(invitations) do
    %{data: Enum.map(invitations, &data/1)}
  end

  @doc """
  Renders a single invitation/membership.
  """
  def show(%{membership: membership}), do: %{data: data(membership)}
  def show(%{invitation: invitation}), do: %{data: data(invitation)}
  def show(%OrganizationMembership{} = membership), do: %{data: data(membership)}
  def show(membership) when is_map(membership), do: %{data: data(membership)}

  @doc """
  Formats an invitation membership record.
  """
  def data(%OrganizationMembership{} = membership) do
    %{
      id: to_string(membership.id),
      role: membership.role,
      status: membership.status,
      inserted_at: format_datetime(membership.inserted_at),
      organization: serialize_organization(membership.organization)
    }
  end

  def data(membership) when is_map(membership) do
    %{
      id: to_string(Map.get(membership, :id)),
      role: Map.get(membership, :role),
      status: Map.get(membership, :status),
      inserted_at: format_datetime(Map.get(membership, :inserted_at)),
      organization: serialize_organization(Map.get(membership, :organization))
    }
  end

  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp format_datetime(val), do: val

  defp serialize_organization(%Ecto.Association.NotLoaded{}), do: nil
  defp serialize_organization(nil), do: nil

  defp serialize_organization(org) when is_map(org) do
    %{
      id: to_string(Map.get(org, :id)),
      username: Map.get(org, :username),
      display_name: Map.get(org, :display_name),
      avatar_url: Map.get(org, :avatar_url) || "/default-avatar.jpg"
    }
  end
end
