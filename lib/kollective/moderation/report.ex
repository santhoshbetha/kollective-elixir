defmodule Kollective.Moderation.Report do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "reports" do
    field :category, :string
    field :reason, :string
    field :details, :string
    field :preview_text, :string
    field :comment, :string
    field :status, :string, default: "open"
    field :target_type, :string, default: "Post"
    field :target_id, :binary_id

    belongs_to :reporter, Kollective.Accounts.User
    belongs_to :target_user, Kollective.Accounts.User
    belongs_to :post, Kollective.Posts.Post
    belongs_to :event, Kollective.Events.Event

    timestamps(type: :utc_datetime)
  end

  def changeset(report, attrs) do
    report
    |> cast(attrs, [
      :category,
      :reason,
      :details,
      :preview_text,
      :comment,
      :status,
      :target_type,
      :target_id,
      :reporter_id,
      :target_user_id,
      :post_id,
      :event_id
    ])
    |> validate_required([:reporter_id])
  end
end
