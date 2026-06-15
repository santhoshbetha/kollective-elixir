defmodule Kollective.Chats.Message do
  use Ecto.Schema

  schema "messages" do
    field :encrypted_content, :binary # The cipher text # Text content (encrypted via RSA)
    field :sender_id, :id

    field :file_url, :string            # Path to R2 bucket
    field :encrypted_file_key, :binary  # AES key (encrypted via RSA)
    field :file_iv, :binary             # AES Initialization Vector (random, non-secret)
    field :file_name, :string           # Encrypted name

    belongs_to :conversation, Kollective.Chats.Conversation
    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> Ecto.Changeset.cast(attrs, [:encrypted_content, :sender_id, :conversation_id, :file_url, :encrypted_file_key, :file_iv, :file_name])
    |> Ecto.Changeset.validate_required([:sender_id, :conversation_id])
  end

end
