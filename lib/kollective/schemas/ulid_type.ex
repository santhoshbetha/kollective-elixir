defmodule Kollective.Schemas.ULIDType do
  @moduledoc """
  Ecto type for ULIDs using Ecto.ULID from ecto_ulid_next.
  """

  use Ecto.Type

  @impl true
  def type, do: :uuid

  @impl true
  def cast(binary) when is_binary(binary), do: {:ok, binary}
  def cast(_), do: :error

  @impl true
  def load(binary) when is_binary(binary), do: {:ok, binary}

  @impl true
  def dump(binary) when is_binary(binary), do: {:ok, binary}

  @impl true
  def autogenerate do
    # Use Ecto.ULID.generate() for ULID generation
    Ecto.ULID.generate()
  end

  @impl true
  def embed_as(_), do: :self

  @impl true
  def equal?(a, b), do: a == b
end
