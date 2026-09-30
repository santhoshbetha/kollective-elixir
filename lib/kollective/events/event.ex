defmodule Kollective.Events.Event do
  use Kollective.Schemas.Schema
  use Waffle.Ecto.Schema
  import Ecto.Changeset

  alias Kollective.Posts.Post

  @type t :: %__MODULE__{}

  @join_modes ["free", "restricted", "invite_only"]

  schema "events" do
    belongs_to(:post, Post)
    belongs_to :user, Kollective.Accounts.User, foreign_key: :created_by

    # Event details
    # Form Input: "Action Title"
    field(:title, :string)
    # Form Input: "Core Objective"
    field(:description, :string)

    # 1. Action Type Classifiers (Differentiates standard events from collective actions)
    # Allowed categories: "protest", "town_hall", "rally", "meeting", "standard"
    field(:category, :string, default: "standard")
    # 2. Location & Logistics Parameters (From Step 2 of your Frontend Wizard)
    # "in_person" or "online_virtual"
    field(:participation_format, :string, default: "in_person")
    # Combined "Date" + "Start Time" inputs
    field(:start_time, :utc_datetime)
    field(:end_time, :utc_datetime)

    # 3. Organization Identity Context Layer (Enables the "OFFICIAL" verification badge)
    belongs_to :organization, Kollective.Accounts.User,
      foreign_key: :organization_id,
      type: Ecto.ULID

    # e.g., "America/New_York"
    field(:timezone, :string)
    # Free, Restricted, Invite Only
    field(:join_mode, :string, default: "free")

    field :banner_url, Kollective.Media.EventBanner.Type
    field(:logo_url, :string)
    field(:show_banner, :boolean, default: true)

    # Counters
    field(:participants_count, :integer, default: 0)
    field(:participation_request_count, :integer, default: 0)

    # Location information
    # Form Input: "Venue Name"
    field(:location_name, :string)
    field(:location_url, :string)

    field(:longitude, :float)
    field(:latitude, :float)

    # Unpacked from "Full Address"
    field(:street, :string)
    field(:postal_code, :string)

    field(:locality, :string)
    field(:region, :string)

    field :city_name, :string
    field(:country, :string)

    # Additional data
    field(:metadata, :map, default: %{})

    # Virtual field for user-specific data
    field(:join_state, :string, virtual: true)

    field :event_status, :string, default: "published"

    # --- NEW JURISDICTION FIELDS ---
    field :target_scope, Ecto.Enum, values: [:local, :state, :country, :world], default: :local

    # federal_district                    # India: MP / US: Congress
    field :origin_district_l1, :string

    # state_senate_district               # India: ?? / US: State Senate (Upper House)
    field :origin_district_l2, :string

    # state_district                      # India: MLA / US: State House Representative (Lower House)
    field :origin_district_l3, :string

    # field :origin_city_id, :integer
    belongs_to :origin_city, Kollective.Locations.City, foreign_key: :origin_city_id

    field :location, Geo.PostGIS.Geometry

    field :origin_state, :string
    field :origin_country, :string, default: "US"

    field :comments_count, :integer, default: 0
    has_many :comments, Kollective.Events.Comment, foreign_key: :event_id

    timestamps()
  end

  # lib/kollective/events/event.ex

  @join_modes ~w(free restricted invite_only)

  @doc """
  The authoritative validation footprint for community event creation.
  Integrates full metadata fields, timing controls, and capacity boundaries natively.
  """
  def creation_changeset(%__MODULE__{} = event, attrs) do
    attrs = normalize_event_attrs(attrs)

    event
    |> cast(attrs, [
      :post_id,
      :created_by,
      # Form Input: "Action Title"
      :title,
      # Form Input: "Core Objective"
      :description,
      # "protest", "town_hall", "rally", "meeting", "standard"
      :category,
      # "in_person" or "online_virtual"
      :participation_format,
      # Combined "Date" + "Start Time" inputs
      :start_time,
      :end_time,
      :join_mode,
      :participants_count,
      :participation_request_count,

      # ─── FULL RICH LOCATION METADATA FIELDS ───
      # Form Input: "Venue Name"
      :location_name,
      :location_url,
      # Unpacked from "Full Address"
      :street,
      :postal_code,
      :locality,
      :region,
      :city_name,
      :country,
      :metadata,
      :logo_url,
      :show_banner,
      :target_scope,
      :origin_state,
      :origin_country,
      :origin_district_l1,
      :origin_district_l2,
      :origin_district_l3,
      # Standardized to match your unified schema foreign key relationship name
      :origin_city_id,
      :latitude,
      :longitude,
      :location
    ])
    |> maybe_cast_banner_attachment(attrs)
    # 1. OPTIMIZATION: Extract capacity limits and stash them directly into the JSONB map buffer
    |> put_capacity_metadata(attrs)

    # 2. CORE INTEGRITY VALIDATIONS
    # Removed :city_id to support rural/unincorporated onboarding seamlessly
    |> validate_required([:title, :created_by, :join_mode])
    |> validate_required([:description, :category, :participation_format, :start_time])
    |> validate_inclusion(:join_mode, @join_modes)
    |> validate_length(:title, min: 1, max: 255)
    |> validate_length(:description, max: 5000)
    |> validate_conditional_logistics()

    # 3. DOMAIN SECURITY LOGIC CHECKS
    |> validate_capacity()
    |> validate_times()
    |> validate_url(:banner_url)
    |> validate_url(:logo_url)

    # 4. DATABASE FOREIGN KEY INTEGRITY GUARDS
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:created_by)
    # Standard database safety constraints path
    |> foreign_key_constraint(:origin_city_id)

    # 5. GEOSPATIAL POSTGIS COORDINATE CONVERTER
    # Automatically packs incoming lat/lng inputs into a single spatial POINT location column
    |> Kollective.Locations.GeoUtilities.cast_postgis_location(attrs)
    |> sync_coordinates_and_location()
  end

  defp sync_coordinates_and_location(changeset) do
    lat = get_field(changeset, :latitude)
    lng = get_field(changeset, :longitude)
    loc = get_field(changeset, :location)

    case loc do
      %Geo.Point{coordinates: {point_lng, point_lat}} when is_nil(lat) or is_nil(lng) ->
        changeset
        |> put_change(:latitude, point_lat)
        |> put_change(:longitude, point_lng)

      _ ->
        if is_nil(loc) and not is_nil(lat) and not is_nil(lng) do
          point = %Geo.Point{coordinates: {lng, lat}, srid: 4326}
          put_change(changeset, :location, point)
        else
          changeset
        end
    end
  end

  # ─── INTERNAL PRIVATE STRUCTURAL VALIDATION HELPERS ───
  @doc """
  Normalizes frontend payload attributes to match backend schema expectations.
  Handles parameter naming variations (format vs participation_format, capacity vs max_participants,
  image vs banner_url, location string unpacking, and human date/time parsing).
  """
  def normalize_event_attrs(attrs) when is_map(attrs) do
    attrs
    |> stringify_keys()
    |> normalize_format()
    |> normalize_banner()
    |> normalize_location()
    |> normalize_capacity()
    |> normalize_timing()
    |> normalize_defaults()
  end

  def normalize_event_attrs(attrs), do: attrs

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp normalize_format(attrs) do
    raw_format =
      attrs["participation_format"] || attrs[:participation_format] ||
        attrs["format"] || attrs[:format] || attrs["formatType"] || attrs[:formatType]

    case raw_format do
      val when val in ["in_person", "In-Person", "in-person", "physical"] ->
        Map.put(attrs, "participation_format", "in_person")

      val when val in ["online_virtual", "Online", "online", "virtual", "Online/Virtual"] ->
        Map.put(attrs, "participation_format", "online_virtual")

      val when val in ["hybrid", "Hybrid"] ->
        Map.put(attrs, "participation_format", "hybrid")

      val when is_binary(val) and val != "" ->
        Map.put(attrs, "participation_format", String.downcase(val))

      _ ->
        attrs
    end
  end

  defp normalize_banner(attrs) do
    banner =
      attrs["banner_url"] || attrs[:banner_url] ||
        attrs["image"] || attrs[:image] ||
        attrs["coverImage"] || attrs[:coverImage] ||
        attrs["cover_image"] || attrs[:cover_image]

    if banner && !attrs["banner_url"] && !attrs[:banner_url] do
      Map.put(attrs, "banner_url", banner)
    else
      attrs
    end
  end

  defp normalize_location(attrs) do
    loc_val = attrs["location"] || attrs[:location]

    if is_binary(loc_val) and String.trim(loc_val) != "" do
      loc_str = String.trim(loc_val)

      attrs
      # Remove the string "location" key so Ecto does not attempt to cast
      # a plain text address into Geo.PostGIS.Geometry
      |> Map.delete("location")
      |> Map.delete(:location)
      |> maybe_put_str("location_name", loc_str)
      |> maybe_put_str("street", loc_str)
      |> maybe_put_url("location_url", loc_str)
    else
      loc_str =
        attrs["location_name"] || attrs[:location_name] ||
          attrs["address"] || attrs[:address]

      if is_binary(loc_str) and String.trim(loc_str) != "" do
        clean = String.trim(loc_str)

        attrs
        |> maybe_put_str("location_name", clean)
        |> maybe_put_str("street", clean)
        |> maybe_put_url("location_url", clean)
      else
        attrs
      end
    end
  end

  defp maybe_put_url(attrs, key, str) do
    if String.starts_with?(str, ["http://", "https://"]) do
      maybe_put_str(attrs, key, str)
    else
      attrs
    end
  end

  defp maybe_put_str(map, key, val) do
    if is_nil(map[key]) and is_nil(map[String.to_atom(key)]) do
      Map.put(map, key, val)
    else
      map
    end
  end

  defp normalize_capacity(attrs) do
    cap =
      attrs["capacity"] || attrs[:capacity] ||
        attrs["max_participants"] || attrs[:max_participants]

    if cap && is_nil(attrs["max_participants"]) && is_nil(attrs[:max_participants]) do
      Map.put(attrs, "max_participants", cap)
    else
      attrs
    end
  end

  defp normalize_timing(attrs) do
    attrs
    |> normalize_start_time()
    |> normalize_end_time()
  end

  defp normalize_start_time(attrs) do
    existing_start = attrs["start_time"] || attrs[:start_time]

    cond do
      is_struct(existing_start, DateTime) ->
        attrs

      is_binary(existing_start) and String.trim(existing_start) != "" ->
        case DateTime.from_iso8601(existing_start) do
          {:ok, dt, _} -> Map.put(attrs, "start_time", dt)
          _ -> parse_from_date_and_time(attrs, :start)
        end

      true ->
        parse_from_date_and_time(attrs, :start)
    end
  end

  defp normalize_end_time(attrs) do
    existing_end = attrs["end_time"] || attrs[:end_time]

    cond do
      is_struct(existing_end, DateTime) ->
        attrs

      is_binary(existing_end) and String.trim(existing_end) != "" ->
        case DateTime.from_iso8601(existing_end) do
          {:ok, dt, _} -> Map.put(attrs, "end_time", dt)
          _ -> parse_from_date_and_time(attrs, :end)
        end

      true ->
        parse_from_date_and_time(attrs, :end)
    end
  end

  defp parse_from_date_and_time(attrs, :start) do
    date_str = attrs["startDate"] || attrs[:startDate] || attrs["date"] || attrs[:date]

    time_str =
      attrs["startTime"] || attrs[:startTime] ||
        extract_start_from_time_range(attrs["time"] || attrs[:time])

    case combine_date_time_to_utc(date_str, time_str) do
      {:ok, dt} -> Map.put(attrs, "start_time", dt)
      _ -> attrs
    end
  end

  defp parse_from_date_and_time(attrs, :end) do
    date_str =
      attrs["endDate"] || attrs[:endDate] ||
        attrs["startDate"] || attrs[:startDate] ||
        attrs["date"] || attrs[:date]

    time_str =
      attrs["endTime"] || attrs[:endTime] ||
        extract_end_from_time_range(attrs["time"] || attrs[:time])

    case combine_date_time_to_utc(date_str, time_str) do
      {:ok, dt} -> Map.put(attrs, "end_time", dt)
      _ -> attrs
    end
  end

  defp extract_start_from_time_range(time_range) when is_binary(time_range) do
    case String.split(time_range, ~r/\s*-\s*/) do
      [start_part | _] -> String.trim(start_part)
      _ -> nil
    end
  end

  defp extract_start_from_time_range(_), do: nil

  defp extract_end_from_time_range(time_range) when is_binary(time_range) do
    case String.split(time_range, ~r/\s*-\s*/) do
      [_start_part, end_part | _] -> String.trim(end_part)
      _ -> nil
    end
  end

  defp extract_end_from_time_range(_), do: nil

  defp combine_date_time_to_utc(date_str, time_str) when is_binary(date_str) do
    date_clean = String.trim(date_str)

    with {:ok, date} <- parse_date_string(date_clean),
         {:ok, time} <- parse_time_string(time_str) do
      case DateTime.new(date, time, "Etc/UTC") do
        {:ok, dt} -> {:ok, dt}
        _ -> :error
      end
    else
      _ -> :error
    end
  end

  defp combine_date_time_to_utc(_, _), do: :error

  defp parse_date_string(str) do
    case Date.from_iso8601(str) do
      {:ok, date} ->
        {:ok, date}

      _ ->
        case Regex.run(~r/([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})/, str) do
          [_, month_name, day_str, year_str] ->
            month = month_name_to_number(month_name)
            day = String.to_integer(day_str)
            year = String.to_integer(year_str)
            if month, do: Date.new(year, month, day), else: :error

          _ ->
            :error
        end
    end
  end

  defp parse_time_string(str) when is_binary(str) do
    clean = String.trim(str)

    cond do
      clean == "" ->
        {:ok, ~T[00:00:00]}

      Regex.match?(~r/^\d{1,2}:\d{2}(:\d{2})?$/, clean) ->
        parts = String.split(clean, ":")
        h = String.to_integer(Enum.at(parts, 0))
        m = String.to_integer(Enum.at(parts, 1))
        s = if Enum.at(parts, 2), do: String.to_integer(Enum.at(parts, 2)), else: 0
        Time.new(h, m, s)

      true ->
        {:ok, ~T[00:00:00]}
    end
  end

  defp parse_time_string(_), do: {:ok, ~T[00:00:00]}

  defp month_name_to_number(name) do
    case String.downcase(String.slice(name, 0, 3)) do
      "jan" -> 1
      "feb" -> 2
      "mar" -> 3
      "apr" -> 4
      "may" -> 5
      "jun" -> 6
      "jul" -> 7
      "aug" -> 8
      "sep" -> 9
      "oct" -> 10
      "nov" -> 11
      "dec" -> 12
      _ -> nil
    end
  end

  defp normalize_defaults(attrs) do
    attrs
    |> maybe_put_str("join_mode", "free")
    |> maybe_put_str("category", "standard")
  end

  defp put_capacity_metadata(changeset, attrs) do
    # Extract the parameter supporting both string and atom parameter keys safely
    max_value =
      attrs["max_participants"] || attrs[:max_participants] ||
        attrs["capacity"] || attrs[:capacity]

    cond do
      is_nil(max_value) or max_value == "" ->
        changeset

      is_integer(max_value) ->
        metadata = get_field(changeset, :metadata) || %{}
        put_change(changeset, :metadata, Map.put(metadata, "max_participants", max_value))

      is_binary(max_value) ->
        # SAFELY PARSE STRINGS: Forms pass numbers as strings (e.g., "50")
        case Integer.parse(max_value) do
          {parsed_int, ""} ->
            metadata = get_field(changeset, :metadata) || %{}
            put_change(changeset, :metadata, Map.put(metadata, "max_participants", parsed_int))

          _ ->
            # If the string contains junk text, inject a malformed string value
            # so that validate_capacity handles the error tuple cleanly
            metadata = get_field(changeset, :metadata) || %{}
            put_change(changeset, :metadata, Map.put(metadata, "max_participants", :invalid))
        end
    end
  end

  defp validate_capacity(changeset) do
    metadata = get_field(changeset, :metadata) || %{}

    case metadata["max_participants"] do
      nil -> changeset
      val when is_integer(val) and val > 0 -> changeset
      _ -> add_error(changeset, :metadata, "max_participants must be a positive integer")
    end
  end

  defp validate_times(changeset) do
    start_time = get_field(changeset, :start_time)
    end_time = get_field(changeset, :end_time)

    cond do
      is_nil(start_time) and is_nil(end_time) ->
        changeset

      is_nil(start_time) ->
        add_error(changeset, :start_time, "must be set when end_time is provided")

      is_nil(end_time) ->
        changeset

      DateTime.compare(start_time, end_time) == :gt ->
        add_error(changeset, :end_time, "must be after start_time")

      true ->
        changeset
    end
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      cond do
        is_nil(value) || value == "" || is_struct(value) || is_map(value) ->
          []

        is_binary(value) and String.starts_with?(value, ["http://", "https://"]) ->
          []

        true ->
          [
            {field,
             "must be a valid secure asset URL structure matching a web prefix (http/https)."}
          ]
      end
    end)
  end

  defp validate_conditional_logistics(changeset) do
    format = get_field(changeset, :participation_format)

    if format in ["in_person", "hybrid"] do
      # Physical or hybrid actions demand concrete location strings to safeguard grassroots coordination
      changeset |> validate_required([:location_name, :street])
    else
      # Virtual coordinate lookups bypass physical address validators
      changeset
    end
  end

  # defp parseInt(val) when is_binary(val), do: String.to_integer(val)
  # defp parseInt(val) when is_integer(val), do: val
  # defp parseInt(_), do: nil

  # defp validate_location(changeset) do
  # FIX: Using get_field instead of get_change ensures validations run
  # during both initial creation and subsequent profile edits.
  # latitude = get_field(changeset, :latitude)
  # longitude = get_field(changeset, :longitude)

  # changeset
  #  |> validate_latitude(latitude)
  #  |> validate_longitude(longitude)
  # end

  # defp validate_latitude(changeset, nil), do: changeset

  # defp validate_latitude(changeset, latitude) do
  #  if latitude >= -90 and latitude <= 90 do
  #    changeset
  #  else
  #    add_error(changeset, :latitude, "must be between -90 and 90")
  #  end
  # end

  # defp validate_longitude(changeset, nil), do: changeset

  # defp validate_longitude(changeset, longitude) do
  #  if longitude >= -180 and longitude <= 180 do
  #    changeset
  #  else
  defp maybe_cast_banner_attachment(changeset, attrs) do
    banner = Map.get(attrs, "banner_url") || Map.get(attrs, :banner_url)

    case banner do
      url when is_binary(url) ->
        put_change(changeset, :banner_url, %{file_name: url, updated_at: nil})

      _ ->
        cast_attachments(changeset, attrs, [:banner_url])
    end
  end
end
