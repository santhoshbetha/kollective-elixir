# lib/kollective_web/controllers/vouch_controller.ex
defmodule KollectiveWeb.VouchController do
  use KollectiveWeb, :controller

  alias Kollective.Civic.VouchCache
  alias Kollective.Civic.VerificationService

  @doc """
  POST /api/v1/vouch/generate-token
  Generates a short-lived token pointer for peer QR code scanning.
  """
  def request_token(conn, _params) do
    current_user_id = conn.assigns.current_user.id
    token_string = VouchCache.generate_token(current_user_id)

    conn
    |> put_status(:ok)
    |> json(%{status: "success", secure_token: token_string})
  end

  @doc """
  POST /api/v1/vouch/verify-peer
  Consumes the token payload from a QR scan and runs the peer-to-peer verification check.
  """
  def execute_peer_vouch(conn, %{"secure_token" => scan_payload}) do
    voucher_id = conn.assigns.current_user.id

    case VouchCache.consume_token(scan_payload) do
      {:ok, vouchee_id} ->
        # 2. Forward execution variables directly to your atomic database transaction pipeline
        case VerificationService.process_peer_vouch(voucher_id, vouchee_id) do
          {:ok, current_vouches} ->
            conn
            |> put_status(:ok)
            |> json(%{status: "success", current_vouches: current_vouches})

          {:error, _failed_step, db_rollback_reason, _changes} ->
            # FIX: Catch all standard Ecto Multi three-part rollback tuples cleanly
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{status: "error", error: "database_rollback", message: to_string(db_rollback_reason)})

          {:error, db_rollback_reason} ->
            # Secondary catch-all fallback guard ensures absolute safety against crashes
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{status: "error", error: "transaction_failed", message: to_string(db_rollback_reason)})
        end

      {:error, :token_expired} ->
        conn
        |> put_status(:gone)
        |> json(%{status: "error", error: "token_expired", message: "Validation session has timed out. Please refresh QR code."})

      {:error, :token_invalid} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", error: "token_invalid", message: "Invalid or already consumed token signature."})
    end
  end
end
