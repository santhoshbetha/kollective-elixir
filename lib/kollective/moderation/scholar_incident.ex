defmodule Kollective.Moderation.ScholarIncident do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "scholar_incidents" do
    field :status, :string, default: "pending"
    field :flag_type, :string
    field :description, :string
    field :target_username, :string
    field :orcid_id, :string
    field :historical_count, :integer, default: 0
    field :scraped_count, :integer, default: 0
    field :last_sync_at, :utc_datetime

    belongs_to :user, Kollective.Accounts.User
    belongs_to :resolved_by, Kollective.Accounts.User
    field :resolved_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(incident, attrs) do
    incident
    |> cast(attrs, [
      :status,
      :flag_type,
      :description,
      :target_username,
      :orcid_id,
      :historical_count,
      :scraped_count,
      :last_sync_at,
      :user_id,
      :resolved_by_id,
      :resolved_at
    ])
    |> validate_required([:user_id])
  end
end
