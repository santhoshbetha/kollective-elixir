defmodule Kollective.Events.Location do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "locations" do
    field :name, :string
    field :url, :string
    field :longitude, :float
    field :latitude, :float
    field :street, :string
    field :postal_code, :string
    field :locality, :string
    field :region, :string
    field :state, :string
    field :country, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(location, attrs) do
    location
    |> cast(attrs, [
      :name,
      :url,
      :longitude,
      :latitude,
      :street,
      :postal_code,
      :locality,
      :region,
      :state,
      :country
    ])
    |> validate_required([:name])
  end

  @doc """
  Returns public fields only for public API exposure
  """
  def public_fields(%__MODULE__{} = location) do
    %{
      id: location.id,
      name: location.name,
      url: location.url,
      longitude: location.longitude,
      latitude: location.latitude,
      street: location.street,
      postal_code: location.postal_code,
      locality: location.locality,
      region: location.region,
      state: location.state,
      country: location.country
    }
  end
end
