# Admin Logging to track who sent which global alert for accountability
# Admin Logging for global alerts, we will create a dedicated admin_logs table and wrap
# the alert broadcast in an Ecto.Multi. This ensures that an alert is never sent without
# a permanent record of who sent it and what the message was.
# lib/kollective/admin/log.ex
defmodule Kollective.Admins.Log do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "admin_logs" do
    # "event_cancelled", "post_deleted", "user_shadow_banned"
    field :action, :string
    # The specific ID of the mutated Event, Post, or Comment
    field :target_id, Ecto.ULID
    # "Event", "Post", "User"
    field :target_type, :string, default: "Event"

    # Single flexible JSONB map column storing dynamic metadata tracking contexts
    field :metadata, :map, default: %{}

    # Explicitly map the foreign key name to user_id to match your transaction code parameters
    belongs_to :admin, Kollective.Accounts.User, foreign_key: :user_id

    timestamps()
  end

  @doc "Baseline changesets validator for admin compliance operations logs mapping."
  def changeset(log, attrs) do
    log
    |> cast(attrs, [:action, :target_id, :target_type, :metadata, :user_id])
    |> validate_required([:action, :target_type, :user_id])
    |> foreign_key_constraint(:user_id)
  end
end

# reate index(:admin_logs, [:details], using: :gin)
