defmodule Kollective.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:conversations, primary_key: false) do
      # Match your system's ULID type
      add :id, :binary_id, primary_key: true
      # Optional group chat title
      add :title, :string
      add :is_group, :boolean, default: false, null: false

      timestamps()
    end
  end
end
