defmodule Kollective.Classifieds.Classified do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  @categories [
    "For Sale",
    "Services",
    "Handmade",
    "Housing",
    "Gigs",
    "Community"
  ]

  schema "classifieds" do
    field :title, :string
    field :category, :string
    field :price, :string
    field :neighborhood, :string
    field :description, :string
    field :duration_days, :integer, default: 7
    field :expires_at, :utc_datetime
    field :status, :string, default: "active"
    field :location, :string
    field :images, {:array, :string}, default: []
    field :contact_info, :string

    # Contact fields
    field :email, :string
    field :phone_number, :string

    # Political district and geospatial coordinates
    belongs_to :district, Kollective.Locations.PoliticalDistrict, foreign_key: :district_id
    field :geom, Geo.PostGIS.Geometry

    belongs_to :user, Kollective.Accounts.User, foreign_key: :user_id
    belongs_to :organization, Kollective.Accounts.User, foreign_key: :organization_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(classified, attrs) do
    classified
    |> cast(attrs, [
      :title,
      :category,
      :price,
      :neighborhood,
      :description,
      :duration_days,
      :expires_at,
      :status,
      :location,
      :images,
      :contact_info,
      :email,
      :phone_number,
      :district_id,
      :geom,
      :user_id,
      :organization_id
    ])
    |> validate_required([
      :title,
      :category,
      :price,
      :neighborhood,
      :description,
      :user_id,
      :email
    ])
    |> validate_length(:title, min: 3, max: 100)
    |> validate_length(:description, min: 5, max: 5000)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:phone_number, max: 30)
    |> validate_inclusion(:status, ["active", "expired", "archived", "deleted"])
    |> normalize_category()
    |> set_location_fallback()
    |> set_expiration_timestamp()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:district_id)
  end

  def categories, do: @categories

  defp normalize_category(changeset) do
    case get_change(changeset, :category) do
      nil ->
        changeset

      cat ->
        # Match case-insensitively or formatted
        normalized =
          Enum.find(@categories, cat, fn c ->
            String.downcase(c) == String.downcase(cat) or
              String.replace(String.downcase(c), " ", "_") == String.downcase(cat)
          end)

        put_change(changeset, :category, normalized)
    end
  end

  defp set_location_fallback(changeset) do
    location = get_field(changeset, :location)
    neighborhood = get_field(changeset, :neighborhood)

    if is_nil(location) or location == "" do
      put_change(changeset, :location, neighborhood)
    else
      changeset
    end
  end

  defp set_expiration_timestamp(changeset) do
    if is_nil(get_field(changeset, :expires_at)) do
      duration = get_field(changeset, :duration_days) || 7

      expires_at =
        DateTime.utc_now() |> DateTime.add(duration, :day) |> DateTime.truncate(:second)

      put_change(changeset, :expires_at, expires_at)
    else
      changeset
    end
  end
end
