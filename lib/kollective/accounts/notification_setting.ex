defmodule Kollective.Accounts.NotificationSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @derive Jason.Encoder
  @primary_key false

  embedded_schema do
    field(:block_from_strangers, :boolean, default: false)
    field(:hide_notification_contents, :boolean, default: false)
  end

  def changeset(schema, params) do
    schema
    # Note: cast/3 is fine here, but usually your boolean params
    # from a form will be "true"/"false" strings or atoms.
    |> cast(params, [:block_from_strangers, :hide_notification_contents])
  end
end
