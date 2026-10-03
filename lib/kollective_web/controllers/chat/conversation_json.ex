defmodule KollectiveWeb.ConversationJSON do
  @moduledoc """
  🔒 CRYPTOGRAPHIC INBOX FEED JSON VIEW LAYER
  Serializes E2EE conversation metadata containers, maps dynamic unread indicators,
  and structures partner profile cards to protect user interface legibility.
  """
  alias Kollective.Chats.Chats

  @doc """
  Renders a single conversation wrapper.
  """
  def show(%{conversation: conversation, current_user_id: current_user_id}) do
    %{data: data(conversation, current_user_id)}
  end

  @doc """
  Renders a list of conversations for index actions.
  """
  def index(%{conversations: conversations, current_user_id: current_user_id}) do
    %{data: index(conversations, current_user_id)}
  end

  def index(conversations, current_user_id) when is_list(conversations) do
    Enum.map(conversations, &data(&1, current_user_id))
  end

  @doc """
  Serializes a single conversation entity map.
  """
  def data(conversation, current_user_id) do
    last_msg = List.first(conversation.messages)
    other_party = other_user(conversation.participants, current_user_id)

    # 🚀 ACCELERATION NOTE:
    # If your Chats context precalculates unread counts via a join statement,
    # read directly from a virtual field mapping like `conversation.unread_count`.
    unread_count =
      case Map.get(conversation, :unread_count) do
        nil -> Chats.get_unread_count(conversation.id, current_user_id)
        count -> count
      end

    %{
      id: to_string(conversation.id),
      updated_at: conversation.updated_at,
      unread_count: unread_count,
      other_user: other_party,
      last_message: serialize_last_message(last_msg)
    }
  end

  # --- Private Structural Extraction Helpers ---

  defp other_user(participants, current_user_id) when is_list(participants) do
    participants
    |> Enum.find(fn p -> to_string(p.user_id) != to_string(current_user_id) end)
    |> case do
      nil ->
        %{username: "Deleted User", avatar: "/default-avatar.jpg", user_id: nil}

      participant ->
        user = Map.get(participant, :user)

        case user do
          %Kollective.Accounts.User{} ->
            avatar =
              if user.avatar_url,
                do: Kollective.Media.UserAvatar.url({user.avatar_url, user}, :original),
                else: "/default-avatar.jpg"

            %{
              id: to_string(user.id),
              username: user.username,
              avatar: avatar,
              public_key: Map.get(participant, :public_key)
            }

          _ ->
            %{username: "Deleted User", avatar: "/default-avatar.jpg", user_id: nil}
        end
    end
  end

  defp other_user(_, _),
    do: %{username: "Deleted User", avatar: "/default-avatar.jpg", user_id: nil}

  defp serialize_last_message(nil), do: nil

  defp serialize_last_message(last_msg) do
    %{
      id: to_string(last_msg.id),
      sender_id: to_string(last_msg.sender_id),

      # 🚀 EXTENSION COMPATIBILITY MATRICES:
      # Feeds text parameters to help preview chat strings inside sidebars
      text: last_msg.encrypted_content,
      content: last_msg.encrypted_content,
      encrypted_content: last_msg.encrypted_content,
      inserted_at: last_msg.inserted_at
    }
  end
end
