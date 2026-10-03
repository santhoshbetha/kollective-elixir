defmodule Kollective.Admins.FeatureFlag do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:key, :string, []}
  schema "feature_flags" do
    # e.g., "registration_open", "voice_broadcast_limits", "enhanced_notifications"
    # on or off
    field(:enabled, :boolean, default: false)
    # description
    field(:description, :string)
    # metadata
    field(:metadata, :map)

    # inserted_at, updated_at
    timestamps(type: :utc_datetime)
  end

  def changeset(feature_flag, attrs) do
    feature_flag
    |> cast(attrs, [:key, :enabled, :description, :metadata])
    |> validate_required([:key, :enabled])
    |> validate_inclusion(:key, [
      # Controls account sign-up locks
      "registration_open",
      # Emergency megaphone broadcast toggles
      "voice_broadcast_active",
      # Pauses heavy background tasks during traffic spikes
      "media_transcoding",
      # Cyber-attack mitigation lock down switch
      "public_feeds_enabled"
    ])
  end
end
