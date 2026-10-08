# lib/kollective/chats/participant.ex
defmodule Kollective.Chats.Participant do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "conversation_participants" do
    # Tracks when this specific user last viewed this chat
    field :last_read_at, :utc_datetime

    # The "Double Gray Tick" timestamp
    field :last_delivered_at, :utc_datetime

    # We store the user's current Public Key here for easy lookup during encryption
    field :public_key, :string

    # Align association primary key field translation behaviors to match ULID structures
    belongs_to :user, Kollective.Accounts.User, type: Ecto.ULID
    belongs_to :conversation, Kollective.Chats.Conversation, type: Ecto.ULID

    timestamps()
  end

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:user_id, :conversation_id, :last_read_at, :last_delivered_at, :public_key])
    |> validate_required([:user_id, :conversation_id])
    # Prevent a user from being added to the same DM twice
    |> unique_constraint([:user_id, :conversation_id])
  end
end
