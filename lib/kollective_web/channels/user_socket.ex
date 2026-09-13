defmodule KollectiveWeb.UserSocket do
  use Phoenix.Socket
  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.OrganizationMembership

  ## Channels
  channel "user:*", KollectiveWeb.UserChannel
  channel "user:public", KollectiveWeb.UserPublicChannel
  channel "user_notifications:*", KollectiveWeb.NotificationChannel

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
    token = params["token"] || params[:token]

    with true <- is_binary(token),
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

  # Socket id's are topics that allow you to identify all sockets for a given user:
  #
  #     def id(socket), do: "user_socket:#{socket.assigns.user_id}"
  #
  # Would allow you to broadcast a "disconnect" event and terminate
  # all active sockets and channels for a given user:
  #
  #     KollectiveWeb.Endpoint.broadcast("users_socket:#{user.id}", "disconnect", %{})
  #
  # Returning `nil` makes this socket anonymous.
  @impl true
  # This allows us to target a specific user by their ULID
  def id(socket), do: "users_socket:#{socket.assigns.user_id}"

  defp fetch_authenticated_user(token) when is_binary(token) do
    result =
      case Base.url_decode64(token, padding: false) do
        {:ok, raw_bytes} -> Accounts.get_user_by_session_token(raw_bytes)
        _ -> nil
      end || Accounts.get_user_by_session_token(token)

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
