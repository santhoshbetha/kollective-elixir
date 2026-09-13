defmodule KollectiveWeb.AuditLogJSONTest do
  use ExUnit.Case, async: true

  alias KollectiveWeb.AuditLogJSON
  alias Kollective.Accounts.{AuditLog, User}

  describe "AuditLogJSON serialization" do
    test "index/1 serializes list of audit logs" do
      now = ~U[2026-09-12 12:00:00Z]

      log = %AuditLog{
        id: "01J7K8M9N0P1Q2R3S4T5U6V7W8",
        action: "member_removed",
        target_type: "user",
        target_id: "01J7K8M9N0P1Q2R3S4T5U6V7W9",
        metadata: %{"reason" => "left team"},
        inserted_at: now,
        actor: %User{
          id: "01J7K8M9N0P1Q2R3S4T5U6V7AA",
          display_name: "Admin Alice",
          username: "alice_admin"
        }
      }

      res = AuditLogJSON.index(%{audit_logs: [log]})
      assert is_list(res.data)
      assert length(res.data) == 1

      first = hd(res.data)
      assert first.id == "01J7K8M9N0P1Q2R3S4T5U6V7W8"
      assert first.action == "member_removed"
      assert first.target_type == "user"
      assert first.actor.username == "alice_admin"
      assert first.inserted_at == "2026-09-12T12:00:00Z"

      # Also test bare list overload
      res_bare = AuditLogJSON.index([log])
      assert res_bare == res
    end

    test "show/1 and data/1 render audit log entry" do
      now = ~U[2026-09-12 12:00:00Z]

      log = %AuditLog{
        id: "01J7K8M9N0P1Q2R3S4T5U6V7W8",
        action: "role_updated",
        target_type: "membership",
        target_id: "01J7K8M9N0P1Q2R3S4T5U6V7W9",
        metadata: %{"new_role" => "admin"},
        inserted_at: now,
        actor: nil
      }

      data = AuditLogJSON.data(log)
      assert data.actor == %{username: "System", name: "System Event"}

      show_res = AuditLogJSON.show(%{audit_log: log})
      assert show_res.data == data
    end

    test "handles unloaded actor safely" do
      log = %AuditLog{
        id: "01J7K8M9N0P1Q2R3S4T5U6V7W8",
        action: "invite_created",
        target_type: "invite",
        target_id: "01J7K8M9N0P1Q2R3S4T5U6V7W9",
        metadata: %{},
        inserted_at: ~U[2026-09-12 12:00:00Z],
        actor: %Ecto.Association.NotLoaded{}
      }

      data = AuditLogJSON.data(log)
      assert data.actor == nil
    end
  end
end
