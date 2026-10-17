defmodule Kollective.Moderation.SovereignOperator do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:username, :string, autogenerate: false}
  @derive {Jason.Encoder, only: [:username, :role, :granted_by, :inserted_at]}

  schema "sovereign_operators" do
    field :role, :string
    field :granted_by, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(operator, attrs) do
    operator
    |> cast(attrs, [:username, :role, :granted_by])
    |> validate_required([:username, :role, :granted_by])
    |> validate_inclusion(:role, ["moderator", "admin"])
  end
end
