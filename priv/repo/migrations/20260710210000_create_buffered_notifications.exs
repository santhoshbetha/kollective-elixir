defmodule Kollective.Repo.Migrations.CreateBufferedNotifications do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:buffered_notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :type, :string, null: false

      add :target_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps()
    end

    create_if_not_exists index(:buffered_notifications, [:user_id, :type, :target_id])
  end
end
