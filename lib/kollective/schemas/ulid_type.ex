defmodule Kollective.Schemas.ULIDType do
  @moduledoc """
  Custom wrapper type delegating safely to Ecto.ULID.
  """
  use Ecto.Type

  # Ecto.ULID treats the underlying DB field as a binary :uuid type
  @impl true
  def type, do: Ecto.ULID.type()

  @impl true
  def cast(value), do: Ecto.ULID.cast(value)

  @impl true
  def load(value), do: Ecto.ULID.load(value)

  @impl true
  def dump(value), do: Ecto.ULID.dump(value)

  @impl true
  def autogenerate, do: Ecto.ULID.autogenerate()

  @impl true
  def embed_as(format), do: Ecto.ULID.embed_as(format)

  @impl true
  def equal?(a, b), do: Ecto.ULID.equal?(a, b)

  # Your helper function
  def generate, do: Ecto.ULID.generate()
end
