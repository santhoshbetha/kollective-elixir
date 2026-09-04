defmodule Kollective.Governance.Importer do
  @moduledoc """
  Handles reading, parsing, and upserting global country office structures
  from JSON schema files into the unified Postgres registry tables.
  """
  alias Kollective.Repo
  alias Kollective.Governance.PoliticalOffice

  @doc """
  Processes a single country configuration JSON file path or a raw decoded map structure.
  """
  def import_country_json(file_path) when is_binary(file_path) do
    if File.exists?(file_path) do
      file_path
      |> File.read!()
      |> Jason.decode!()
      |> process_payload()
    else
      {:error, :file_not_found}
    end
  end

  def import_country_json(raw_map) when is_map(raw_map) do
    process_payload(raw_map)
  end

  # --- Private Ingestion Processing Engine ---
  defp process_payload(%{"country_code" => country_code, "offices" => offices}) do
    cc = String.upcase(country_code)

    # Wrap the loops inside an atomic database transaction.
    # If one row fails validation, the entire batch rolls back to prevent corrupt states.
    Repo.transaction(fn ->
      Enum.each(offices, fn office_data ->
        params = %{
          "country_code" => cc,
          "office_id" => office_data["id"],
          "category" => office_data["category"],
          "title" => office_data["title"],
          "scope" => office_data["scope"],
          "desc" => office_data["desc"],
          # 🌟 New parameters mapping from our advanced merged layout schemas:
          "term_years" => Map.get(office_data, "term_years"),
          "qualifications" => Map.get(office_data, "qualifications", %{}),
          "run_note" => Map.get(office_data, "run_note"),
          "state_restriction" => Map.get(office_data, "state_restriction"),
          "district_restriction" => Map.get(office_data, "district_restriction"),
          "area_type" => Map.get(office_data, "area_type")
        }

        # Safe Atomic Upsert Pattern
        %PoliticalOffice{}
        |> PoliticalOffice.changeset(params)
        |> Repo.insert!(
          on_conflict: {
            :replace,
            [
              :category,
              :title,
              :scope,
              :desc,
              :term_years,
              :qualifications,
              :run_note,
              :district_restriction,
              :area_type
            ]
          },
          conflict_target: [:country_code, :office_id, :state_restriction]
        )
      end)
    end)

    {:ok, :success}
  end

  defp process_payload(_invalid_structure) do
    {:error, :invalid_json_schema_structure}
  end
end
