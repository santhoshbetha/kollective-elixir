defmodule KollectiveWeb.MessageJSON do
  @moduledoc """
  🔒 CRYPTOGRAPHIC JSON SERIALIZATION VIEW LAYER
  Encodes secure E2EE binary payloads, institutional R2 storage vectors,
  and maps nested author credentials safely to match React frontend formats.
  """
  alias Kollective.Chats.Message

  @doc """
  Renders a single message wrapper object response.
  """
  def show(%{message: message}) do
    %{data: data(message)}
  end

  def error(%{changeset: changeset}) do
    KollectiveWeb.ChangesetJSON.error(%{changeset: changeset})
  end

  @doc """
  Renders a list of historical messages with look-ahead cursor pagination parameters.
  """
  def index(%{messages: messages, next_cursor: next_cursor}) do
    %{
      data: Enum.map(messages, &data/1),
      pagination: %{
        next_cursor: to_string(next_cursor),
        # If rows fetched match our page limit, flag that more records exist
        has_more: not is_nil(next_cursor) and length(messages) >= 20
      }
    }
  end

  def index(%{messages: messages}) do
    %{data: Enum.map(messages, &data/1)}
  end

  def index(messages) when is_list(messages) do
    Enum.map(messages, &data/1)
  end

  @doc """
  Serializes a single database message row entity response.
  """
  def data(%Message{} = message) do
    # Fallback to structural map extraction if the schema preloads author records
    author_map =
      case Ecto.assoc_loaded?(message.sender) do
        true -> %{id: to_string(message.sender.id), username: message.sender.username}
        false -> %{id: to_string(message.sender_id), username: "user_#{message.sender_id}"}
      end

    %{
      id: to_string(message.id),
      conversation_id: to_string(message.conversation_id),
      sender_id: to_string(message.sender_id),

      # 🚀 MULTI-NAMING KEY ALIGNMENT:
      # Feeds both base text content and cryptographic binary parameters
      text: message.encrypted_content,
      content: message.encrypted_content,
      encrypted_content: message.encrypted_content,

      # Nested Identity Card block matching your React view access lines
      author: author_map,

      # Secure storage file attachment vectors (Cloudflare R2 fields)
      file_url: message.file_url,
      file_name: message.file_name,
      file_iv: message.file_iv,
      encrypted_file_key: message.encrypted_file_key,

      # Reliable ISO-8601 formatting for browser date sorting engines
      inserted_at: message.inserted_at,
      updated_at: message.updated_at
    }
  end

  def data(message) when is_map(message) do
    sender_id = Map.get(message, :sender_id) || Map.get(message, "sender_id")
    content = Map.get(message, :encrypted_content) || Map.get(message, "encrypted_content")

    %{
      id: to_string(Map.get(message, :id) || Map.get(message, "id")),
      conversation_id:
        to_string(Map.get(message, :conversation_id) || Map.get(message, "conversation_id")),
      sender_id: to_string(sender_id),
      text: content,
      content: content,
      encrypted_content: content,
      author: %{id: to_string(sender_id), username: "user_#{sender_id}"},
      file_url: Map.get(message, :file_url) || Map.get(message, "file_url"),
      file_name: Map.get(message, :file_name) || Map.get(message, "file_name"),
      file_iv: Map.get(message, :file_iv) || Map.get(message, "file_iv"),
      encrypted_file_key:
        Map.get(message, :encrypted_file_key) || Map.get(message, "encrypted_file_key"),
      inserted_at: Map.get(message, :inserted_at) || Map.get(message, "inserted_at"),
      updated_at: Map.get(message, :updated_at) || Map.get(message, "updated_at")
    }
  end

  @doc """
  🚀 DYNAMIC WEBSOCKET BROADCAST PARSER
  Builds the exact data map signature expected by your frontend useConversationChannel hooks.
  """
  def broadcast_data(%Message{} = message) do
    %{
      id: to_string(message.id),
      conversation_id: to_string(message.conversation_id),
      sender_id: to_string(message.sender_id),

      # Maps content fields to text attributes cleanly
      text: message.encrypted_content,
      content: message.encrypted_content,

      # Mounts the nested author reference frame for instant layout evaluation
      author: %{
        id: to_string(message.sender_id),
        username: "user_#{message.sender_id}"
      },
      file_url: message.file_url,
      inserted_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
end
