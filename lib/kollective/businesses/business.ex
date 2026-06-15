#To implement a Local Businesses feature with district-based visibility and a 60-mile radius
#discovery, you need a specialized context for business data and a geospatial query engine
#using PostGIS.

#1. We will create a single businesses table with a type field to distinguish between a "Proposal" (Idea) and an "Existing" business.

#Critical Requirement: We use a geography type to store the exact coordinates for the 60-mile radius search.

defmodule Kollective.Businesses.Business do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  @categories [
    :food_beverage,  # Restaurants, Coffee Shops, Bakeries
    :technology,     # Software, IT, Repair, Hardware
    :retail,         # Clothing, Boutique, General Store
    :services,       # Legal, Accounting, Cleaning, Hair/Beauty
    :manufacturing,  # Local makers, Factories, Crafting
    :construction,   # Contractors, Plumbing, Electrical
    :healthcare,     # Clinics, Dental, Fitness/Gyms
    :education,      # Tutoring, Schools, Music lessons
    :online,         # E-commerce, Digital services, SaaS
    :other
  ]

  schema "businesses" do
    field :name, :string
    field :description, :string

    # :proposal or :existing
    field :type, Ecto.Enum, values: [:proposal, :existing], default: :proposal

    field :category, Ecto.Enum, values: @categories, default: :other

    # Physical & Contact Fields
    field :address, :string
    field :zip, :string
    field :email, :string
    field :phone, :string
    field :website, :string

    # Political Anchor Data (for district matching)
    field :origin_district_l1, :string
    field :origin_district_l2, :string
    field :origin_district_l3, :string
    #field :origin_city_id, :integer
    belongs_to :city, Kollective.Locations.City, foreign_key: :city_id

    field :origin_state, :string
    field :origin_country, :string, default: "US"

    # Geospatial Data (for 60-mile radius)
    # Note: You'll need the geo_postgis library for this type
    field :location, Geo.PostGIS.Geometry

    field :physical_address, :string
    field :verification_status, Ecto.Enum, values: [:unverified, :pending, :verified], default: :unverified
    field :verification_token, :string # For postcard/OTP verification
    field :verified_at, :utc_datetime

    belongs_to :user, Kollective.Accounts.User

    has_many :upvotes, Kollective.Businesses.Upvote
    has_many :comments, Kollective.Businesses.Comment
    timestamps()
  end

  def changeset(business, attrs) do
    business
    |> cast(attrs, [:name, :description, :type, :category, :address, :zip, :email, :phone, :website, :location])
    |> validate_required([:name, :description, :type, :category])
    |> validate_existing_fields() # Custom validation
  end

  defp validate_existing_fields(changeset) do
    type = get_field(changeset, :type)
    category = get_field(changeset, :category)

    if type == :existing do
      if category == :online do
        # Online businesses MUST have a website or email to be discoverable
        changeset
        |> validate_required([:website, :email])
      else
        # Physical businesses still require address/phone
        changeset
        |> validate_required([:address, :zip, :phone])
      end
    else
      changeset
    end
  end

end
