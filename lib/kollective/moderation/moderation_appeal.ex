defmodule Kollective.Moderation.ModerationAppeal do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "moderation_appeals" do
    field :incident_id, Ecto.ULID
    field :reason, :string
    field :status, :string, default: "pending"
    field :country_code, :string
    field :origin_node_atom, :string

    belongs_to :user, Kollective.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(appeal, attrs) do
    appeal
    |> cast(attrs, [:incident_id, :user_id, :reason, :status, :country_code, :origin_node_atom])
    |> validate_required([:incident_id, :user_id, :reason, :country_code, :origin_node_atom])
    |> validate_inclusion(:status, ["pending", "approved", "rejected"])
  end
end
