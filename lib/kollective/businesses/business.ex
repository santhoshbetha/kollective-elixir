# To implement a Local Businesses feature with district-based visibility and a 60-mile radius
# discovery, you need a specialized context for business data and a geospatial query engine
# using PostGIS.

# 1. We will create a single businesses table with a type field to distinguish between a "Proposal" (Idea) and an "Existing" business.

# Critical Requirement: We use a geography type to store the exact coordinates for the 60-mile radius search.

# lib/kollective/businesses/business.ex
defmodule Kollective.Businesses.Business do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  @categories ~w(
    food_beverage technology retail services manufacturing construction
    healthcare education online agriculture sustainable_energy infrastructure cooperative other
  )

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
    community_garden organic_farm csa_coop urban_farm permaculture
    solar_coop community_wind energy_efficiency battery_storage
    mesh_networking tool_library community_space recycling_waste water_commons
    worker_coop consumer_coop housing_coop producer_coop
    general_other
  )

  # Collaborative and grassroots corporate entity classifications
  @legal_structures [
    "Cooperative",
    "Worker-Owned Co-op",
    "Community Land Trust",
    "Non-Profit",
    "Mutual Aid",
    "LLC",
    "Sole Proprietorship"
  ]

  schema "businesses" do
    field(:name, :string)
    field(:description, :string)

    # Standardized to direct string properties to match PostGIS and timeline query filters
    # "proposals" or "existing"
    field(:type, :string, default: "proposals")
    # From @categories list
    field(:category, :string, default: "other")
    # From @sub_categories list
    field(:sub_category, :string, default: "general_other")

    # Physical Contact metrics fields
    field(:address, :string)
    # Municipal city name text string
    field(:city, :string)
    # State code (e.g., "TX")
    field(:state, :string)
    field(:zip, :string)
    field(:country, :string, default: "US")
    field(:email, :string)
    field(:phone, :string)
    field(:website, :string)

    # Operational & Corporate Metadata Fields
    field(:year_established, :integer)
    field(:number_of_employees, :integer)
    # Restricted to @legal_structures
    field(:legal_structure, :string)
    # Direct-to-R2 profile thumbnail pointer
    field(:profile_image_url, :string)
    field(:is_image_processed, :boolean, default: false)

    # Political Boundary Caches & PostGIS Data Layer
    # Political Boundary Cache Nodes (Enables instant geofence grouping partitions)
    field(:district_l1, :string)
    field(:district_l2, :string)
    field(:district_l3, :string)

    belongs_to(:city_relation, Kollective.Locations.City, foreign_key: :city_id)

    # PostGIS geometric coordinates footprint data layer
    field(:location, Geo.PostGIS.Geometry)

    # Administrative Trust & Compliance Markers
    # "unverified", "pending", "verified"
    field(:verification_status, :string, default: "unverified")
    # Flexible JSONB block for business hours, etc.
    field(:metadata, :map, default: %{})

    field(:verification_token, :string)
    field(:verified_at, :utc_datetime)

    # COUNTER CACHE OPTIMIZATION: Keeps lookups extremely fast
    field(:upvotes_count, :integer, default: 0)
    field(:comments_count, :integer, default: 0)

    belongs_to(:user, Kollective.Accounts.User, foreign_key: :user_id)
    has_many(:upvotes, Kollective.Businesses.Upvote, foreign_key: :business_id)
    has_many(:comments, Kollective.Businesses.Comment, foreign_key: :business_id)

    timestamps()
  end

  @doc """
  Unified changesets validator for regional discovery registrations.
  """
  def creation_changeset(business, attrs) do
    # 🚀 FIX: Fallback sub_category mapping to avoid frontend validation drop-outs
    attrs =
      attrs
      |> normalize_business_attrs()
      # If no child classification is provided, default to general_other to clear Ecto guards safely
      |> then(fn map ->
        sub = Map.get(map, "sub_category") || Map.get(map, :sub_category)
        if is_nil(sub) || sub == "", do: Map.put(map, "sub_category", "general_other"), else: map
      end)

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
      :metadata,
      # 🚀 NEW: Register the processing status flag to allow background worker writes safely
      :is_image_processed
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
          sub in ~w(restaurant cafe_coffee bakery food_truck brewery_bar meal_prep general_other)

        {"technology", sub} ->
          sub in ~w(it_consulting device_repair software_saas hardware_networking general_other)

        {"retail", sub} ->
          sub in ~w(apparel_boutique grocery_market home_decor handmade_crafts bookstore general_other)

        {"services", sub} ->
          sub in ~w(hair_beauty cleaning_janitorial legal_accounting real_estate pet_care general_other)

        {"manufacturing", sub} ->
          sub in ~w(artisan_crafting apparel_textiles metal_woodworking food_processing general_other)

        {"construction", sub} ->
          sub in ~w(general_contractor plumbing electrical hvac roofing_masonry general_other)

        {"healthcare", sub} ->
          sub in ~w(medical_clinic dental fitness_gym mental_health physical_therapy general_other)

        {"education", sub} ->
          sub in ~w(tutoring k12_preschool music_art_lessons vocational_training general_other)

        {"online", sub} ->
          sub in ~w(ecommerce_shop digital_marketing saas_product virtual_assistance general_other)

        {"agriculture", sub} ->
          sub in ~w(community_garden organic_farm csa_coop urban_farm permaculture general_other)

        {"sustainable_energy", sub} ->
          sub in ~w(solar_coop community_wind energy_efficiency battery_storage general_other)

        {"infrastructure", sub} ->
          sub in ~w(mesh_networking tool_library community_space recycling_waste water_commons general_other)

        {"cooperative", sub} ->
          sub in ~w(worker_coop consumer_coop housing_coop producer_coop general_other)

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
        "is not a valid classification matching parent category #{category}."
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
    attrs =
      attrs
      |> normalize_proposal_attrs()
      |> then(fn map ->
        cat = Map.get(map, "category") || business.category || "other"
        sub = Map.get(map, "sub_category") || business.sub_category || default_subcategory_for(cat)
        map
        |> Map.put_new("category", cat)
        |> Map.put_new("sub_category", sub)
      end)

    business
    |> cast(attrs, [
      :name,
      :description,
      :type,
      :category,
      :sub_category,
      :address,
      :city,
      :state,
      :zip,
      :country,
      :district_l1,
      :district_l2,
      :district_l3,
      :city_id,
      :profile_image_url,
      :metadata
    ])
    |> validate_required([:name, :description, :category, :sub_category, :user_id])
    |> validate_inclusion(:type, ["proposals", "existing"])
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
    funding_data =
      attrs["funding_data"] || attrs[:funding_data] ||
        extract_funding_data_from_attrs(attrs)

    current_metadata = get_field(changeset, :metadata) || %{}

    img = attrs["profile_image_url"] || attrs[:profile_image_url] || attrs["image"] || attrs[:image]
    tags = attrs["tags"] || attrs[:tags] || attrs["looking_for"] || attrs[:looking_for]

    updated_metadata =
      current_metadata
      |> Map.put("funding_data", funding_data)
      |> then(fn meta ->
        meta = if img, do: Map.put(meta, "image", img) |> Map.put("profile_image_url", img), else: meta
        if tags && is_list(tags), do: Map.put(meta, "tags", tags) |> Map.put("looking_for", tags), else: meta
      end)

    put_change(changeset, :metadata, updated_metadata)
  end

  defp extract_funding_data_from_attrs(attrs) do
    funding_required? = attrs["funding_required"] || attrs[:funding_required] || false

    money_required =
      attrs["money_required"] || attrs[:money_required] || attrs["fundingGoal"] ||
        attrs[:fundingGoal] || 0

    min_amount =
      attrs["minimum_amount"] || attrs[:minimum_amount] || attrs["minInvest"] || attrs[:minInvest] ||
        0

    max_amount =
      attrs["maximum_amount"] || attrs[:maximum_amount] || attrs["maxInvest"] || attrs[:maxInvest] ||
        0

    %{
      "funding_required" => funding_required? || money_required > 0,
      "money_required" => parse_int(money_required, 0),
      "fundingGoal" => parse_int(money_required, 0),
      "minimum_amount" => parse_int(min_amount, 0),
      "minInvest" => parse_int(min_amount, 0),
      "maximum_amount" => parse_int(max_amount, 0),
      "maxInvest" => parse_int(max_amount, 0),
      "fundingCollected" =>
        parse_int(attrs["fundingCollected"] || attrs[:fundingCollected] || 0, 0),
      "percent" => parse_float(attrs["percent"] || attrs[:percent] || 0, 0.0),
      "daysLeft" => parse_int(attrs["daysLeft"] || attrs[:daysLeft] || 45, 45),
      "participants" => to_string(attrs["participants"] || attrs[:participants] || "0 Members"),
      "status" => to_string(attrs["status"] || attrs[:status] || "New")
    }
  end

  # ─── NORMALIZATION PIPELINES ───

  @doc """
  Normalizes frontend business payload parameters into schema expectations.
  Handles category display values, legal structure string normalization,
  established year parsing, employee range strings, image mapping, and metadata bundling.
  """
  def normalize_business_attrs(attrs) when is_map(attrs) do
    attrs
    |> stringify_keys()
    |> normalize_category()
    |> normalize_legal_structure()
    |> normalize_established()
    |> normalize_employees()
    |> normalize_business_image()
    |> normalize_business_metadata()
    |> normalize_sub_category()
    |> ensure_default_type("existing")
  end

  def normalize_business_attrs(attrs), do: attrs

  @doc """
  Normalizes frontend business proposal payload parameters.
  Maps title to name, standardizes funding goals, and packs proposal timeline parameters.
  """
  def normalize_proposal_attrs(attrs) when is_map(attrs) do
    attrs
    |> stringify_keys()
    |> normalize_proposal_name()
    |> normalize_category()
    |> normalize_proposal_funding()
    |> normalize_proposal_location()
    |> normalize_business_image()
    |> normalize_proposal_metadata()
    |> normalize_sub_category()
    |> ensure_default_type("proposals")
  end

  def normalize_proposal_attrs(attrs), do: attrs

  defp normalize_proposal_metadata(attrs) do
    meta = attrs["metadata"] || attrs[:metadata] || %{}

    img = attrs["profile_image_url"] || attrs[:profile_image_url] || attrs["image"] || attrs[:image]
    meta = if img, do: Map.put(meta, "image", img) |> Map.put("profile_image_url", img), else: meta

    tags = attrs["tags"] || attrs[:tags] || attrs["looking_for"] || attrs[:looking_for]
    meta = if tags && is_list(tags), do: Map.put(meta, "tags", tags) |> Map.put("looking_for", tags), else: meta

    owner = attrs["owner"] || attrs[:owner]
    meta = if owner, do: Map.put(meta, "owner_handle", owner), else: meta

    avatar = attrs["ownerAvatar"] || attrs[:ownerAvatar] || attrs["owner_avatar"]
    meta = if avatar, do: Map.put(meta, "owner_avatar", avatar), else: meta

    Map.put(attrs, "metadata", meta)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp ensure_default_type(attrs, default_type) do
    if is_nil(attrs["type"]) or attrs["type"] == "" do
      Map.put(attrs, "type", default_type)
    else
      attrs
    end
  end

  defp normalize_category(attrs) do
    raw_cat = attrs["category"] || attrs[:category]

    normalized =
      case raw_cat do
        val
        when val in ["Food & Beverage", "food_beverage", "Food and Beverage", "food & beverage"] ->
          "food_beverage"

        val when val in ["Healthcare", "healthcare", "Health & Fitness", "health_fitness"] ->
          "healthcare"

        val when val in ["Sustainable Energy", "sustainable_energy", "Clean Energy", "energy"] ->
          "sustainable_energy"

        val when val in ["Agriculture", "agriculture", "Farming", "Farming & Agriculture"] ->
          "agriculture"

        val when val in ["Infrastructure", "infrastructure", "Civic Infrastructure"] ->
          "infrastructure"

        val when val in ["Cooperative", "cooperative", "Co-op", "Mutual Aid"] ->
          "cooperative"

        val when val in ["Technology", "technology", "Tech"] ->
          "technology"

        val when val in ["Retail", "retail", "Commerce"] ->
          "retail"

        val when val in ["Services", "services", "Professional Services"] ->
          "services"

        val when val in ["Manufacturing", "manufacturing", "Makers"] ->
          "manufacturing"

        val when val in ["Construction", "construction", "Building"] ->
          "construction"

        val when val in ["Education", "education", "Learning"] ->
          "education"

        val when val in ["Online", "online", "Digital"] ->
          "online"

        val when is_binary(val) and val != "" ->
          slug =
            val
            |> String.downcase()
            |> String.replace(~r/[^a-z0-9]+/, "_")
            |> String.trim("_")

          if slug in @categories, do: slug, else: "other"

        _ ->
          "other"
      end

    Map.put(attrs, "category", normalized)
  end

  defp normalize_legal_structure(attrs) do
    raw =
      attrs["legal_structure"] || attrs[:legal_structure] ||
        attrs["legalStructure"] || attrs[:legalStructure]

    cleaned =
      case raw do
        val when is_binary(val) ->
          cond do
            String.contains?(val, "Worker-Owned") ->
              "Worker-Owned Co-op"

            String.contains?(val, "Cooperative") || String.contains?(val, "Co-op") ->
              "Cooperative"

            String.contains?(val, "Land Trust") ->
              "Community Land Trust"

            String.contains?(val, "Non-Profit") || String.contains?(val, "Nonprofit") ->
              "Non-Profit"

            String.contains?(val, "Mutual Aid") ->
              "Mutual Aid"

            String.contains?(val, "LLC") ->
              "LLC"

            String.contains?(val, "Sole") ->
              "Sole Proprietorship"

            true ->
              val
          end

        _ ->
          "Cooperative"
      end

    Map.put(attrs, "legal_structure", cleaned)
  end

  defp normalize_established(attrs) do
    est =
      attrs["year_established"] || attrs[:year_established] ||
        attrs["established"] || attrs[:established]

    val =
      case est do
        num when is_integer(num) ->
          num

        bin when is_binary(bin) ->
          case Integer.parse(bin) do
            {int, _} -> int
            _ -> nil
          end

        _ ->
          nil
      end

    if val do
      Map.put(attrs, "year_established", val)
    else
      attrs
    end
  end

  defp normalize_employees(attrs) do
    raw =
      attrs["number_of_employees"] || attrs[:number_of_employees] ||
        attrs["employees"] || attrs[:employees]

    case raw do
      num when is_integer(num) ->
        Map.put(attrs, "number_of_employees", num)

      bin when is_binary(bin) ->
        num =
          cond do
            bin in ["1-5", "1 - 5"] ->
              5

            bin in ["6-20", "6 - 20"] ->
              20

            bin in ["21-50", "21 - 50"] ->
              50

            bin in ["50+", "50 +"] ->
              100

            true ->
              case Integer.parse(bin) do
                {i, _} -> i
                _ -> 5
              end
          end

        meta = attrs["metadata"] || attrs[:metadata] || %{}
        updated_meta = Map.put(meta, "employee_range", bin)

        attrs
        |> Map.put("number_of_employees", num)
        |> Map.put("metadata", updated_meta)

      _ ->
        attrs
    end
  end

  defp normalize_business_image(attrs) do
    img =
      attrs["profile_image_url"] || attrs[:profile_image_url] ||
        attrs["image"] || attrs[:image]

    if img && is_nil(attrs["profile_image_url"]) do
      Map.put(attrs, "profile_image_url", img)
    else
      attrs
    end
  end

  defp normalize_business_metadata(attrs) do
    meta = attrs["metadata"] || attrs[:metadata] || %{}

    hours = attrs["hours"] || attrs[:hours] || attrs["business_hours"] || attrs[:business_hours]

    meta =
      if hours, do: Map.put(meta, "business_hours", hours) |> Map.put("hours", hours), else: meta

    services = attrs["services"] || attrs[:services] || attrs["tags"] || attrs[:tags]

    meta =
      if services && is_list(services),
        do: Map.put(meta, "services", services) |> Map.put("tags", services),
        else: meta

    owner = attrs["owner"] || attrs[:owner]
    meta = if owner, do: Map.put(meta, "owner_handle", owner), else: meta

    avatar = attrs["ownerAvatar"] || attrs[:ownerAvatar] || attrs["owner_avatar"]
    meta = if avatar, do: Map.put(meta, "owner_avatar", avatar), else: meta

    rating = attrs["rating"] || attrs[:rating]
    meta = if rating, do: Map.put(meta, "rating", rating), else: meta

    reviews_count = attrs["reviewsCount"] || attrs[:reviewsCount] || attrs["reviews_count"]
    meta = if reviews_count, do: Map.put(meta, "reviews_count", reviews_count), else: meta

    images = attrs["images"] || attrs[:images] || attrs["gallery"] || attrs[:gallery]
    meta =
      if images && is_list(images) do
        Map.put(meta, "images", images) |> Map.put("gallery", images)
      else
        meta
      end

    Map.put(attrs, "metadata", meta)
  end

  defp normalize_sub_category(attrs) do
    sub = attrs["sub_category"] || attrs[:sub_category]
    category = attrs["category"] || attrs[:category]

    if is_nil(sub) or sub == "" or sub not in @sub_categories do
      default_sub = default_subcategory_for(category)
      Map.put(attrs, "sub_category", default_sub)
    else
      attrs
    end
  end

  defp default_subcategory_for("food_beverage"), do: "restaurant"
  defp default_subcategory_for("technology"), do: "software_saas"
  defp default_subcategory_for("retail"), do: "grocery_market"
  defp default_subcategory_for("services"), do: "general_other"
  defp default_subcategory_for("manufacturing"), do: "artisan_crafting"
  defp default_subcategory_for("construction"), do: "general_contractor"
  defp default_subcategory_for("healthcare"), do: "medical_clinic"
  defp default_subcategory_for("education"), do: "general_other"
  defp default_subcategory_for("online"), do: "ecommerce_shop"
  defp default_subcategory_for("agriculture"), do: "community_garden"
  defp default_subcategory_for("sustainable_energy"), do: "solar_coop"
  defp default_subcategory_for("infrastructure"), do: "community_space"
  defp default_subcategory_for("cooperative"), do: "worker_coop"
  defp default_subcategory_for(_), do: "general_other"

  defp normalize_proposal_name(attrs) do
    name = attrs["name"] || attrs[:name] || attrs["title"] || attrs[:title]

    if name && (is_nil(attrs["name"]) or attrs["name"] == "") do
      Map.put(attrs, "name", name)
    else
      attrs
    end
  end

  defp normalize_proposal_funding(attrs) do
    funding_goal =
      attrs["money_required"] || attrs[:money_required] ||
        attrs["fundingGoal"] || attrs[:fundingGoal] ||
        attrs["funding_goal"] || attrs[:funding_goal] || 0

    min_invest =
      attrs["minimum_amount"] || attrs[:minimum_amount] ||
        attrs["minInvest"] || attrs[:minInvest] ||
        attrs["min_invest"] || attrs[:min_invest] || 0

    max_invest =
      attrs["maximum_amount"] || attrs[:maximum_amount] ||
        attrs["maxInvest"] || attrs[:maxInvest] ||
        attrs["max_invest"] || attrs[:max_invest] || 0

    funding_goal_int = parse_int(funding_goal, 0)
    min_invest_int = parse_int(min_invest, 0)
    max_invest_int = parse_int(max_invest, 0)

    funding_data = %{
      "funding_required" => funding_goal_int > 0,
      "money_required" => funding_goal_int,
      "fundingGoal" => funding_goal_int,
      "minimum_amount" => min_invest_int,
      "minInvest" => min_invest_int,
      "maximum_amount" => max_invest_int,
      "maxInvest" => max_invest_int,
      "fundingCollected" =>
        parse_int(attrs["fundingCollected"] || attrs[:fundingCollected] || 0, 0),
      "percent" => parse_float(attrs["percent"] || attrs[:percent] || 0, 0.0),
      "daysLeft" => parse_int(attrs["daysLeft"] || attrs[:daysLeft] || 45, 45),
      "participants" => to_string(attrs["participants"] || attrs[:participants] || "0 Members"),
      "status" => to_string(attrs["status"] || attrs[:status] || "New")
    }

    current_metadata = attrs["metadata"] || attrs[:metadata] || %{}
    updated_metadata = Map.merge(current_metadata, %{"funding_data" => funding_data})

    attrs
    |> Map.put("funding_required", funding_goal_int > 0)
    |> Map.put("money_required", funding_goal_int)
    |> Map.put("minimum_amount", min_invest_int)
    |> Map.put("maximum_amount", max_invest_int)
    |> Map.put("funding_data", funding_data)
    |> Map.put("metadata", updated_metadata)
  end

  defp normalize_proposal_location(attrs) do
    loc = attrs["location"] || attrs[:location]

    if is_binary(loc) and String.trim(loc) != "" and is_nil(attrs["address"]) do
      attrs
      |> Map.put("address", String.trim(loc))
      |> Map.put("city", String.trim(loc))
    else
      attrs
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      _ -> default
    end
  end

  defp parse_int(val, _default) when is_float(val), do: round(val)
  defp parse_int(_, default), do: default

  defp parse_float(val, _default) when is_float(val), do: val
  defp parse_float(val, _default) when is_integer(val), do: val * 1.0

  defp parse_float(val, default) when is_binary(val) do
    case Float.parse(val) do
      {num, _} -> num
      _ -> default
    end
  end

  defp parse_float(_, default), do: default
end
