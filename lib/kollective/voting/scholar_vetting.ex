defmodule Kollective.Voting.ScholarVetting do
  @moduledoc """
  Handles automated and peer-driven vetting logic for Academic Scholars and Professors.
  """
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Accounts.User

  @doc """
  Attempts to auto-verify a scholar if they provide a valid, authenticated ORCID iD record.
  """
  def verify_via_orcid(user_id, orcid_id) do
    # In a production app, you would make an HTTP request to the Public ORCID API:
    # https://orcid.org{orcid_id}/record
    case fetch_orcid_record(orcid_id) do
      {:ok, %{verified: true}} ->
        update_user_to_scholar(user_id, orcid_id)

      {:error, _reason} ->
        {:error, :invalid_orcid_record}
    end
  end

  @doc """
  Fallback: If automated ORCID checks fail or aren't available, routes to a blind peer jury
  consisting strictly of 5 existing, verified Academic Scholars (Emerald Green holders).
  """
  def route_to_academic_jury(user_id, _academic_credentials_text) do
    # Get 5 random existing scholars to judge the academic validity of the applicant
    query =
      from(u in User,
        where: u.badge_type == "Scholar",
        where: u.id != ^user_id,
        order_by: fragment("RANDOM()"),
        limit: 5,
        select: u.id
      )

    case Repo.all(query) do
      juror_ids when length(juror_ids) == 5 ->
        # Reuse your existing application/jury multi-transaction framework here,
        # restricting the jury pool strictly to these 5 academic peers.
        {:ok, :routed_to_academic_peer_review}

      _ ->
        {:error, "Insufficient verified academic peers online to review credentials."}
    end
  end

  defp fetch_orcid_record(orcid_id) do
    # Regex validation validation check for standard ORCID string formats
    if String.match?(orcid_id, ~r/^\d{4}-\d{4}-\d{4}-\d{3}[0-9X]$/) do
      # Mocking successful open-access API parsing response
      {:ok, %{verified: true}}
    else
      {:error, :malformed_id}
    end
  end

  defp update_user_to_scholar(user_id, orcid_id) do
    Repo.get(User, user_id)
    |> User.changeset(%{
      badge_type: "Scholar",
      metadata: %{orcid_id: orcid_id, verified_at: DateTime.utc_now()}
    })
    |> Repo.update()
  end
end
