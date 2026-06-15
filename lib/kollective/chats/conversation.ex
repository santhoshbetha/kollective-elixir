defmodule Kollective.Chats.Conversation do
  use Ecto.Schema

  schema "conversations" do
    field :title, :string # Optional for group DMs
    has_many :participants, Kollective.Chats.Participant
    has_many :messages, Kollective.Chats.Message
    timestamps()
  end

end
