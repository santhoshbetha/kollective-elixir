defmodule KollectiveWeb.MessageJSON do
  @moduledoc """
  Renders secure data payloads for message transfers, encryption keys,
  and R2 attachment parameters.
  """
  alias Kollective.Chats.Message

  @doc """
  Renders a single message wrapper object.
  """
  def show(%{message: message}) do
    %{data: data(message)}
  end

  def error(%{changeset: changeset}) do
    KollectiveWeb.ChangesetJSON.error(%{changeset: changeset})
  end

  @doc """
  Renders a list of messages with optional cursor pagination.
  """
  def index(%{messages: messages, next_cursor: next_cursor}) do
    %{
      data: Enum.map(messages, &data/1),
      pagination: %{
        next_cursor: next_cursor,
        # If rows fetched match our page limit, flag that more records likely exist
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
  Serializes a single message.
  """
  def data(%Message{} = message) do
    %{
      id: message.id,
      conversation_id: message.conversation_id,
      sender_id: message.sender_id,

      # The raw RSA-encrypted string content block
      encrypted_content: message.encrypted_content,

      # Secure storage attachment vectors (S3/R2 parameters)
      file_url: message.file_url,
      file_name: message.file_name,
      file_iv: message.file_iv,
      encrypted_file_key: message.encrypted_file_key,

      # ISO-8601 formatting for reliable React date sorting
      inserted_at: message.inserted_at,
      updated_at: message.updated_at
    }
  end

  def data(message) when is_map(message) do
    %{
      id: Map.get(message, :id),
      conversation_id: Map.get(message, :conversation_id),
      sender_id: Map.get(message, :sender_id),
      encrypted_content: Map.get(message, :encrypted_content),
      file_url: Map.get(message, :file_url),
      file_name: Map.get(message, :file_name),
      file_iv: Map.get(message, :file_iv),
      encrypted_file_key: Map.get(message, :encrypted_file_key),
      inserted_at: Map.get(message, :inserted_at),
      updated_at: Map.get(message, :updated_at)
    }
  end

  @doc """
  Payload representation for real-time WebSocket deliveries.
  """
  def broadcast_data(message) do
    %{
      id: message.id,
      sender_id: message.sender_id,
      conversation_id: message.conversation_id,
      encrypted_content: message.encrypted_content,
      file_url: message.file_url,
      inserted_at: message.inserted_at
    }
  end
end
