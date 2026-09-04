defmodule Kollective.Campaigns.Candidate do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "candidates" do
    field :profession, :string
    field :manifesto, :string
    # 🖼️ Flat string pointing to the object storage asset
    field :video_url, :string
    field :votes_count, :integer, default: 0
    field :country, :string, default: "US"
    field :district_id, :string

    belongs_to :account, Kollective.Accounts.User

    timestamps()
  end

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [
      :profession,
      :manifesto,
      :video_url,
      :country,
      :district_id,
      :account_id,
      :votes_count
    ])
    |> validate_required([
      :profession,
      :manifesto,
      :video_url,
      :country,
      :district_id,
      :account_id
    ])
    # Enforce character limits directly on the backend database layer
    |> validate_length(:profession, max: 50)
    |> validate_length(:manifesto, max: 2000)
  end
end
