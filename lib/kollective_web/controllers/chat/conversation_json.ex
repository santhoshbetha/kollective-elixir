defmodule KollectiveWeb.ConversationJSON do
  @moduledoc """
  Renders JSON payloads for chat conversations and inbox feeds.
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

    %{
      id: conversation.id,
      updated_at: conversation.updated_at,
      unread_count: Chats.get_unread_count(conversation.id, current_user_id),
      other_user: other_party,
      last_message: serialize_last_message(last_msg)
    }
  end

  defp other_user(participants, current_user_id) when is_list(participants) do
    participants
    |> Enum.find(fn p -> p.user_id != current_user_id end)
    |> case do
      nil ->
        %{username: "Deleted User", avatar: nil}

      participant ->
        user = Map.get(participant, :user)

        case user do
          %Kollective.Accounts.User{} ->
            %{username: user.username, avatar: user.avatar_url}

          _ ->
            %{username: "Deleted User", avatar: nil}
        end
    end
  end

  defp other_user(_, _), do: %{username: "Deleted User", avatar: nil}

  defp serialize_last_message(nil), do: nil

  defp serialize_last_message(last_msg) do
    %{
      sender_id: last_msg.sender_id,
      encrypted_content: last_msg.encrypted_content,
      inserted_at: last_msg.inserted_at
    }
  end
end
