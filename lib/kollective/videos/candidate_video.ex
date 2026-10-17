defmodule Kollective.Videos.CandidateVideo do
  use Kollective.Schemas.Schema

  @derive {Jason.Encoder,
           only: [
             :id,
             :title,
             :video_url,
             :thumbnail_url,
             :description,
             :status,
             :office_level,
             :district_code,
             :sub_local_name,
             :scope,
             :target_district,
             :target_state,
             :target_country,
             :votes_count,
             :likes_count,
             :user_id,
             :inserted_at,
             :updated_at
           ]}
  schema "candidate_videos" do
    field :title, :string
    field :video_url, :string

    # Added for preview images
    field :thumbnail_url, :string

    field :description, :string
    field :status, Ecto.Enum, values: [:published, :pending, :rejected], default: :published

    # "congress" | "state_senate" | "state_rep" | "municipal" | "county"
    field :office_level, :string
    # e.g., "tx-10" or location slug "austin_tx"
    field :district_code, :string
    # e.g., "City Council Place 2", "County Sheriff"
    field :sub_local_name, :string

    # "city" | "state_senate" | "state_rep" | "congress" | "at_large"
    field :scope, Ecto.Enum, values: [:city, :state_senate, :state_rep, :congress, :at_large]

    belongs_to :user, Kollective.Accounts.User

    # The specific ID/Name of the district (if applicable)
    field :target_district, :string
    field :target_state, :string
    field :target_country, :string, default: "US"

    # Engagement Counters (Counter Caches)
    field :votes_count, :integer, default: 0
    field :likes_count, :integer, default: 0

    has_many :votes, Kollective.Videos.Vote, foreign_key: :video_id
    has_many :likes, Kollective.Videos.Like, foreign_key: :video_id

    timestamps()
  end

  def changeset(candidate_video, attrs) do
    candidate_video
    |> cast(attrs, [
      :title,
      :video_url,
      :votes_count,
      :office_level,
      :district_code,
      :sub_local_name,
      :user_id
    ])
    |> validate_required([:video_url, :office_level, :district_code, :user_id])
    # Dynamically validate that municipal or county posts explicitly state their specific seat target titles
    |> validate_sub_local_requirement()
  end

  defp validate_sub_local_requirement(changeset) do
    level = get_field(changeset, :office_level)
    sub_local = get_field(changeset, :sub_local_name)

    if level in ["municipal", "county"] && (is_nil(sub_local) || String.trim(sub_local) == "") do
      add_error(
        changeset,
        :sub_local_name,
        "Municipal and County office tracks must specify a target position name."
      )
    else
      changeset
    end
  end
end
