defmodule Kollective.Moderation.Incident do
  use Ecto.Schema
  import Ecto.Changeset

  # Configure your primary schema to utilize your system's unified binary ULID/UUID keys
  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID

  schema "scholar_incidents" do
    # "pending" | "resolved_restored" | "resolved_banned"
    field(:status, :string, default: "pending")
    # ISO-3166 text token, e.g., "US", "IN"
    field(:country_code, :string)
    # Node name identifier string, e.g., "node_mumbai@127.0.0.1"
    field(:origin_node_atom, :string)
    # Handled for fast admin search queries
    field(:target_username, :string)
    # Context payload regarding infraction
    field(:description, :string)
    # e.g., "ORCID_SYNC_MISMATCH", "POST_ABUSE_REPORT"
    field(:flag_type, :string)

    # 🔒 WORK-STEALING LEASE TRACKERS
    field(:leased_by_id, Ecto.ULID)
    field(:leased_until, :utc_datetime)

    # Associations
    belongs_to(:reporter, Kollective.Accounts.User)
    belongs_to(:post, Kollective.Posts.Post, type: Ecto.ULID)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Sovereign model changeset builder.
  """
  def changeset(incident, attrs) do
    incident
    |> cast(attrs, [
      :status,
      :country_code,
      :origin_node_atom,
      :target_username,
      :description,
      :flag_type,
      :leased_by_id,
      :leased_until,
      :reporter_id,
      :post_id
    ])
    |> validate_required([:status, :country_code, :origin_node_atom, :description, :reporter_id])
    |> validate_inclusion(:status, ["pending", "resolved_restored", "resolved_banned"])
  end
end
