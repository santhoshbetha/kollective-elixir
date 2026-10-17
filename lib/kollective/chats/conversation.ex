defmodule Kollective.Chats.Conversation do
  use Kollective.Schemas.Schema

  schema "conversations" do
    # Optional for group DMs
    field(:title, :string)
    has_many(:participants, Kollective.Chats.Participant)
    has_many(:messages, Kollective.Chats.Message)
    timestamps()
  end

  @doc """
  Unified relational changeset.
  Casts the base attributes and structurally maps nested participants collection pools.
  """
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title])
    |> validate_required([:title])
    # 🚀 CAST NESTED RELATIONSHIPS:
    # This instructs Ecto to look for a "participants" list inside your parameters map
    # and safely pass each item into your Participant.changeset/2 module.
    |> cast_assoc(:participants, required: true)
  end
end
