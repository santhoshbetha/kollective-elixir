defmodule KollectiveWeb.TeamJSON do
  alias Kollective.Accounts.OrganizationMembership

  def index(%{members: members}) do
    %{data: Enum.map(members, &data/1)}
  end

  @doc """
  Renders a collection of pending workspace invitations.
  """
  def pending_invites(%{invites: invites}) do
    %{data: Enum.map(invites, &data/1)}
  end

  def data(%OrganizationMembership{} = membership) do
    %{
      id: to_string(membership.id),
      role: membership.role,
      status: membership.status,
      joined_at: membership.inserted_at,
      user: render_user(membership.user)
    }
  end

  defp render_user(nil), do: nil

  defp render_user(user) do
    %{
      id: to_string(user.id),
      name: Map.get(user, :display_name) || Map.get(user, :name),
      username: user.username,
      avatar_url: Map.get(user, :avatar_url, nil)
    }
  end
end
