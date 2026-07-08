defmodule Kollective.Voting.ApplicationJury do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "application_juries" do
    # "unvoted", "approve", "reject"
    field :vote, :string, default: "unvoted"
    field :voted_at, :naive_datetime
    belongs_to :application, Kollective.Voting.RedBadgeApplication
    belongs_to :juror, Kollective.Accounts.User

    timestamps()
  end

  def changeset(jury, attrs) do
    jury
    |> cast(attrs, [:vote, :voted_at, :application_id, :juror_id])
    |> validate_required([:application_id, :juror_id])
    |> unique_constraint([:application_id, :juror_id],
      name: :application_juries_application_id_juror_id_index
    )
  end
end
