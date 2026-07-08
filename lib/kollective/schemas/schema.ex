# lib/kollective/schemas/schema.ex
defmodule Kollective.Schemas.Schema do
  @moduledoc """
  The definitive foundational configuration boilerplate for Ecto schemas.
  Universally enforces chronological Ecto.ULID primary keys and UTC datetime options.
  """
  def macrohtml do
    quote do
      use Ecto.Schema
      import Ecto.Changeset

      # ─── UNIVERSAL SCHEMATIC PRIMITIVES ───
      # Forces all primary keys to use sortable Ecto.ULID binary formats universally
      @primary_key {:id, Ecto.ULID, autogenerate: true}

      # This makes sure all belongs_to associations expect the identical sortable ULID type
      @foreign_key_type Ecto.ULID

      # Enforces that all automatic timestamps track exact UTC parameters natively
      @timestamps_opts [type: :utc_datetime]
    end
  end

  defmacro __using__(_opts) do
    macrohtml()
  end
end
