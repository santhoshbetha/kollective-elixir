# lib/kollective/campaigns/candidacy_application.ex
defmodule Kollective.Campaigns.CandidacyApplication do
  use Kollective.Schemas.Schema

  @derive {Jason.Encoder,
           only: [
             :id,
             :status,
             :declared_profession,
             :employment_proof_url,
             :vouches_count,
             :user_id,
             :linkedin_url
           ]}
  @derive {JSON.Encoder,
           only: [
             :id,
             :status,
             :declared_profession,
             :employment_proof_url,
             :vouches_count,
             :user_id,
             :linkedin_url
           ]}
  schema "candidacy_applications" do
    field :status, :string, default: "pending_vouches"
    field :declared_profession, :string
    field :linkedin_url, :string
    field :employment_proof_url, :string
    field :vouches_count, :integer, default: 0

    belongs_to :user, Kollective.Accounts.User

    many_to_many :vouching_users, Kollective.Accounts.User,
      join_through: "candidacy_vouches",
      join_keys: [application_id: :id, vouching_user_id: :id]

    timestamps()
  end

  def changeset(application, attrs) do
    application
    |> cast(attrs, [
      :declared_profession,
      :employment_proof_url,
      :status,
      :user_id,
      :vouches_count,
      :linkedin_url
    ])
    |> validate_required([:declared_profession, :employment_proof_url, :user_id])
    |> validate_inclusion(:status, [
      "pending_vouches",
      "under_jury_review",
      "approved",
      "rejected"
    ])
    # 🛡️ URL Formatting Validation Guard
    |> validate_format(:linkedin_url, ~r/^https?:\/\/(www\.)?linkedin\.com\/in\/.+/i,
      message: "Must be a valid LinkedIn profile path link (e.g., https://linkedin.com)"
    )
  end
end
