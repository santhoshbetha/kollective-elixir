defmodule Kollective.Chats.Conversation do
  use Kollective.Schemas.Schema

  schema "conversations" do
    # Optional for group DMs
    field :title, :string
    has_many :participants, Kollective.Chats.Participant
    has_many :messages, Kollective.Chats.Message
    timestamps()
  end
end
