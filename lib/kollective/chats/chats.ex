defmodule Kollective.Chats.Chats do
  @moduledoc """
  The Chats context.
  """
  import Ecto.Query, warn: false
  alias Kollective.Repo

  alias Kollective.Chats.{Conversation, Participant, Message}

  # Conversation functions
  def is_participant?(conversation_id, user_id) do
    Repo.exists?(
      from p in Participant,
        where: p.conversation_id == ^conversation_id and p.user_id == ^user_id
    )
  end

  # 1-on-1 Direct Message conversation, you need a strategy that prevents creating duplicate conversations
  # between the same two people. You want to "find" the existing ID if it exists, or "create" a new one
  # if it’s their first time talking.

  # 1. . The "Find or Create" Logic
  # In your Chat context, you use a query that looks for a conversation where both User A and User B
  # are participants.

  def get_or_create_1on1(user_a_id, user_b_id) do
    # 1. Look for a conversation containing BOTH users
    query =
      from c in Conversation,
        join: p1 in Participant,
        on: p1.conversation_id == c.id,
        join: p2 in Participant,
        on: p2.conversation_id == c.id,
        where: p1.user_id == ^user_a_id and p2.user_id == ^user_b_id,
        limit: 1

    case Repo.one(query) do
      %Conversation{} = conversation ->
        {:ok, conversation}

      nil ->
        # 2. Not found? Create a new one in a transaction
        Repo.transaction(fn ->
          with {:ok, conv} <- Repo.insert(%Conversation{}),
               {:ok, _p1} <-
                 Repo.insert(%Participant{user_id: user_a_id, conversation_id: conv.id}),
               {:ok, _p2} <-
                 Repo.insert(%Participant{user_id: user_b_id, conversation_id: conv.id}) do
            conv
          else
            error -> Repo.rollback(error)
          end
        end)
    end
  end

  # 1-on-1 Direct Message conversation
  # 3. Fetching the "Inbox" List
  # To show the user a list of their recent chats (like the WhatsApp or Twitter DM sidebar),
  # you query the Participant table to find all conversations they belong to, then preload the other person's profile.
  def list_my_conversations(user_id) do
    from c in Conversation,
      join: p in Participant,
      on: p.conversation_id == c.id,
      where: p.user_id == ^user_id,
      # Preload the messages and the OTHER participants (not me)
      preload: [messages: ^from(m in Message, order_by: [desc: m.inserted_at], limit: 1)],
      preload: [participants: :user],
      order_by: [desc: c.updated_at]
  end

  # "Unread Badges" for specific conversations using the last_read_at field in the Participant schema
  # To implement Unread Badges for your DMs, you compare each participant's last_read_at timestamp
  # against the inserted_at time of the messages in that conversation. Any message newer than last_read_at
  # is considered "unread" for that specific user.
  # 1. The Ecto Query for Unread Counts
  # Add this to your Chat context. It calculates the count of messages in a conversation that were sent
  # after the user last viewed it.
  def get_unread_count(conversation_id, user_id) do
    # 1. Get the user's last_read_at for this chat
    participant =
      Repo.get_by!(Participant,
        conversation_id: conversation_id,
        user_id: user_id
      )

    # 2. Count messages newer than that timestamp
    # If last_read_at is nil, all messages are unread
    query =
      from m in Message,
        where: m.conversation_id == ^conversation_id,
        # Don't count your own messages
        where: m.sender_id != ^user_id

    query =
      if participant.last_read_at do
        where(query, [m], m.inserted_at > ^participant.last_read_at)
      else
        query
      end

    Repo.aggregate(query, :count, :id)
  end

  #  implement the mark_as_read function in your Chat context, you perform a bulk update on the
  #  Participant record to set the last_read_at timestamp to the current time. This instantly "clears"
  #  the unread count for that user in that specific conversation.

  # It uses Repo.update_all for a fast, atomic update. Ecto.Repo.update_all/3
  def mark_as_read(conversation_id, user_id) do
    # Truncate to seconds to match database precision
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(p in Participant,
      where: p.conversation_id == ^conversation_id and p.user_id == ^user_id
    )
    |> Repo.update_all(set: [last_read_at: now])
  end

  # "Read Receipts" (blue checkmarks) logic so users can see exactly when their partner read the message
  # To implement WhatsApp-style Read Receipts (blue checkmarks), you leverage the existing last_read_at
  # field in your Participant schema to determine which messages have been seen by the other user.

  # The Elixir Backend (Providing Read Status)
  # When you fetch messages for a conversation, you include the other participant's last_read_at so
  # React can determine the tick color.
  def list_messages_with_read_status(conversation_id, current_user_id) do
    # 1. Get the OTHER person's last_read_at
    other_participant =
      from(p in Participant,
        where: p.conversation_id == ^conversation_id and p.user_id != ^current_user_id,
        select: p.last_read_at
      )
      |> Repo.one()

    # 2. Fetch messages
    messages =
      from(m in Message,
        where: m.conversation_id == ^conversation_id,
        order_by: [asc: m.inserted_at]
      )
      |> Repo.all()

    {messages, other_participant}
  end

  # Delivery Receipts
  def mark_as_delivered(conversation_id, user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(p in Participant,
      where: p.conversation_id == ^conversation_id and p.user_id == ^user_id
    )
    |> Repo.update_all(set: [last_delivered_at: now])
  end

  def create_message_with_attachment(user_id, conv_id, attrs) do
    Ecto.Multi.new()
    # 1. Insert the core message (storing the RSA-encrypted AES key)

    |> Ecto.Multi.insert(
      :message,
      Message.changeset(%Message{sender_id: user_id, conversation_id: conv_id}, attrs)
    )

    # 2. Update the conversation 'updated_at' to bubble it to the top of the inbox
    |> Ecto.Multi.update_all(
      :touch_conversation,
      from(c in Conversation, where: c.id == ^conv_id),
      set: [updated_at: DateTime.utc_now()]
    )
    |> Repo.transaction()
  end
end
