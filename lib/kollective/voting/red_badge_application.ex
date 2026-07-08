defmodule Kollective.Voting.RedBadgeApplication do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "red_badge_applications" do
    field :evidence_text, :string
    field :evidence_media_urls, {:array, :string}
    # "pending", "voting", "approved", "rejected"
    field :status, :string, default: "voting"
    field :target_badge_type, :string, default: "ProfessionalTeal"
    belongs_to :applicant, Kollective.Accounts.User

    timestamps()
  end

  def changeset(application, attrs) do
    application
    |> cast(attrs, [
      :evidence_text,
      :evidence_media_urls,
      :status,
      :target_badge_type,
      :applicant_id
    ])
    |> validate_required([:evidence_text, :applicant_id])
  end
end
