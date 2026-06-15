defmodule Kollective.Events.Event do
  use Kollective.Schemas.Schema

  alias Kollective.Posts.Post
  alias Kollective.Events.Event

  @type t :: %__MODULE__{}

  @join_modes ["free", "restricted", "invite_only"]

  schema "events" do
    belongs_to(:post, Post)
    belongs_to :user, Kollective.Accounts.User, foreign_key: :created_by

    # Event details
    field(:name, :string)
    field(:description, :string)
    field(:start_time, :utc_datetime)
    field(:end_time, :utc_datetime)
    # e.g., "America/New_York"
    field :timezone, :string
    field(:join_mode, :string, default: "free")

    field(:banner_url, :string)
    field(:logo_url, :string)
    field(:show_banner, :boolean, default: true)

    # Counters
    field(:participants_count, :integer, default: 0)
    field(:participation_request_count, :integer, default: 0)

    # Location information
    field(:location_name, :string)
    field(:location_url, :string)
    field(:longitude, :float)
    field(:latitude, :float)
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

    #field :origin_city_id, :integer
    belongs_to :origin_city, Kollective.Locations.City, foreign_key: :origin_city_id

    field :origin_state,   :string
    field :origin_country, :string, default: "US"

    field :comments_count, :integer, default: 0
    has_many :comments, Kollective.Events.Comment, foreign_key: :event_id

    timestamps(type: :utc_datetime)
  end

  def changeset(%Event{} = event, attrs) do
    event
    |> cast(attrs, [
      :post_id,
      :user_id,
      :name,
      :description,
      :start_time,
      :end_time,
      :join_mode,
      :participants_count,
      :participation_request_count,
      :location_name,
      :location_url,
      :longitude,
      :latitude,
      :street,
      :postal_code,
      :locality,
      :region,
      :country,
      :metadata,
      :banner_url,
      :logo_url,
      :show_banner
    ])
    # 1. New: Extract capacity and put it into the metadata map
    |> put_capacity_metadata(attrs)
    # 2. Existing validations
    |> validate_required([:name, :start_time]) # Added start_time as required for modern apps
    |> validate_inclusion(:join_mode, @join_modes)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:description, max: 5000)
    # 3. New: Validate that max_participants (if present) is a sane number
    |> validate_capacity()
    |> validate_times()
    |> validate_location()
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:user_id)
    # You can add URL format validation here if you want to be strict
    |> validate_url(:banner_url)
    |> validate_url(:logo_url)
  end

  # --- Helper Functions ---
  defp put_capacity_metadata(changeset, %{"max_participants" => max}) do
    # Merges max_participants into the existing metadata map
    metadata = get_field(changeset, :metadata) || %{}
    put_change(changeset, :metadata, Map.put(metadata, "max_participants", max))
  end

  defp put_capacity_metadata(changeset, _), do: changeset

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

  defp validate_location(changeset) do
    latitude = get_change(changeset, :latitude)
    longitude = get_change(changeset, :longitude)

    changeset
    |> validate_latitude(latitude)
    |> validate_longitude(longitude)
  end

  defp validate_latitude(changeset, nil), do: changeset

  defp validate_latitude(changeset, latitude) do
    if latitude >= -90 and latitude <= 90 do
      changeset
    else
      add_error(changeset, :latitude, "must be between -90 and 90")
    end
  end

  defp validate_longitude(changeset, nil), do: changeset

  defp validate_longitude(changeset, longitude) do
    if longitude >= -180 and longitude <= 180 do
      changeset
    else
      add_error(changeset, :longitude, "must be between -180 and 180")
    end
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if String.starts_with?(value, ["http://", "https://"]) do
        []
      else
        [{field, "must be a valid URL"}]
      end
    end)
  end

end
