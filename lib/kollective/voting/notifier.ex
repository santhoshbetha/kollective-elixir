defmodule Kollective.Voting.Notifier do
  alias KollectiveWeb.Endpoint

  @doc """
  Loops through assigned jurors and pushes a real-time notification payload down their WebSocket.
  """
  def send_jury_invitations(application_id, juror_ids) do
    payload = %{
      type: "JURY_DUTY_ASSIGNED",
      title: "Frontline Action Verification",
      message: "You have been selected as a blind juror to vet a new Signal Red badge candidate.",
      application_id: application_id,
      expires_in_hours: 48
    }

    Enum.each(juror_ids, fn juror_id ->
      # Broadcasts to the specific private channel for each juror
      Endpoint.broadcast("user:#{juror_id}", "new_notification", payload)
    end)
  end
end
