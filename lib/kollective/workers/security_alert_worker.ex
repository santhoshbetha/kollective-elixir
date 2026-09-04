#  SecurityAlertWorker logic to handle those "Hard Ban" notifications

# This worker handles high-priority alerts for "Hard-Banned" content or aggressive spam attempts. By using a
# separate worker, you can route these to a more urgent email or even a different notification channel
# (like a dedicated security log) without mixing them with standard moderation tasks.

# 1. The Security Alert Worker
# This worker extracts the threat details—like the user's IP, the specific "Hard" keywords triggered,
# and the user's history—and sends a consolidated report to the admin.

# 3. Why This "Split" Strategy Works:

#  Prioritization: Standard moderation emails (EventAlertWorker) go to the "Community Team," while SecurityAlertWorker emails go to the "Dev/Security Team."
#  Efficiency: If a bot hits your "Hard" keywords 1,000 times, you can add logic to this worker to throttle itself (e.g., "Don't send more than one security alert per hour for the same IP").
#  Traceability: Oban keeps a record of every security alert sent in the oban_jobs table, creating a secondary audit log of attacks.

defmodule Kollective.Workers.SecurityAlertWorker do
  use Oban.Worker, queue: :maintenance, max_attempts: 3
  alias Kollective.Accounts.Accounts
  alias Kollective.Mailer
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"type" => "hard_ban_triggered", "user_id" => user_id, "ip" => ip}
      }) do
    user = Accounts.get_user!(user_id)

    subject = "🚨 SECURITY ALERT: Hard-Ban Triggered"

    body = """
    A user has attempted to post content containing 'Hard-Banned' material.
    The post was automatically rejected and 'Black-Holed'.

    User: #{user.username} (ID: #{user.id})
    IP Address: #{ip}
    Action Taken: Content Discarded, User Flagged.

    The user is now automatically shadow-banned globally.
    Review user profile: https://kollective.social/users/#{user.id}
    """

    # Deliver via Swoosh/Finch
    case Mailer.send_admin_alert(subject, body) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to send security alert: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def perform(%Oban.Job{
        args: %{"type" => "hard_ban_attempt", "user_id" => user_id, "ip" => ip, "notes" => notes}
      }) do
    user = Accounts.get_user!(user_id)

    subject = "SECURITY ALERT: Hard-Ban Attempt"

    body = """
    A user attempted to submit content with prohibited language.

    User: #{user.username} (ID: #{user.id})
    IP Address: #{ip}
    Notes: #{notes}
    Action Taken: Request rejected.
    """

    case Mailer.send_admin_alert(subject, body) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to send security alert: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def perform(%Oban.Job{args: %{"type" => "aggressive_spam", "ip" => ip}}) do
    # Logic for IP-based blacklisting alerts
    subject = "🛡️ SECURITY: IP Blacklisted"
    body = "IP #{ip} has been added to the 24-hour blacklist due to aggressive rate-limit hits."

    Mailer.send_admin_alert(subject, body)
    :ok
  end

  # "Moderator Notes" to the automated security alert so admins can see exactly which three "Hard" words
  # triggered the user's cooldown
  # 3.Modify the worker to accept the notes argument and include it in the admin email.

  # Why this is effective:

  #  Contextual Evidence: Admins no longer have to guess which words caused the ban; the Oban job carries the exact proof.
  #  Precision: By using Enum.uniq, you don't list the same word three times if they just spammed the same prohibited term.
  #  Audit Readiness: The "Notes" are now part of the Swoosh email and the oban_jobs table history.
  def perform(%Oban.Job{
        args: %{"type" => "cooldown_triggered", "user_id" => u_id, "notes" => notes, "ip" => ip}
      }) do
    user = Accounts.get_user!(u_id)

    subject = "🚫 User Cooldown: Repeated Hard-Ban Violations"

    body = """
    User #{user.username} (ID: #{user.id}) has been Black-Holed from IP #{ip}.

    MODERATOR NOTES:
    #{notes}

    The user is blocked for 1 hour. This was triggered by 3 violations in 10 minutes.
    """

    Mailer.send_admin_alert(subject, body)
    :ok
  end
end
