defmodule Kollective.Chats.Message do
  use Kollective.Schemas.Schema

  schema "messages" do
    # The cipher text # Text content (encrypted via RSA)
    field :encrypted_content, :binary
    field :sender_id, :id

    # Path to R2 bucket
    field :file_url, :string
    # AES key (encrypted via RSA)
    field :encrypted_file_key, :binary
    # AES Initialization Vector (random, non-secret)
    field :file_iv, :binary
    # Encrypted name
    field :file_name, :string

    belongs_to :conversation, Kollective.Chats.Conversation
    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> Ecto.Changeset.cast(attrs, [
      :encrypted_content,
      :sender_id,
      :conversation_id,
      :file_url,
      :encrypted_file_key,
      :file_iv,
      :file_name
    ])
    |> Ecto.Changeset.validate_required([:sender_id, :conversation_id])
  end
end
