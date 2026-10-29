defmodule KollectiveWeb.EventParticipantController do
  use KollectiveWeb, :controller
  import Ecto.Query, only: [from: 2]
  alias Kollective.Accounts.Accounts
  alias Kollective.Events.Events
  alias KollectiveWeb.EventJSON
  alias KollectiveWeb.Plugs.AuthorizeOrgSocialAction

  plug AuthorizeOrgSocialAction when action in [:join, :rsvp, :leave]

  # POST /api/v1/kollective/events/:event_id/join
  def join(conn, %{"event_id" => event_id}) do
    actor =
      if conn.assigns[:account_type] == :organization and conn.assigns[:current_organization] do
        conn.assigns[:current_organization]
      else
        conn.assigns.current_user
      end

    case Events.join_event(actor, event_id) do
        {:ok, :joined} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          code: "joined",
          isAttending: true,
          message: "Successfully registered for this event."
        })

      {:ok, :left} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          code: "left",
          isAttending: false,
          message: "Successfully left the event."
        })

      {:ok, :requested} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          code: "requested",
          isAttending: false,
          message: "Your participation request is pending organizer approval."
        })

      {:ok, :waitlisted} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          code: "waitlisted",
          isAttending: false,
          message: "Event is at full capacity. You have been added to the waitlist queue."
        })

      {:ok, other_code} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          code: to_string(other_code),
          message: "Event attendance updated."
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
    actor =
      if conn.assigns[:account_type] == :organization and conn.assigns[:current_organization] do
        conn.assigns[:current_organization]
      else
        conn.assigns.current_user
      end

    case Events.leave_event(actor, event_id) do
      {:ok, _} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Successfully left the event."})

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
      res when res in [{:ok, :approved}, {:ok, {:ok, :approved}}] ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Attendee request successfully approved."})

      res when res in [{:ok, :already_approved}, {:ok, {:ok, :already_approved}}] ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "This request was already approved."})

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
      res when res in [{:ok, :rejected}, {:ok, {:ok, :rejected}}] ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Attendee request successfully rejected."})

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

    conn
    |> put_status(:ok)
    |> json(EventJSON.event_with_social_context(event, attendee_preview, friends_going))
  end

  # POST /api/v1/kollective/events/:event_id/rsvp
  # Expected payload parameter: %{"status" => "going"} or "maybe", "no", "interested"
  def rsvp(conn, params) do
    actor =
      if conn.assigns[:account_type] == :organization and conn.assigns[:current_organization] do
        conn.assigns[:current_organization]
      else
        conn.assigns.current_user
      end

    event_id = params["event_id"] || params["id"] || params["action_id"]
    status = Map.get(params, "status", "interested")

    case Events.rsvp_to_event(actor, event_id, status) do
        {:ok, code} when code in [:removed, "removed"] ->
          conn
          |> put_status(:ok)
          |> json(%{
            status: "success",
            code: "removed",
            isInterested: false,
            isAttending: false,
            rsvp: "None",
            user_rsvp_status: "None",
            userStatus: "None",
            message: "RSVP removed."
          })

        {:ok, {:ok, inner_code}} ->
          code_str = to_string(inner_code) |> String.downcase()
          is_interested = code_str == "interested"
          is_attending = code_str in ["accepted", "joined", "going", "attending"]

          rsvp_status =
            cond do
              is_attending -> "Attending"
              is_interested -> "Interested"
              true -> "None"
            end

          conn
          |> put_status(:ok)
          |> json(%{
            status: "success",
            code: code_str,
            isInterested: is_interested,
            isAttending: is_attending,
            rsvp: rsvp_status,
            user_rsvp_status: rsvp_status,
            userStatus: rsvp_status,
            message: "RSVP updated to: #{status}"
          })

        {:ok, final_code} when is_atom(final_code) or is_binary(final_code) ->
          code_str = to_string(final_code) |> String.downcase()
          is_interested = code_str == "interested"
          is_attending = code_str in ["accepted", "joined", "going", "attending"]

          rsvp_status =
            cond do
              is_attending -> "Attending"
              is_interested -> "Interested"
              true -> "None"
            end

          conn
          |> put_status(:ok)
          |> json(%{
            status: "success",
            code: code_str,
            isInterested: is_interested,
            isAttending: is_attending,
            rsvp: rsvp_status,
            user_rsvp_status: rsvp_status,
            userStatus: rsvp_status,
            message: "RSVP updated to: #{status}"
          })

        {:error, error_msg} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "rsvp_failed", message: error_msg})
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

    # 3. Serialize output instantly using a clean EventJSON call
    conn
    |> put_status(:ok)
    |> json(%{
      data: EventJSON.participant_users(users)
    })
  end

  # GET /api/v1/events/:event_id/requests
  def list_requests(conn, params), do: participation_requests(conn, params)

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

          conn
          |> put_status(:ok)
          |> json(%{
            data:
              EventJSON.participation_requests(%{
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
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Attendee request successfully approved."})

      {:ok, :already_approved} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "This request was already approved."})

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
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Attendee request successfully rejected."})

      {:error, error_message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "rejection_failed", message: error_message})
    end
  end
end
