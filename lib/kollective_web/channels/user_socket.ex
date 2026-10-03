defmodule KollectiveWeb.UserSocket do
  use Phoenix.Socket
  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.OrganizationMembership

  ## Channels
  channel "user:public", KollectiveWeb.UserPublicChannel
  channel "user:*", KollectiveWeb.UserChannel
  channel "user_notifications:*", KollectiveWeb.NotificationChannel

  # Routes system alerts to your high-security governance channel
  channel "admin_notifications:*", KollectiveWeb.AdminChannel

  channel "feed:*", KollectiveWeb.FeedChannel
  channel "voice_alert", KollectiveWeb.FeedChannel
  channel "event:*", KollectiveWeb.FeedChannel
  channel "timeline:*", KollectiveWeb.FeedChannel

  # handle real-time post comment threads
  channel "post_details:*", KollectiveWeb.PostChannel

  channel "poll:*", KollectiveWeb.PollChannel

  # Routes dynamic chat rooms to the EventChatChannel
  channel "event_chat:*", KollectiveWeb.EventChatChannel

  # Route to manage secure direct message streams
  channel "conversation:*", KollectiveWeb.ConversationChannel

  channel "org_admin_audit:*", KollectiveWeb.OrgAdminAuditChannel

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  # To deny connection, return `:error`.
  @impl true
  def connect(params, socket, _connect_info) do
    raw_token = params["token"] || params[:token]

    token =
      if is_binary(raw_token), do: String.replace(raw_token, ~r/^Bearer\s+/i, ""), else: raw_token

    with true <- is_binary(token) and token != "",
         {:ok, user} <- fetch_authenticated_user(token),
         {:ok, membership} <- validate_org_membership(user, params) do
      socket =
        socket
        |> assign(:user, user)
        |> assign(:user_id, user.id)
        |> assign(:is_authenticated, true)

      socket =
        if org_id = get_org_id(params) do
          socket
          |> assign(:org_id, org_id)
          |> assign(:current_org_id, org_id)
          |> assign(:org_membership, membership)
        else
          socket
        end

      {:ok, socket}
    else
      _ ->
        :error
    end
  end

  @impl true
  def id(socket) do
    if user_id = socket.assigns[:user_id] do
      "users_socket:#{user_id}"
    else
      nil
    end
  end

  defp fetch_authenticated_user(token) when is_binary(token) do
    clean_token = String.replace(token, ~r/^Bearer\s+/i, "")

    result =
      case Base.url_decode64(clean_token, padding: false) do
        {:ok, raw_bytes} -> Accounts.get_user_by_session_token(raw_bytes)
        _ -> nil
      end || Accounts.get_user_by_session_token(clean_token)

    case result do
      {%{suspended_at: nil} = user, _inserted_at} -> {:ok, user}
      {:ok, %{suspended_at: nil} = user} -> {:ok, user}
      %{suspended_at: nil} = user -> {:ok, user}
      _ -> {:error, :invalid_or_suspended_user}
    end
  end

  defp get_org_id(params) do
    case Map.get(params, "org_id") || Map.get(params, :org_id) ||
           Map.get(params, "organization_id") || Map.get(params, :organization_id) do
      nil -> nil
      "" -> nil
      id -> to_string(id)
    end
  end

  defp validate_org_membership(user, params) do
    case get_org_id(params) do
      nil ->
        {:ok, nil}

      org_id when org_id == user.id ->
        # User is connecting as the organization entity account itself
        {:ok, :self}

      org_id ->
        case Accounts.get_organization_membership_by_user(user.id, org_id) do
          %OrganizationMembership{status: status} = membership
          when status in [:approved, :active] ->
            {:ok, membership}

          _ ->
            {:error, :unauthorized_org_membership}
        end
    end
  end
end
