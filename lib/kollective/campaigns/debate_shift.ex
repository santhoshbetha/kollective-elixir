# lib/kollective/campaigns/debate_shift.ex
defmodule Kollective.Campaigns.DebateShift do
  use Kollective.Schemas.Schema

  @derive {Jason.Encoder, only: [:id, :role_name, :max_volunteers, :debate_event_id, :volunteers]}
  @derive {JSON.Encoder, only: [:id, :role_name, :max_volunteers, :debate_event_id, :volunteers]}
  schema "debate_shifts" do
    field :role_name, :string
    field :max_volunteers, :integer

    belongs_to :debate_event, Kollective.Campaigns.DebateEvent

    # Preloads claimed user fields flatly matching client structures
    many_to_many :volunteers, Kollective.Accounts.User,
      join_through: "debate_shifts_volunteers",
      on_replace: :delete

    timestamps()
  end
end
