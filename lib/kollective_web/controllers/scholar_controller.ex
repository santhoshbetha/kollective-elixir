# lib/kollective_web/controllers/scholar_controller.ex
defmodule KollectiveWeb.ScholarController do
  use KollectiveWeb, :controller

  alias Kollective.Voting.ScholarVetting
  alias KollectiveWeb.ChangesetJSON

  @doc """
  POST /api/v1/voting/scholar-verify
  Body parameters: %{"orcid_id" => "0000-0002-1825-0001"}
  Validates research credentials via global open-access registries instantly .
  """
  def verify_orcid(conn, %{"orcid_id" => orcid_id}) do
    # Fetch user straight out of server RAM safely
    current_user = conn.assigns.current_user

    # Validate correct format pattern before spending resources executing network lookups
    if String.match?(orcid_id, ~r/^\d{4}-\d{4}-\d{4}-\d{3}[0-9X]$/) do
      case ScholarVetting.verify_via_orcid(current_user.id, orcid_id) do
        {:ok, updated_user} ->
          conn
          |> put_status(:ok)
          |> json(%{
            status: "success",
            message: "Academic validation verified successfully via global ORCID register.",
            data: %{
              id: to_string(updated_user.id),
              # Ensures user's account permissions immediately promote to scholar status
              type: to_string(updated_user.type),
              badge_type: updated_user.badge_type || "scholar"
            }
          })

        {:error, :invalid_orcid_record} ->
          conn
          |> put_status(:bad_request)
          |> json(%{
            status: "error",
            error:
              "The provided ORCID tracking number holds no active record on the registry database."
          })

        {:error, %Ecto.Changeset{} = changeset} ->
          # FIX: Catches database constraint errors (e.g. duplicate ORCID usages) warning-free
          conn
          |> put_status(:unprocessable_entity)
          |> json(ChangesetJSON.error(%{changeset: changeset}))

        {:error, reason} ->
          # Generic fallback wrapper prevents unhandled CaseClauseError crashes
          conn
          |> put_status(:bad_request)
          |> json(%{status: "error", error: "verification_failed", message: to_string(reason)})
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{
        status: "error",
        error: "malformed_format",
        message: "Invalid ORCID structure format. Must follow layout: XXXX-XXXX-XXXX-XXXX"
      })
    end
  end
end
