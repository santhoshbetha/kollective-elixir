defmodule Kollective.Mailer do
  use Swoosh.Mailer, otp_app: :kollective
  import Swoosh.Email

  def send_admin_alert(subject, body) do
    new()
    |> to("admin@example.com")
    |> from({"Kollective System", "system@kollective.social"})
    |> subject(subject)
    |> text_body(body)
    # This sends the email via Finch/Swoosh
    |> deliver()
  end
end
