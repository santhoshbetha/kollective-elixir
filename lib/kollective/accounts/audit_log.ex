# lib/kollective/accounts/audit_log.ex
defmodule Kollective.Accounts.AuditLog do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "audit_logs" do
    field :action, :string
    field :target_type, :string
    field :target_id, :string
    field :metadata, :map, default: %{}

    belongs_to :actor, Kollective.Accounts.User
    belongs_to :organization, Kollective.Accounts.User

    timestamps(updated_at: false)
  end

  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [:action, :target_type, :target_id, :metadata, :actor_id, :organization_id])
    |> validate_required([:action, :target_type, :target_id, :organization_id])
  end
end
