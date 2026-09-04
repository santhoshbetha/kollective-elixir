defmodule Kollective.Repo.Migrations.CreateEventComments do
  use Ecto.Migration

  def change do
    create table(:event_comments, primary_key: false) do
      # Enforces unified Ecto.ULID binary format globally
      add :id, :binary_id, primary_key: true

      # ─── CORE ATTRIBUTES ───
      # Using :text to comfortably support up to 5000 chars
      add :content, :text
      add :image_url, :string
      add :moderation_status, :string, default: "pending", null: false

      # ─── CORE RELATIONSHIPS ───
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :event_id, references(:events, type: :binary_id, on_delete: :delete_all), null: false

      # ─── THE THREAD SELF-JOIN ───
      add :parent_id, references(:event_comments, type: :binary_id, on_delete: :delete_all)

      timestamps()
    end

    # ─── PERFORMANCE INDICES ───
    # Speeds up loading the primary comment timeline inside a specific event node
    create index(:event_comments, [:event_id, :inserted_at])

    # Optimizes deep threaded nested reply lookups
    create index(:event_comments, [:parent_id])

    # Faster user profile comment history tracking lookups
    create index(:event_comments, [:user_id])
  end
end
