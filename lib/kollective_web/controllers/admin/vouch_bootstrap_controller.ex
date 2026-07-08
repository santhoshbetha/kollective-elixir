# lib/kollective_web/controllers/admin/vouch_bootstrap_controller.ex
defmodule KollectiveWeb.Admin.VouchBootstrapController do
  use KollectiveWeb, :controller

  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Accounts.User

  @doc """
  POST /api/v1/admin/civic/bootstrap-seed
  Body Input Specs: %{"user_id" => "01J0A..."}
  Bootstraps an initial trust anchor based on their actual multi-district location data [INDEX].
  """
  def bootstrap_seed(conn, %{"user_id" => target_user_id}) do
    _admin_user_id = conn.assigns.current_user.id

    Repo.transaction(fn ->
      user = Repo.get!(User, target_user_id)

      # Ensure the user has valid location profiles configured before seeding
      if is_nil(user.origin_state) || is_nil(user.district_l1) do
        Repo.rollback("User profiles must contain verified district metrics before initialization.")
      end

      # 1. Look-ahead check: Enforce the cap of 3 seed anchors across all overlapping boundaries
      overlapping_seeds =
        Repo.one(
          from u in User,
            where: u.origin_state == ^user.origin_state and u.account_tier == 1,
            where: u.district_l1 == ^user.district_l1 or
                   u.district_l2 == ^user.district_l2 or
                   u.district_l3 == ^user.district_l3,
            select: count(u.id)
        )

      if overlapping_seeds >= 3 do
        Repo.rollback("This overlapping boundary sector has already established 3 seed nodes. Use P2P network instead.")
      end

      # 2. Atomically update the user account standing parameters
      updated_metadata = Map.put(user.metadata || %{}, "bootstrapped_via_video_at", DateTime.utc_now())

      {:ok, updated_user} =
        user
        |> User.changeset(%{
          account_tier: 1,
          metadata: updated_metadata
        })
        |> Repo.update()

      updated_user
    end)
    |> case do
      {:ok, user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Seed Node status assigned. User can now organically verify overlapping neighbors.",
          data: %{
            user_id: to_string(user.id),
            account_tier: user.account_tier,
            districts: %{l1: user.district_l1, l2: user.district_l2, l3: user.district_l3}
          }
        })

      {:error, reason} ->
        conn |> put_status(:conflict) |> json(%{status: "error", error: reason})
    end
  end
end
