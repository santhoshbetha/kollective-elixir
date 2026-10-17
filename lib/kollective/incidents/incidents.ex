defmodule Kollective.Incidents do
  @moduledoc """
  Coordinates lifecycle events across Postgres (Source of Truth) and Mnesia (Mesh Workspace).
  """
  alias Kollective.Repo
  # Your Ecto Schema
  alias Kollective.Moderation.ScholarIncident

  # Write to both locations
  def create_incident(attrs) do
    Repo.transaction(fn ->
      # 1. Save permanently to Postgres
      {:ok, incident} = %ScholarIncident{} |> ScholarIncident.changeset(attrs) |> Repo.insert()

      # 2. Write to the replicated Mnesia Cluster
      :mnesia.activity(:transaction, fn ->
        :mnesia.write(
          {:scholar_incidents, incident.id, incident.title, incident.status, incident.operator_id}
        )
      end)

      incident
    end)
  end

  # When an item is resolved, update Postgres and evict from high-speed memory
  def resolve_incident(incident_id) do
    Repo.transaction(fn ->
      # 1. Update Postgres status
      incident = Repo.get!(ScholarIncident, incident_id)

      {:ok, updated} =
        incident |> ScholarIncident.changeset(%{status: "resolved"}) |> Repo.update()

      # 2. Delete from Mnesia to free up RAM space across the cluster
      :mnesia.activity(:transaction, fn ->
        :mnesia.delete({:scholar_incidents, incident_id})
      end)

      updated
    end)
  end
end
