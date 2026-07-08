# lib/kollective/workers/org_notification_worker.ex
defmodule Kollective.Workers.OrgNotificationWorker do
  @moduledoc """
  Asynchronous Organization Membership Lifecycle Notification Worker.
  Processes background state updates and dispatches template emails safely via Swoosh.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Kollective.Repo
  alias Kollective.Accounts.User
  alias Swoosh.Email
  alias Kollective.Mailer

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"user_id" => user_id, "organization_id" => org_id, "action" => action}
      }) do
    # 1. Fetch data entities safely out of background process RAM strings
    user = Repo.get!(User, user_id)
    org = Repo.get!(User, org_id)

    # 2. Compile dynamic email metadata text payloads based on the transaction status
    {subject, body} =
      case action do
        "approved" ->
          badge_type = Map.get(org.data || %{}, "badge_type", "verified")

          {
            "Confirmed: You have been added to @#{org.username}!",
            """
            Hello @#{user.username},

            Success! Your request to join the organization profile '@#{org.username}' has been approved as an active member.
            You can now switch your publishing context dropdown inside the composer box to post officially under their name.

            Organization Verification Status: #{badge_type}
            """
          }

        "rejected" ->
          {
            "Update regarding your Organization Membership Request",
            """
            Hello @#{user.username},

            Your request to join the organization profile '@#{org.username}' was not approved at this time.
            If you believe this was an error, please reach out to the organization's administration team directly.
            """
          }
      end

    # 3. Dispatch the message text natively via your Swoosh infrastructure
    Email.new()
    |> Email.to(user.email)
    |> Email.from({"Kollective Network", "support@kollective.app"})
    |> Email.subject(subject)
    |> Email.text_body(body)
    |> Mailer.deliver()
    |> case do
      {:ok, _metadata} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
