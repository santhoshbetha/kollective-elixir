defmodule KollectiveWeb.OrganizationJSON do
  @moduledoc """
  JSON serializer for organizations and organizational membership actions.
  """
  alias Kollective.Accounts.User
  alias Kollective.Accounts.OrganizationMembership
  alias KollectiveWeb.AccountJSON

  @doc """
  Renders search results using AccountJSON for uniform user/organization serialization.
  """
  def search(%{organizations: organizations, current_user: current_user}) do
    %{
      status: "success",
      data: AccountJSON.index(%{users: organizations, for: current_user})
    }
  end

  def search(organizations, current_user) when is_list(organizations) do
    %{
      status: "success",
      data: AccountJSON.index(%{users: organizations, for: current_user})
    }
  end

  @doc """
  Renders join request success response.
  """
  def join_request_success do
    %{
      status: "success",
      message: "Request successfully sent to organization administrators."
    }
  end

  @doc """
  Renders invite action success response.
  """
  def invite_success(message, membership, email) do
    %{
      status: "success",
      message: message,
      data: %{
        id: to_string(Map.get(membership, :id)),
        email: email,
        role: Map.get(membership, :role)
      }
    }
  end

  @doc """
  Renders ownership transfer success response.
  """
  def ownership_transferred do
    %{
      status: "success",
      message: "Ownership transferred successfully."
    }
  end

  @doc """
  Renders update organization profile success response.
  """
  def update_profile_success(org, message \\ "Organization profile updated successfully.") do
    %{
      status: "success",
      message: message,
      data: %{
        id: to_string(org.id),
        name: org.display_name,
        display_name: org.display_name,
        bio: org.bio,
        website: org.official_website,
        official_website: org.official_website,
        avatar_url: org.avatar_url,
        cover_image_url: org.cover_image_url
      }
    }
  end

  @doc """
  Renders a single organization profile.
  """
  def show(%{organization: org}), do: %{data: data(org)}
  def show(org) when is_map(org), do: %{data: data(org)}

  @doc """
  Renders a collection of organizations.
  """
  def index(%{organizations: orgs}) when is_list(orgs) do
    %{data: Enum.map(orgs, &data/1)}
  end

  def index(orgs) when is_list(orgs) do
    %{data: Enum.map(orgs, &data/1)}
  end

  @doc """
  Serializes organization account data.
  """
  def data(%User{} = org) do
    %{
      id: to_string(org.id),
      username: org.username,
      display_name: org.display_name,
      avatar_url: org.avatar_url,
      bio: org.bio,
      type: org.type,
      inserted_at: format_datetime(org.inserted_at)
    }
  end

  def data(org) when is_map(org) do
    %{
      id: to_string(Map.get(org, :id)),
      username: Map.get(org, :username),
      display_name: Map.get(org, :display_name),
      avatar_url: Map.get(org, :avatar_url),
      bio: Map.get(org, :bio),
      type: Map.get(org, :type),
      inserted_at: format_datetime(Map.get(org, :inserted_at))
    }
  end

  @doc """
  Serializes organization membership data.
  """
  def membership(%OrganizationMembership{} = m) do
    %{
      id: to_string(m.id),
      user_id: to_string(m.user_id),
      organization_id: to_string(m.organization_id),
      role: m.role,
      status: m.status,
      inserted_at: format_datetime(m.inserted_at)
    }
  end

  def membership(m) when is_map(m) do
    %{
      id: to_string(Map.get(m, :id)),
      user_id: to_string(Map.get(m, :user_id)),
      organization_id: to_string(Map.get(m, :organization_id)),
      role: Map.get(m, :role),
      status: Map.get(m, :status),
      inserted_at: format_datetime(Map.get(m, :inserted_at))
    }
  end

  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp format_datetime(val), do: val
end
