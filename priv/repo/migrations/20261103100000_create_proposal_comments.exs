defmodule Kollective.Repo.Migrations.CreateProposalComments do
  use Ecto.Migration

  def change do
    create table(:proposal_comments, primary_key: false) do
      # Enforces unified Ecto.ULID binary format globally
      add :id, :binary_id, primary_key: true

      # ─── CORE ATTRIBUTES ───
      add :content, :text
      add :image_url, :string
      add :moderation_status, :string, default: "pending", null: false

      # ─── CORE RELATIONSHIPS ───
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      # ─── THE THREAD SELF-JOIN ───
      add :parent_id, references(:proposal_comments, type: :binary_id, on_delete: :delete_all)

      timestamps()
    end

    # ─── PERFORMANCE INDICES ───
    # Speeds up loading the primary discussion timeline inside a single proposal node
    create index(:proposal_comments, [:business_id, :inserted_at])

    # Optimizes deep threaded nested reply lookups
    create index(:proposal_comments, [:parent_id])

    # Faster user profile comment history tracking lookups
    create index(:proposal_comments, [:user_id])
  end
end
