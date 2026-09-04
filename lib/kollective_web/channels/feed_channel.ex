defmodule KollectiveWeb.FeedChannel do
  use KollectiveWeb, :channel
  import Ecto.Query

  alias Kollective.Events.Events
  alias Kollective.Events.Event
  alias Kollective.Events.Participant, as: EventParticipant
  alias Kollective.Repo

  # Register the event interceptor so handle_out/3 is allowed to run
  intercept ["event_details_updated", "new_comment"]

  # Shared public streams
  @impl true
  def join("feed:public", _payload, socket), do: {:ok, socket}
  def join("voice_alert", _payload, socket), do: {:ok, socket}

  def join("discovery:local:" <> _scope, _payload, socket), do: {:ok, socket}
  def join("discovery:state:" <> _scope, _payload, socket), do: {:ok, socket}

  # THE EVENT ROOM ENTRANCE GATEWAY
  @impl true
  def join("event:" <> event_id, _payload, socket) do
    user_id = socket.assigns.user_id

    # 1. Enforce strict join-mode privacy boundaries at the front gate
    case Events.get_event(event_id) do
      {:ok, %Event{join_mode: "invite_only", created_by: creator_id}} ->
        is_invited =
          Repo.exists?(
            from(p in EventParticipant,
              where: p.event_id == ^event_id and p.user_id == ^user_id and p.status == "accepted"
            )
          )

        if is_invited or creator_id == user_id do
          # Return the initial history batch to React in the join token to save an API request
          {:ok, fetch_initial_comments_payload(event_id, user_id),
           assign(socket, :event_id, event_id)}
        else
          {:error, %{reason: "This is a private, invite-only event."}}
        end

      {:ok, _public_or_restricted_event} ->
        {:ok, fetch_initial_comments_payload(event_id, user_id),
         assign(socket, :event_id, event_id)}

      {:error, :not_found} ->
        {:error, %{reason: "Event not found."}}
    end
  end

  # Global Timeline Connection Gate
  def join("timeline:global", _payload, socket) do
    # Open streaming layer for users to catch cross-instance global activities instantly
    {:ok, socket}
  end

  # ─── REAL-TIME INTERCEPTORS & SHADOW-BAN SHIELDS ───

  # CLAUSE 1: Specialized interceptor matching on a specific string name
  # If an organizer edits an event, this block intercepts it, loads preloads, and formats the JSON payload
  @impl true
  def handle_out("event_details_updated", event_struct, socket) do
    # Formats structural data safely
    serialized_payload = KollectiveWeb.EventJSON.data(event_struct)
    push(socket, "event_details_updated", serialized_payload)
    {:noreply, socket}
  end

  # CLAUSE 2: The Generic Catch-All Fallback
  # Any other event (like "update_rsvps" or "new_post_available") bypasses Clause 1 and hits this block
  @impl true
  def handle_out("new_comment", %{comment: comment, author_shadow_banned?: true}, socket) do
    # SHADOW BAN INTERCEPTOR: If the author is shadow-banned, only push the comment to them!
    # To all other users on the platform, this comment is completely invisible
    if socket.assigns.user_id == comment.user_id do
      push(socket, "new_comment", KollectiveWeb.CommentJSON.data(comment))
    end

    {:noreply, socket}
  end

  @impl true
  def handle_out("new_comment", %{comment: comment, author_shadow_banned?: false}, socket) do
    # Clean comment: broadcast out to everyone looking at this event page instantly
    push(socket, "new_comment", KollectiveWeb.CommentJSON.data(comment))
    {:noreply, socket}
  end

  @impl true
  def handle_out(event, payload, socket) do
    # Directly stream all other transient metrics (like update_rsvps counters) down to React
    push(socket, event, payload)
    {:noreply, socket}
  end

  # --- In-Memory Batch Hydration Query Helper ---
  defp fetch_initial_comments_payload(event_id, user_id) do
    raw_comments = Events.list_comments(event_id, limit: 30)

    # Pre-calculate user liked markers using a single MapSet lookup pass to avoid N+1 query loops
    comment_ids = Enum.map(raw_comments, & &1.id)

    liked_ids =
      Repo.all(
        from(l in "comment_likes",
          where: l.user_id == ^user_id and l.comment_id in ^comment_ids,
          select: l.comment_id
        )
      )
      |> MapSet.new()

    serialized_comments =
      Enum.map(raw_comments, fn comment ->
        Map.put(comment, :is_liked_by_me, MapSet.member?(liked_ids, comment.id))
        |> KollectiveWeb.CommentJSON.data()
      end)

    %{comments: serialized_comments}
  end
end
