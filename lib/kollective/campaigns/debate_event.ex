# lib/kollective/campaigns/debate_event.ex
defmodule Kollective.Campaigns.DebateEvent do
  use Kollective.Schemas.Schema

  @derive {JSON.Encoder,
           only: [
             :id,
             :title,
             :date_time,
             :venue_address,
             :office_level,
             :district_code,
             :broadcast_node_url,
             :shifts
           ]}
  schema "debate_events" do
    field :title, :string
    field :date_time, :utc_datetime
    field :venue_address, :string
    field :office_level, :string
    field :district_code, :string
    field :broadcast_node_url, :string

    has_many :shifts, Kollective.Campaigns.DebateShift

    timestamps()
  end
end
