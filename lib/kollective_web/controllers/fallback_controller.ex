defmodule KollectiveWeb.FallbackController do
  use KollectiveWeb, :controller

  @moduledoc """
  Translates system and database execution failures into semantic,
  well-formed JSON API responses matching front-end contract specifications.
  """

  # 🚨 Catch-All: Handle general atomic database changeset error parsing
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: KollectiveWeb.ChangesetJSON)
    |> render("error.json", changeset: changeset)
  end

  # 🔒 Catch-All: Handle Explicit Security & Authorization Failures
  def call(conn, {:error, :not_authorized}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      status: "error",
      code: "UNAUTHORIZED_ACTION",
      message:
        "You do not possess the required validation credentials or clearance tiers for this operation."
    })
  end

  # ⏰ Catch-All: Handle P2P Token Expiration Timeouts (410 Gone)
  def call(conn, {:error, :token_expired}) do
    conn
    |> put_status(:gone)
    |> json(%{
      status: "error",
      code: "APPLICATION_EXPIRED",
      message:
        "This verification session has closed. The 60-second single-use token time has passed."
    })
  end

  # 🧩 Catch-All: Handle Invalid Token Signatures (400 Bad Request)
  def call(conn, {:error, :token_invalid}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      status: "error",
      code: "INVALID_TOKEN_SIGNATURE",
      message: "Malformed token signature structural data. Scanner verification failed."
    })
  end

  # 🔄 Catch-All: Handle Already Voted / Early Supermajority Resolutions
  def call(conn, {:error, :already_voted}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      status: "error",
      code: "DUPLICATE_BALLOT",
      message:
        "You have already cast a ballot for this review session. Blind votes cannot be modified."
    })
  end

  # 📜 Catch-All: Handle Scholar ORCID Registry Lookup Failures
  def call(conn, {:error, :invalid_orcid_record}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      status: "error",
      code: "ORCID_RECORD_MISSING",
      message:
        "The provided ORCID tracking number holds no active public record on the open registry database."
    })
  end

  # 🧪 Catch-All: Handle Fallback Generic String Error Reasons
  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      status: "error",
      code: "PIPELINE_TRANSACTION_REJECTED",
      message: reason
    })
  end
end
