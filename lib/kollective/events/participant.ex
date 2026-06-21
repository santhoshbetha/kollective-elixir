defmodule Kollective.Events.Participant do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "event_participants" do
    belongs_to :event, Kollective.Events.Event
    belongs_to :user, Kollective.Accounts.User
    #field :status, :string, default: "accepted"

    # Statuses: "going", "maybe", "no", "pending", "waitlisted" , "accepted", "rejected"
    field :status, :string, default: "going"

    timestamps(type: :utc_datetime)
  end

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:event_id, :user_id, :status])
    |> validate_required([:event_id, :user_id, :status])
    |> unique_constraint([:event_id, :user_id])
  end
end
