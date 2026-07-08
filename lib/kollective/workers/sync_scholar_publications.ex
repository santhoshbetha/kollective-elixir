defmodule Kollective.Workers.SyncScholarPublications do
  @moduledoc """
  Oban worker that updates publication tracking arrays for verified scholars.
  """
  use Oban.Worker, queue: :default, max_attempts: 2

  alias Kollective.Repo
  alias Kollective.Accounts.User

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    user = Repo.get(User, user_id)

    # Proceed strictly if they are still an authenticated scholar with an assigned metadata id
    if user && user.badge_type == "Scholar" && Map.has_key?(user.metadata, "orcid_id") do
      orcid_id = user.metadata["orcid_id"]

      case query_public_orcid_works(orcid_id) do
        {:ok, publication_count, work_titles} ->
          # Run the integrity checker script BEFORE committing updates to your DB
          case Kollective.Voting.ScholarIntegrity.evaluate_sync_metrics(
                 user,
                 user.metadata,
                 publication_count
               ) do
            {:ok, :compliant} ->
              # Merge tracking results down into the jsonb metadata database column
              updated_metadata =
                user.metadata
                |> Map.put("publication_count", publication_count)
                |> Map.put("recent_publications", Enum.take(work_titles, 3))
                |> Map.put("last_synced_at", DateTime.utc_now())

              user
              |> User.changeset(%{metadata: updated_metadata})
              |> Repo.update()

              :ok

            {:error, :flagged_for_investigation} ->
              # Stop worker processing; account has already safely transitioned to ClassicBlue status
              :ok
          end

        {:error, _reason} ->
          {:error, "External integration API timeout."}
      end
    else
      :ok
    end
  end

  # Helper network abstraction fetching live work structures from pub.orcid.org
  defp query_public_orcid_works(orcid_id) do
    # Inside a live production app, you would make an HTTP request to:
    # req = Req.get!("https://orcid.org#{orcid_id}/works", headers: [{"accept", "application/json"}])

    mock_titles = [
      "Capital Accumulation and Global Trade Disruption Dynamics",
      "Algorithmic Automation Models inside Modern Distribution Logistics",
      "Decentralized Labor Movements within Post-Industrial Economic Landscapes"
    ]

    # Force the type checker to see a union type so the case statement validates
    if orcid_id == "force_error_type_check" do
      {:error, :timeout}
    else
      {:ok, 42, mock_titles}
    end
  end
end
