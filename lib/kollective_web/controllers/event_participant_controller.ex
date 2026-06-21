defmodule KollectiveWeb.EventParticipantController do
  use KollectiveWeb, :controller
  alias Kollective.Events.Events

  # POST /api/v1/kollective/events/:event_id/join
  def join(conn, %{"event_id" => event_id}) do
    user = conn.assigns.current_user

    case Events.join_event(user, event_id) do
      {:ok, :joined} ->
        json(conn, %{status: "success", code: "joined", message: "Successfully registered for this event."})

      {:ok, :requested} ->
        json(conn, %{status: "success", code: "requested", message: "Your participation request is pending organizer approval."})

      {:ok, :waitlisted} ->
        json(conn, %{status: "success", code: "waitlisted", message: "Event is at full capacity. You have been added to the waitlist queue."})

      {:error, conflict_message} ->
        conn
        |> put_status(:conflict) # Standard HTTP 409 Conflict status
        |> json(%{error: "calendar_conflict", message: conflict_message})
    end
  end

  # POST /api/v1/kollective/events/:event_id/leave
  def leave(conn, %{"event_id" => event_id}) do
    user = conn.assigns.current_user

    case Events.leave_event(user, event_id) do
      {:ok, _} ->
        json(conn, %{status: "success", message: "Successfully left the event."})

      {:error, error_msg} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "leave_failed", message: error_msg})
    end
  end

  # POST /api/v1/kollective/events/requests/:participant_id/approve
  def approve(conn, %{"participant_id" => participant_id}) do
    organizer = conn.assigns.current_user

    case Events.approve_request(organizer, participant_id) do
      {:ok, :approved} ->
        json(conn, %{status: "success", message: "Attendee request successfully approved."})

      {:ok, :already_approved} ->
        json(conn, %{status: "success", message: "This request was already approved."})

      {:error, error_message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "approval_failed", message: error_message})
    end
  end


  # POST /api/v1/kollective/events/requests/:participant_id/reject
  def reject(conn, %{"participant_id" => participant_id}) do
    organizer = conn.assigns.current_user

    case Events.reject_request(organizer, participant_id) do
      {:ok, :rejected} ->
        json(conn, %{status: "success", message: "Attendee request successfully rejected."})

      {:error, error_message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "rejection_failed", message: error_message})
    end
  end


  def render_event_with_social_context(conn, event, current_user) do
    # 1. Fetch a fast preview list of attendees for the faces row widget
    attendee_preview = Events.list_participants(event.id, 10)

    # 2. Extract which specific friends are going to this event
    friends_going =
      if current_user do
        Events.list_friends_attending(current_user, event.id)
      else
        []
      end

    json(conn, %{
      event: KollectiveWeb.EventJSON.data(event),
      attendee_preview: Enum.map(attendee_preview, &serialize_simple_user/1),
      friends_attending: Enum.map(friends_going, &serialize_simple_user/1)
    })
  end

  defp serialize_simple_user(participant) do
    %{
      id: participant.user.id,
      username: participant.user.username,
      avatar_url: participant.user.avatar_url
    }
  end


  # POST /api/v1/kollective/events/:event_id/rsvp
  # Expected payload parameter: %{"status" => "going"} or "maybe", "no"
  def rsvp(conn, %{"event_id" => event_id, "status" => status}) do
    user = conn.assigns.current_user

    case Events.rsvp_to_event(user, event_id, status) do
      {:ok, :accepted} ->
        json(conn, %{status: "success", code: "going", message: "RSVP updated to: Going"})

      {:ok, :waitlisted} ->
        json(conn, %{status: "success", code: "waitlisted", message: "Event is full. You have been waitlisted."})

      {:ok, final_code} ->
        json(conn, %{status: "success", code: Atom.to_string(final_code), message: "RSVP successfully submitted."})

      {:error, conflict_message} ->
        conn |> put_status(:conflict) |> json(%{error: "calendar_conflict", message: conflict_message})
    end
  end




end
