# lib/kollective/campaigns/election_deadline.ex
defmodule Kollective.Campaigns.ElectionDeadline do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  @derive {JSON.Encoder,
           only: [
             :id,
             :office_level,
             :district_code,
             :sub_local_name,
             :application_deadline,
             :election_date,
             :state,
             :logged_by_id
           ]}
  schema "election_deadlines" do
    field :office_level, :string
    field :district_code, :string
    field :sub_local_name, :string
    field :application_deadline, :date
    field :election_date, :date
    field :state, :string

    belongs_to :logged_by, Kollective.Accounts.User, foreign_key: :logged_by_id

    timestamps()
  end

  @doc """
  Validates crowdsourced dates. Protects data arrays against chronological logic flaws.
  """
  def changeset(election_deadline, attrs) do
    election_deadline
    |> cast(attrs, [
      :office_level,
      :district_code,
      :sub_local_name,
      :application_deadline,
      :election_date,
      :state,
      :logged_by_id
    ])
    |> validate_required([
      :office_level,
      :district_code,
      :application_deadline,
      :election_date,
      :state,
      :logged_by_id
    ])
    |> validate_inclusion(:office_level, [
      "congress",
      "state_senate",
      "state_rep",
      "municipal",
      "county"
    ])
    |> validate_dates()
    |> unique_constraint(:unique_election_key,
      name: :election_deadlines_office_level_district_code_sub_local_name_index,
      message: "This election target parameters timeline is already logged."
    )
  end

  # 🛡️ Structural Data Security Guard: Ensures you can't apply to run AFTER an election date passes
  defp validate_dates(changeset) do
    deadline = get_field(changeset, :application_deadline)
    election = get_field(changeset, :election_date)

    if deadline && election && Date.compare(deadline, election) == :gt do
      add_error(
        changeset,
        :application_deadline,
        "Application cutoff deadline cannot follow the actual election date."
      )
    else
      changeset
    end
  end
end
