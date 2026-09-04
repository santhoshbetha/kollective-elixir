# lib/kollective/moderation/abuse_report.ex
defmodule Kollective.Moderation.AbuseReport do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  @derive {JSON.Encoder, only: [:id, :comment, :status, :target_type, :target_id, :reporter_id]}
  schema "abuse_reports" do
    field :comment, :string
    field :status, :string, default: "open"
    field :target_type, :string
    field :target_id, :integer

    belongs_to :reporter, Kollective.Accounts.User, foreign_key: :reporter_id

    belongs_to :assigned_moderator, Kollective.Accounts.User, foreign_key: :assigned_moderator_id

    timestamps()
  end

  def changeset(abuse_report, attrs) do
    abuse_report
    |> cast(attrs, [
      :comment,
      :status,
      :target_type,
      :target_id,
      :reporter_id,
      :assigned_moderator_id
    ])
    |> validate_required([:comment, :target_type, :target_id, :reporter_id])
    |> validate_inclusion(:status, ["open", "resolved"])
    |> validate_inclusion(:target_type, ["candidate", "post", "comment"])
  end
end
