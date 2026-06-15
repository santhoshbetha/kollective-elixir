defmodule Kollective.Accounts.UserRelationship do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  @types ["follow",
          "block",
          "mute",
          "reblog_mute",
          "notification_mute",
          "inverse_subscription",
          "endorsement"
         ]

  schema "user_relationships" do
    field :type, :string, default: "follow"

    belongs_to :source, Kollective.Accounts.User, foreign_key: :source_id
    belongs_to :target, Kollective.Accounts.User, foreign_key: :target_id

    timestamps()
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:type, :source_id, :target_id])
    |> validate_inclusion(:type, @types)
    |> foreign_key_constraint(:source_id)
    |> foreign_key_constraint(:target_id)
    |> validate_not_self()
    # Prevents duplicate follows/blocks in the DB
    |> unique_constraint([:source_id, :target_id, :type])
  end

  defp validate_not_self(changeset) do
    if get_field(changeset, :source_id) == get_field(changeset, :target_id) do
      add_error(changeset, :target_id, "You cannot relate to yourself")
    else
      changeset
    end
  end
end

# In your UserRelationship migration
#create index(:user_relationships, [:expires_at])
#create index(:user_relationships, [:source_id, :target_id, :type], unique: true)

# Index for follows/mutes lookups
#create index(:user_relationships, [:source_id, :type])
# Ensure a user can't follow the same person twice
#create unique_index(:user_relationships, [:source_id, :target_id, :type])
