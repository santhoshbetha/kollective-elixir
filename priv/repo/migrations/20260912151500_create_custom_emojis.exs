defmodule Kollective.Repo.Migrations.CreateCustomEmojis do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:custom_emojis) do
      add :shortcode, :string, null: false
      add :url, :string, null: false
      add :static_url, :string
      add :category, :string
      add :visible_in_picker, :boolean, default: true

      timestamps()
    end

    create_if_not_exists unique_index(:custom_emojis, [:shortcode])
    create_if_not_exists index(:custom_emojis, [:category])
  end
end
