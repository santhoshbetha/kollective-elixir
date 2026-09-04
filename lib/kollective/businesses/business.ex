# To implement a Local Businesses feature with district-based visibility and a 60-mile radius
# discovery, you need a specialized context for business data and a geospatial query engine
# using PostGIS.

# 1. We will create a single businesses table with a type field to distinguish between a "Proposal" (Idea) and an "Existing" business.

# Critical Requirement: We use a geography type to store the exact coordinates for the 60-mile radius search.

# lib/kollective/businesses/business.ex
defmodule Kollective.Businesses.Business do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  @categories ~w(food_beverage technology retail services manufacturing construction healthcare education online other)

  @sub_categories ~w(
    restaurant cafe_coffee bakery food_truck brewery_bar meal_prep
    it_consulting device_repair software_saas hardware_networking
    apparel_boutique grocery_market home_decor handmade_crafts bookstore
    hair_beauty cleaning_janitorial legal_accounting real_estate pet_care
    artisan_crafting apparel_textiles metal_woodworking food_processing
    general_contractor plumbing electrical hvac roofing_masonry
    medical_clinic dental fitness_gym mental_health physical_therapy
    tutoring k12_preschool music_art_lessons vocational_training
    ecommerce_shop digital_marketing saas_product virtual_assistance
    general_other
  )

  # Strict local corporate entity classifications
  @legal_structures ~w(Cooperative LLC Non-Profit Sole Proprietorship)

  schema "businesses" do
    field :name, :string
    field :description, :string

    # Standardized to direct string properties to match PostGIS and timeline query filters
    # "proposals" or "existing"
    field :type, :string, default: "proposals"
    # From @categories list
    field :category, :string, default: "other"
    # From @sub_categories list
    field :sub_category, :string, default: "general_other"

    # Physical Contact metrics fields
    field :address, :string
    # Municipal city name text string
    field :city, :string
    # State code (e.g., "TX")
    field :state, :string
    field :zip, :string
    field :country, :string, default: "US"
    field :email, :string
    field :phone, :string
    field :website, :string

    # Operational & Corporate Metadata Fields
    field :year_established, :integer
    field :number_of_employees, :integer
    # Restricted to @legal_structures
    field :legal_structure, :string
    # Direct-to-R2 profile thumbnail pointer
    field :profile_image_url, :string

    # Political Boundary Caches & PostGIS Data Layer
    # Political Boundary Cache Nodes (Enables instant geofence grouping partitions)
    field :district_l1, :string
    field :district_l2, :string
    field :district_l3, :string

    belongs_to :city_relation, Kollective.Locations.City, foreign_key: :city_id

    # PostGIS geometric coordinates footprint data layer
    field :location, Geo.PostGIS.Geometry

    # Administrative Trust & Compliance Markers
    # "unverified", "pending", "verified"
    field :verification_status, :string, default: "unverified"
    # Flexible JSONB block for business hours, etc.
    field :metadata, :map, default: %{}

    field :verification_token, :string
    field :verified_at, :utc_datetime

    # COUNTER CACHE OPTIMIZATION: Keeps lookups extremely fast
    field :upvotes_count, :integer, default: 0
    field :comments_count, :integer, default: 0

    belongs_to :user, Kollective.Accounts.User, foreign_key: :user_id
    has_many :upvotes, Kollective.Businesses.Upvote, foreign_key: :business_id
    has_many :comments, Kollective.Businesses.Comment, foreign_key: :business_id

    timestamps()
  end

  @doc """
  Unified changesets validator for regional discovery registrations.
  """
  def creation_changeset(business, attrs) do
    business
    |> cast(attrs, [
      :name,
      :description,
      :type,
      :category,
      :sub_category,
      :address,
      :city,
      :zip,
      :email,
      :phone,
      :website,
      :year_established,
      :number_of_employees,
      :legal_structure,
      :city_id,
      :district_l1,
      :district_l2,
      :district_l3,
      :state,
      :country,
      :profile_image_url,
      :metadata
    ])
    |> validate_required([
      :name,
      :description,
      :type,
      :category,
      :sub_category,
      :address,
      :city,
      :state,
      :zip,
      :email,
      :phone,
      :legal_structure,
      :user_id
    ])
    |> validate_inclusion(:type, ["proposals", "existing"])
    |> validate_inclusion(:category, @categories)
    |> validate_inclusion(:sub_category, @sub_categories)
    |> validate_length(:name, max: 150)
    |> validate_length(:description, max: 5000)
    |> validate_inclusion(:legal_structure, @legal_structures)
    |> validate_number(:year_established, greater_than: 1700, less_than_or_equal_to: 2027)
    |> validate_number(:number_of_employees, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_id)
    # Strict database structural safety check for your city relationship
    |> foreign_key_constraint(:city_id)
    |> validate_sub_category_alignment()
    |> validate_conditional_fields_by_type()
    |> Kollective.Locations.GeoUtilities.cast_postgis_location(attrs)
  end

  # --- Structural Domain Guard Checkers ---

  defp validate_sub_category_alignment(changeset) do
    category = get_field(changeset, :category)
    sub_category = get_field(changeset, :sub_category)

    # Cross-checks parent-child classification alignment rules natively
    valid_alignment? =
      case {category, sub_category} do
        {"food_beverage", sub} ->
          sub in ~w(restaurant cafe_coffee bakery food_truck brewery_bar meal_prep)

        {"technology", sub} ->
          sub in ~w(it_consulting device_repair software_saas hardware_networking)

        {"retail", sub} ->
          sub in ~w(apparel_boutique grocery_market home_decor handmade_crafts bookstore)

        {"services", sub} ->
          sub in ~w(hair_beauty cleaning_janitorial legal_accounting real_estate pet_care)

        {"manufacturing", sub} ->
          sub in ~w(artisan_crafting apparel_textiles metal_woodworking food_processing)

        {"construction", sub} ->
          sub in ~w(general_contractor plumbing electrical hvac roofing_masonry)

        {"healthcare", sub} ->
          sub in ~w(medical_clinic dental fitness_gym mental_health physical_therapy)

        {"education", sub} ->
          sub in ~w(tutoring k12_preschool music_art_lessons vocational_training)

        {"online", sub} ->
          sub in ~w(ecommerce_shop digital_marketing saas_product virtual_assistance)

        {_other, "general_other"} ->
          true

        _mismatch ->
          false
      end

    if valid_alignment? do
      changeset
    else
      add_error(
        changeset,
        :sub_category,
        "is not a valid classification matching the parent category category."
      )
    end
  end

  defp validate_conditional_fields_by_type(changeset) do
    type = get_field(changeset, :type)
    category = get_field(changeset, :category)

    if type == "existing" do
      if category == "online" do
        # Online entities must expose contact anchors to clear verification
        changeset |> validate_required([:website, :email])
      else
        # Brick-and-mortar storefronts require distinct physical perimeters
        changeset |> validate_required([:address, :zip, :phone])
      end
    else
      # Ideas/Proposals skip intensive structural validations to maximize rapid onboarding
      changeset
    end
  end

  @doc """
  White-listed changeset for user-facing business ideas and proposals.
  Enforces category structures and embeds financing parameters securely inside JSONB.
  """
  def proposal_changeset(business, attrs) do
    business
    |> cast(attrs, [
      :name,
      :description,
      :category,
      :sub_category,
      :address,
      :city,
      :state,
      :zip,
      :district_l1,
      :district_l2,
      :state,
      :city_id
    ])
    |> validate_required([:name, :description, :category, :sub_category, :user_id])
    |> validate_inclusion(:category, @categories)
    |> validate_inclusion(:sub_category, @sub_categories)
    |> validate_length(:name, max: 150)
    |> validate_length(:description, max: 5000)
    |> foreign_key_constraint(:user_id)
    # Enforce database boundary safety
    |> foreign_key_constraint(:city_id)
    # Intercepts raw latitude/longitude inputs to inject PostGIS points natively
    |> Kollective.Locations.GeoUtilities.cast_postgis_location(attrs)
    |> validate_sub_category_alignment()
    |> cast_proposal_funding_metadata(attrs)
  end

  defp cast_proposal_funding_metadata(changeset, attrs) do
    # Extract financing attributes from raw input parameters securely
    funding_required? = attrs["funding_required"] || attrs[:funding_required] || false
    money_required = attrs["money_required"] || attrs[:money_required] || 0
    min_amount = attrs["minimum_amount"] || attrs[:minimum_amount] || 0
    max_amount = attrs["maximum_amount"] || attrs[:maximum_amount] || 0

    # Package values inside a structured sub-map dictionary
    funding_map = %{
      "funding_required" => funding_required?,
      "money_required" => money_required,
      "minimum_amount" => min_amount,
      "maximum_amount" => max_amount
    }

    # Merge fields cleanly into your core JSONB metadata block
    current_metadata = get_field(changeset, :metadata) || %{}
    updated_metadata = Map.merge(current_metadata, %{"funding_data" => funding_map})

    put_change(changeset, :metadata, updated_metadata)
  end
end
