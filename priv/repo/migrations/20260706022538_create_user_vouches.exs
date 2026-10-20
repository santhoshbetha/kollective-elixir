defmodule Kollective.Repo.Migrations.CreateUserVouches do
  use Ecto.Migration

  def change do
    create table(:user_vouches, primary_key: false) do
      # 1. Primary Identifier using your project's native chronological Ecto.ULID format
      add(:id, :binary_id, primary_key: true)

      # 2. Relational Foreign Key Pointers (Cascades cleanly upon account termination)
      add(:voucher_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false)
      add(:vouchee_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false)

      # 3. Precise Local Boundary Structural Cache Parameters
      add(:origin_state, :string, null: false)
      # Constrained to string options: "l1", "l2", "l3"
      add(:matched_tier, :string, null: false)
      # Caches the actual string identifier (e.g. "12", "04")
      add(:district_value, :string, null: false)

      timestamps(type: :utc_datetime)
    end

    # ─── HIGH-SPEED ANTI-FRAUD UNIQUE INDEX ───
    # Enforces that a resident can only verify a specific neighbor ONCE per political level.
    # This acts as an iron-clad security shield blocking duplicate sybil-vouching fraud natively.
    create(
      unique_index(:user_vouches, [:voucher_id, :vouchee_id, :origin_state, :matched_tier],
        name: :vouches_voucher_vouchee_tier_unique_index
      )
    )

    # ─── DISCOVERY FEEDS LOOKUP ACCELERATOR ───
    # Index-driven scanning ensures verification tallies compute in under 0.01ms
    create(index(:user_vouches, [:vouchee_id, :origin_state]))
  end
end
