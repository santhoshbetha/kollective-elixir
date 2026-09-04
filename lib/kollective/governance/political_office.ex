defmodule Kollective.Governance.PoliticalOffice do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "political_offices" do
    # "US", "IN", "BR"
    field :country_code, :string
    # "us_senator", "county_sheriff", "school_board"
    field :office_id, :string
    # "Federal", "Legislative", "Education"
    field :category, :string
    # "U.S. Senator"
    field :title, :string
    # "national_district", "county", "school_district"
    field :scope, :string
    # Long-form contextual description
    field :desc, :string

    # 🚀 "urban" | "rural" | nil
    field :area_type, :string, default: nil

    # 🌟 Merged Properties from the Civic Dataset
    # e.g., 2, 4, 6
    field :term_years, :integer
    # jsonb: { age: 30, residency: "..." }
    field :qualifications, :map, default: %{}
    # e.g., "Great entry-level position..."
    field :run_note, :string, default: nil

    # 🌟 Local Overrides Mapping (Ensures code logic stays country-agnostic)
    # e.g., "TX" or "Karnataka"
    field :state_restriction, :string, default: nil
    # e.g., "Travis County"
    field :district_restriction, :string, default: nil

    timestamps()
  end

  def changeset(political_office, attrs) do
    political_office
    |> cast(attrs, [
      :country_code,
      :office_id,
      :category,
      :title,
      :scope,
      :desc,
      :term_years,
      :qualifications,
      :run_note,
      :state_restriction,
      :district_restriction,
      :area_type
    ])
    |> validate_required([
      :country_code,
      :office_id,
      :category,
      :title,
      :scope,
      :desc
    ])
    # Guarantees strict type bounds
    |> validate_inclusion(:area_type, ["urban", "rural", nil])
    |> update_change(:country_code, &String.upcase/1)
    |> unique_constraint([:country_code, :office_id, :state_restriction, :district_restriction])
  end
end
