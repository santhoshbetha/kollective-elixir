defmodule Kollective.Schemas.Schema do
  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset

      # This ONE line defines the :id field for you automatically
      #@primary_key {:id, Kollective.Schemas.ULIDType, autogenerate: true}
      @primary_key {:id, Ecto.ULID, autogenerate: true}

      # This makes sure belongs_to uses the same ULID type
      #@foreign_key_type Kollective.Schemas.ULIDType
      @foreign_key_type Ecto.ULID
    end
  end
end
