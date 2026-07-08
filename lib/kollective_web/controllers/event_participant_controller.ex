defmodule KollectiveWeb.EventParticipantController do
  use KollectiveWeb, :controller
  import Ecto.Query, only: [from: 2]
  alias Kollective.Accounts.Accounts
  alias Kollective.Events.Events

  # POST /api/v1/kollective/events/:event_id/join
  def join(conn, %{"event_id" => event_id}) do
    user = conn.assigns.current_user

    case Events.join_event(user, event_id) do
      {:ok, :joined} ->
        json(conn, %{
          status: "success",
          code: "joined",
          message: "Successfully registered for this event."
        })

      {:ok, :requested} ->
        json(conn, %{
          status: "success",
          code: "requested",
          message: "Your participation request is pending organizer approval."
        })

      {:ok, :waitlisted} ->
        json(conn, %{
          status: "success",
          code: "waitlisted",
          message: "Event is at full capacity. You have been added to the waitlist queue."
        })

      {:error, conflict_message} ->
        conn
        # Standard HTTP 409 Conflict status
        |> put_status(:conflict)
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
        json(conn, %{
          status: "success",
          code: "waitlisted",
          message: "Event is full. You have been waitlisted."
        })

      {:ok, final_code} ->
        json(conn, %{
          status: "success",
          code: Atom.to_string(final_code),
          message: "RSVP successfully submitted."
        })

      {:error, conflict_message} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "calendar_conflict", message: conflict_message})
    end
  end

  # ─── ACTION 1: LIST ACCEPTED PARTICIPANTS ROSTER ───
  # GET /api/v1/kollective/events/:event_id/participants
  def participations(conn, %{"event_id" => event_id}) do
    current_user = conn.assigns.current_user

    # 1. Fetch the raw roster with user structs preloaded in exactly one query pass
    participant_join_records = Events.list_accepted_participants(event_id)

    # 2. Extract users and enforce bidirectional block masks
    # Restricts blocked actors from polluting rosters
    users =
      participant_join_records
      |> Enum.map(& &1.user)
      |> Enum.filter(fn user ->
        is_nil(current_user) or not Accounts.blocks?(current_user, user)
      end)

    # 3. Serialize output instantly using a clean map loop structure
    json(conn, %{
      data:
        Enum.map(users, fn u ->
          %{
            id: u.id,
            username: u.username,
            display_name: u.display_name,
            avatar_url: u.avatar_url
          }
        end)
    })
  end

  # ─── ACTION 2: LIST PENDING JOIN APPROVAL REQUESTS ───
  # GET /api/v1/kollective/events/:event_id/requests
  def participation_requests(conn, %{"event_id" => event_id}) do
    organizer = conn.assigns.current_user

    # 1. Ownership & verification shield pass
    case Events.get_event(event_id) do
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Event not found."})

      {:ok, event} ->
        if event.created_by != organizer.id do
          conn
          |> put_status(:forbidden)
          |> json(%{error: "You are not authorized to view requests for this event."})
        else
          # 2. Extract database rows matching pending states
          pending_requests =
            Kollective.Repo.all(
              from(p in Kollective.Events.Participant,
                where: p.event_id == ^event.id and p.status == "pending",
                preload: [:user],
                order_by: [desc: p.id]
              )
            )

          json(conn, %{
            data:
              KollectiveWeb.EventJSON.participation_requests(%{
                requests: pending_requests,
                for: organizer
              })
          })
        end
    end
  end

  # ─── ACTION 3: AUTHORIZE / APPROVE JOIN REQUEST ───
  # POST /api/v1/kollective/event_requests/:participant_id/approve
  def authorize_participation_request(conn, %{"participant_id" => participant_id}) do
    organizer = conn.assigns.current_user

    # Invokes our optimized multi-row atomic transaction engine
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

  # ─── ACTION 4: REJECT / DISMISS JOIN REQUEST ───
  # POST /api/v1/kollective/event_requests/:participant_id/reject
  def reject_participation_request(conn, %{"participant_id" => participant_id}) do
    organizer = conn.assigns.current_user

    # Invokes our clean Ecto.Multi subtraction engine
    case Events.reject_request(organizer, participant_id) do
      {:ok, :rejected} ->
        json(conn, %{status: "success", message: "Attendee request successfully rejected."})

      {:error, error_message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "rejection_failed", message: error_message})
    end
  end
end
