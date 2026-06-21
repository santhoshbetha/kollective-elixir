defmodule Kollective.Config.Config do
  use Ecto.Schema
  import Ecto.Changeset

  schema "config" do
    field(:key, :string)
    field(:value, :binary)
    field(:group, :string)

    timestamps()
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [:key, :value, :group])
    |> validate_required([:key, :value])
    |> unique_constraint(:key)
  end
end
