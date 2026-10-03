defmodule Kollective.Repo.Migrations.CreateReports do
  use Ecto.Migration

  def change do
    create table(:reports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :category, :string
      add :reason, :string
      add :details, :string
      add :preview_text, :string
      add :comment, :string
      add :status, :string, default: "open", null: false
      add :target_type, :string, default: "Post"
      add :target_id, :binary_id

      add :reporter_id, references(:users, on_delete: :nilify_all, type: :binary_id)
      add :target_user_id, references(:users, on_delete: :nilify_all, type: :binary_id)
      add :post_id, references(:posts, on_delete: :nilify_all, type: :binary_id)
      add :event_id, references(:events, on_delete: :nilify_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:reports, [:status])
    create index(:reports, [:reporter_id])
    create index(:reports, [:target_user_id])
    create index(:reports, [:post_id])
    create index(:reports, [:event_id])
  end
end
