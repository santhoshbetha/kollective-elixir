# The schema handles the data mapping and ensures all required fields for an audit trail are present.
defmodule Kollective.Events.ModerationLog do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "moderation_logs" do
    field :previous_status, :string
    field :new_status, :string
    field :reason, :string
    field :raw_ai_response, :map

    belongs_to :comment, Kollective.Events.Comment
    belongs_to :admin, Kollective.Accounts.User

    # Store the admin's explanation
    field :notes, :string
    # Optional: Categorize the reason (e.g., "spam", "harassment", "accidental_flag")
    field :category, :string

    timestamps()
  end

  @doc "Cast and validate the log entry"
  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :comment_id,
      :admin_id,
      :previous_status,
      :new_status,
      :reason,
      :raw_ai_response
    ])
    |> validate_required([:comment_id, :admin_id, :new_status, :reason])
  end
end
