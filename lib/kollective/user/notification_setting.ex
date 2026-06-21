defmodule Kollective.User.NotificationSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @derive Jason.Encoder
  @primary_key false

  embedded_schema do
    field(:block_from_strangers, :boolean, default: false) #san this for "notification_setting_block_from_strangers": "Block notifications from users who you do not follow",
    field(:hide_notification_contents, :boolean, default: false)
  end

  def changeset(schema, params) do
    schema
    |> cast(prepare_attrs(params), [
      :block_from_strangers,
      :hide_notification_contents
    ])
  end

  defp prepare_attrs(params) do
    Enum.reduce(params, %{}, fn
      {k, v}, acc when is_binary(v) ->
        Map.put(acc, k, String.downcase(v))

      {k, v}, acc ->
        Map.put(acc, k, v)
    end)
  end
end
