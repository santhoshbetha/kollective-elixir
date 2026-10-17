defmodule KollectiveWeb.Admin.ModerationAppealController do
  use KollectiveWeb, :controller
  require Logger

  alias Kollective.Repo
  alias Kollective.Moderation.ModerationAppeal

  @doc """
  POST /api/v1/moderation/appeals
  Submits a citizen appeal, dual-writing it into Ecto SQL and the replicated Mnesia matrix.
  """
  def create(conn, %{"appeal" => appeal_params}) do
    user = conn.assigns[:current_user] || conn.assigns[:user]

    user_country = Map.get(user, :country_code) || Map.get(user, :country) || "GLOBAL"

    enriched_params =
      appeal_params
      |> Map.put("user_id", user.id)
      |> Map.put("country_code", String.upcase(to_string(user_country)))
      |> Map.put("origin_node_atom", Atom.to_string(Node.self()))
      |> Map.put("status", "pending")

    changeset = ModerationAppeal.changeset(%ModerationAppeal{}, enriched_params)

    case Repo.insert(changeset) do
      {:ok, appeal} ->
        # 🚀 REPLICATE INTO DISTRIBUTED MNESIA INSTANTLY
        # Injects the appeal token parameter row to all nodes across your libcluster mesh
        now_iso = DateTime.utc_now() |> DateTime.to_iso8601()

        mnesia_record = {
          :distributed_appeals,
          to_string(appeal.id),
          to_string(appeal.incident_id),
          to_string(user.id),
          appeal.reason,
          "pending",
          appeal.country_code,
          now_iso
        }

        _ = :mnesia.transaction(fn -> :mnesia.write(mnesia_record) end)

        # Broadcast real-time notifications to any online country or global mods channels
        # region_topic = "mods_zone_#{appeal.country_code}"

        KollectiveWeb.Endpoint.broadcast("admin_notifications:global", "new_appeal", %{
          id: appeal.id
        })

        json(conn, %{
          status: "success",
          message: "Your appeal has been safely broadcast to the governance mesh."
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "Failed to map operational appeal properties.",
          details: inspect(changeset.errors)
        })
    end
  end
end
