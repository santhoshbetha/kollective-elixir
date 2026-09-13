defmodule Kollective.OrganizationMailer do
  use Swoosh.Mailer, otp_app: :kollective
  import Swoosh.Email

  @doc """
  Builds a transactional email struct for a newly invited contributor.
  """
  def invite_notification_email(recipient_email, recipient_name, org_name, assigned_role) do
    new()
    |> to({recipient_name, recipient_email})
    |> from({"Kollective", "[EMAIL_ADDRESS]"})
    |> subject("You have been invited to join #{org_name}!")
    |> html_body("""
      <h1>Hello, #{recipient_name}!</h1>
      <p>You have received an invitation to join <strong>#{org_name}</strong> as a <strong>#{assigned_role}</strong>.</p>
      <p>Please log into your dashboard app panel to accept or decline this active workspace slot.</p>
      <br/>
      <p><i>Note: This request loop will naturally expire in 7 days.</i></p>
    """)
    |> text_body("""
      Hello, #{recipient_name}!
      You have received an invitation to join #{org_name} as a #{assigned_role}.
      Please log into your dashboard app panel to accept or decline this active workspace slot.
      Note: This request loop will naturally expire in 7 days.
    """)
  end
end
