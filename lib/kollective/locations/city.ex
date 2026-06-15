defmodule Kollective.Locations.City do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "cities" do
    field :name, :string
    field :state, :string        # e.g., "TX" or "UP"
    field :country, :string      # e.g., "US" or "IN"
    field :latitude, :float
    field :longitude, :float

    field :external_id, :string  # Unique ID from Geoapify/Google

    # Reverse associations: Useful if you ever want to see everyone in a city
    has_many :users, Kollective.Accounts.User, foreign_key: :city_id
    has_many :businesses, Kollective.Businesses.Business, foreign_key: :city_id

    has_many :events, Kollective.Events.Event, foreign_key: :origin_city_id
    has_many :posts, Kollective.Posts.Post, foreign_key: :origin_city_id

    timestamps()
  end

  def changeset(city, attrs) do
    city
    |> cast(attrs, [:name, :state, :country, :external_id, :latitude, :longitude])
    |> validate_required([:name, :state, :country, :external_id])
    |> unique_constraint(:external_id)
  end
end
