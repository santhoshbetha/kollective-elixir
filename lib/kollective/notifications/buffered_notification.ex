defmodule Kollective.Notifications.BufferedNotification do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "buffered_notifications" do
    belongs_to :user, Kollective.Accounts.User, foreign_key: :user_id
    field :type, :string
    field :target_id, Ecto.ULID

    timestamps()
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:user_id, :type, :target_id])
    |> validate_required([:user_id, :type, :target_id])
  end
end
