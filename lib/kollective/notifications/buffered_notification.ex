defmodule Kollective.Notifications.BufferedNotification do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "buffered_notifications" do
    belongs_to :user, Kollective.Accounts.User
    field :type, :string
    belongs_to :target, Kollective.Accounts.User

    timestamps()
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:user_id, :type, :target_id])
    |> validate_required([:user_id, :type, :target_id])
  end
end
