defmodule KollectiveWeb.Admin.FeatureFlagController do
  use KollectiveWeb, :controller

  alias Kollective.Admin.FeatureFlags

  # 🛡️ PRIVILEGE DEFENSE GUARD: Restricts lookups exclusively to authorized operator staff accounts
  plug :verify_staff_clearance

  @doc """
  GET /api/v1/admin/config/feature_flags
  Fetches all active feature flags to cleanly hydrate dashboard panels on mount.
  """
  def index(conn, _params) do
    flags = FeatureFlags.list_flags()
    render(conn, :index, feature_flags: flags)
  end

  @doc """
  POST /api/v1/admin/config/feature_flags/toggle
  Validates parameter maps and triggers the microsecond ETS cache refresh transaction.
  """
  def toggle(conn, %{"key" => key, "enabled" => enabled})
      when is_binary(key) and is_boolean(enabled) do
    case FeatureFlags.toggle_flag(key, enabled) do
      {:ok, updated_flag} ->
        # Real-time message dispatched inside toggle_flag automatically via PubSub
        render(conn, :show, feature_flag: updated_flag)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(html: KollectiveWeb.ChangesetHTML, json: KollectiveWeb.ChangesetJSON)
        |> render("error.json", changeset: changeset)
    end
  end

  def toggle(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameters: 'key' (string) and 'enabled' (boolean)."})
  end

  # --- Private Security Plug Interceptors ---

  defp verify_staff_clearance(conn, _opts) do
    user = conn.assigns[:current_user] || conn.assigns[:user]

    if user &&
         (user.is_admin || user.is_moderator ||
            Map.get(user, :badge_type) in ["admin", "root", "moderator", "staff"]) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Access denied: Unauthorized platform clearance tier."})
      |> halt()
    end
  end
end
