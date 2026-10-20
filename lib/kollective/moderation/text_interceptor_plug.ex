defmodule Kollective.Moderation.TextInterceptorPlug do
  require Logger

  @doc """
  🕵️‍♂️ PROACTIVE IN-MEMORY INGRESS SCANNER
  Evaluates plain text blobs across node channels. If an infraction threshold matches,
  it generates an automated incident token into the Mnesia work-stealing queue instantly.
  """
  def scan_and_intercept_content(text_payload, sender_user, conversation_id) do
    # Simple direct array token tracking. For production systems, read this dictionary from Mnesia RAM
    banned_keywords = ["malware_payload_attack", "syndicate_leak_bypass", "rogue_override_salt"]

    normalized_text = String.downcase(text_payload)

    # Check if any banned keyword is present in the text payload
    has_violation? = Enum.any?(banned_keywords, &String.contains?(normalized_text, &1))

    if has_violation? do
      Logger.warning(
        "🚨 [SECURITY INTERCEPT]: Proactive filter tripped by user ##{sender_user.id} in chat ##{conversation_id}"
      )

      # 🚀 INJECT AUTOMATED COMPLIANCE INCIDENT TICKET STRAIGHT INTO MNESIA
      # This makes it instantly visible to regional moderators without blocking database pipeline writes.
      incident_uuid = Ecto.UUID.generate()
      now_iso = DateTime.utc_now() |> DateTime.to_iso8601()

      automated_mnesia_incident = {
        :scholar_incidents,
        incident_uuid,
        "pending",
        String.upcase(sender_user.country_code || "GLOBAL"),
        sender_user.username,
        "Automated system intercept: Proactive keyword trigger caught violation parameter patterns on text streams content strings.",
        now_iso,
        # No active leased operator session assigned
        nil,
        nil
      }

      _ = :mnesia.transaction(fn -> :mnesia.write(automated_mnesia_incident) end)

      # Trigger live streaming alerts onto active moderator dashboard panels grids
      KollectiveWeb.Endpoint.broadcast("admin_notifications:global", "new_incident", %{
        id: incident_uuid
      })

      # Return true flag descriptor to instruct the channel to auto-mute or bounce the user
      {:flagged_violation, incident_uuid}
    else
      :clean_pass
    end
  end
end
