# "User Reporting" system so regular users can flag posts that the automated keyword filter missed

defmodule Kollective.Moderation.Report do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "reports" do
    field :reason, :string
    field :details, :string
    field :status, Ecto.Enum, values: [:pending, :resolved, :dismissed], default: :pending

    belongs_to :reporter, Kollective.Accounts.User
    belongs_to :post, Kollective.Posts.Post
    belongs_to :event, Kollective.Events.Event

    timestamps()
  end

  def changeset(report, attrs) do
    report
    |> cast(attrs, [:reason, :details, :reporter_id, :post_id, :event_id, :status])
    |> validate_required([:reason, :reporter_id])
  end
end
