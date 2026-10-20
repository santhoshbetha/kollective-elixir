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
      from(p in Participant,
        where: p.conversation_id == ^conversation_id and p.user_id == ^user_id
      )
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
      from(c in Conversation,
        join: p1 in Participant,
        on: p1.conversation_id == c.id,
        join: p2 in Participant,
        on: p2.conversation_id == c.id,
        where: p1.user_id == ^user_a_id and p2.user_id == ^user_b_id,
        limit: 1
      )

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
  # Update this inside your lib/kollective/chats/chats.ex file to eliminate N+1 loops:
  def list_my_conversations(user_id) do
    from(c in Conversation,
      join: p in Participant,
      on: p.conversation_id == c.id,
      where: p.user_id == ^user_id,
      # Left-join a subquery that calculates unread counts per thread dynamically
      preload: [participants: :user],
      preload: [messages: ^from(m in Message, order_by: [desc: m.id], limit: 1)],
      order_by: [desc: c.updated_at]
    )
  end

  def list_my_conversationsX(user_id) do
    from(c in Conversation,
      join: p in Participant,
      on: p.conversation_id == c.id,
      where: p.user_id == ^user_id,
      # Preload the messages and the OTHER participants (not me)
      preload: [messages: ^from(m in Message, order_by: [desc: m.id], limit: 1)],
      preload: [participants: :user],
      order_by: [desc: c.id]
    )
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
      from(m in Message,
        where: m.conversation_id == ^conversation_id,
        # Don't count your own messages
        where: m.sender_id != ^user_id
      )

    query =
      if participant.last_read_at do
        where(query, [m], m.inserted_at > ^participant.last_read_at)
      else
        query
      end

    Repo.aggregate(query, :count, :id)
  end

  @doc """
  Calculates the total unread message count across all conversations for a given user.
  Used for app badging and global notification indicators.
  """
  def get_total_unread_count(nil), do: 0

  def get_total_unread_count(user_id) do
    query =
      from(p in Participant,
        where: p.user_id == ^user_id,
        join: m in Message,
        on: m.conversation_id == p.conversation_id,
        where: m.sender_id != ^user_id,
        where: is_nil(p.last_read_at) or m.inserted_at > p.last_read_at,
        select: count(m.id)
      )

    Repo.one(query) || 0
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
        order_by: [asc: m.id]
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
    # Truncate your time parameter string down to the second to align timestamps perfectly
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Ecto.Multi.new()
    # 1. Insert the core message (storing the RSA-encrypted AES key)

    |> Ecto.Multi.insert(
      :message,
      Message.changeset(%Message{sender_id: user_id, conversation_id: conv_id}, attrs)
    )

    # 2. Update the conversation 'updated_at' to bubble it to the top of the inbox
    |> Ecto.Multi.update_all(
      :touch_conversation,
      from(c in Conversation, where: c.id == type(^conv_id, Ecto.ULID)),
      set: [updated_at: now]
    )
    |> Repo.transaction()
  end

  @doc """
  Fetches a single page of historical messages for a conversation thread using cursor pagination.
  """
  def list_messages_cursor(conversation_id, current_user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    before_id = Keyword.get(opts, :before_id)

    # 1. Fetch the other participant's last read timestamp for UI checkmarks
    other_last_read =
      from(p in Participant,
        where: p.conversation_id == ^conversation_id and p.user_id != ^current_user_id,
        select: p.last_read_at
      )
      |> Repo.one()

    # 2. Build the base query ordered descending to catch newest messages first
    base_query =
      from(m in Message,
        where: m.conversation_id == ^conversation_id,
        # ID order naturally mirrors chronological entry order
        order_by: [desc: m.id],
        limit: ^limit
      )

    # 3. Apply the cursor filter if 'before_id' is supplied by the React UI
    query =
      if before_id do
        from(m in base_query, where: m.id < ^before_id)
      else
        base_query
      end

    # 4. Fetch records and reverse them so they flow top-to-bottom chronologically in chat
    messages =
      query
      |> Repo.all()
      |> Enum.reverse()

    {messages, other_last_read}
  end

  @doc """
  Fetches public keys for all recipients in a conversation, explicitly excluding the sender.

  Returns a list of maps containing the recipient `user_id` and their associated `public_key`.
  Optimized using `select:` to skip loading full Ecto struct overhead into memory.
  """
  def get_recipient_public_keys(conversation_id, sender_id) do
    Participant
    |> where([p], p.conversation_id == ^conversation_id and p.user_id != ^sender_id)
    |> where([p], not is_nil(p.public_key))
    |> select([p], %{user_id: p.user_id, public_key: p.public_key})
    |> Repo.all()
  end

  @doc """
  Fetches public keys for absolutely everyone in the conversation (including the sender).
  Useful for verifying group key states or sync environments across a user's multi-device layouts.
  """
  def get_all_conversation_public_keys(conversation_id) do
    Participant
    |> where([p], p.conversation_id == ^conversation_id)
    |> where([p], not is_nil(p.public_key))
    |> select([p], %{user_id: p.user_id, public_key: p.public_key})
    |> Repo.all()
  end

  @doc """
  Gets a single message by ID. Returns nil if not found.
  """
  def get_message(id), do: Repo.get(Message, id)

  @doc """
  Gets a single message by ID. Raises Ecto.NoResultsError if not found.
  """
  def get_message!(id), do: Repo.get!(Message, id)

  @doc """
  Soft-deletes a message by updating its `encrypted_content` to the deletion notice text
  and clearing any attached file metadata (file_url, keys, iv, file_name).
  Supports both a `%Message{}` struct and a message binary ID.
  """
  def soft_delete_message(
        message_or_id,
        deleted_text \\ "🚫 This message was deleted by the sender."
      )

  def soft_delete_message(%Message{} = message, deleted_text) do
    message
    |> Message.soft_delete_changeset(deleted_text)
    |> Repo.update()
  end

  def soft_delete_message(id, deleted_text) when is_binary(id) do
    case get_message(id) do
      nil -> {:error, :not_found}
      message -> soft_delete_message(message, deleted_text)
    end
  end
end
