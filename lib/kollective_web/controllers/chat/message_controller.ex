defmodule KollectiveWeb.MessageController do
  use KollectiveWeb, :controller
  import Ecto.Query

  alias Kollective.Repo
  alias Kollective.Chats.Chats
  alias Kollective.Chats.Participant
  alias KollectiveWeb.MessageJSON

  @doc """
  GET /api/v1/conversations/:conversation_id/messages
  Fetches historical messages with look-ahead cursor support after validating participant permissions [1.4].
  """
  def index(conn, %{"conversation_id" => conversation_id} = params) do
    # SAFE SESSION EXTRACTION: Handles both current_user mappings and fallback user shapes cleanly
    current_user = conn.assigns[:current_user] || conn.assigns[:user]

    if Chats.is_participant?(conversation_id, current_user.id) do
      limit = Map.get(params, "limit", "20") |> String.to_integer()
      before_id = Map.get(params, "before_id")

      {messages, other_last_read} =
        Chats.list_messages_cursor(conversation_id, current_user.id,
          limit: limit,
          before_id: before_id
        )

      next_cursor =
        case List.first(messages) do
          nil -> nil
          first_msg -> first_msg.id
        end

      render(conn, :index,
        messages: messages,
        other_participant_last_read: other_last_read,
        next_cursor: next_cursor
      )
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Unauthorized access path."})
    end
  end

  @doc """
  POST /api/v1/conversations/:conversation_id/messages
  Processes incoming RSA-encrypted binary payloads, writes to DB, and handles real-time de-duplication [1.4].
  """
  def create(conn, %{"conversation_id" => conv_id, "message" => msg_params} = params) do
    current_user = conn.assigns[:current_user] || conn.assigns[:user]

    IO.inspect(current_user, label: "current_user")
    IO.inspect(conv_id, label: "conv_id")
    IO.inspect(msg_params, label: "msg_params")

    # 🚀 THE DE-DUPLICATION FIX: Intercept the client-side tracing nonce
    client_nonce = Map.get(params, "nonce") || Map.get(msg_params, "nonce")

    IO.inspect(client_nonce, label: "client_nonce")

    case Chats.create_message_with_attachment(current_user.id, conv_id, msg_params) do
      {:ok, %{message: message}} ->
        # Pass the tracking nonce through to the WebSocket broadcast loop [1.4]
        broadcast_new_message(message, client_nonce)

        IO.inspect(message, label: "message")

        # Trigger a silent push notification to bump the recipient's unread counter [1.4]
        trigger_unread_badge_bump(current_user.id, conv_id)

        conn
        |> put_status(:created)
        |> render(:show, message: message)

      {:error, _failed_operation, changeset, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end

  # --- Private Real-Time Routing Helpers ---

  defp broadcast_new_message(message, nonce) do
    topic = "conversation:#{message.conversation_id}"

    # Serialize the binary content safely
    base_payload = MessageJSON.broadcast_data(message)

    # Inject the client-side nonce back into the payload map [1.4]
    final_payload = if nonce, do: Map.put(base_payload, :nonce, nonce), else: base_payload

    # Broadcast out to the active frontend chat components instantly [1.4]
    KollectiveWeb.Endpoint.broadcast!(topic, "new_message", final_payload)
  end

  defp trigger_unread_badge_bump(sender_id, conversation_id) do
    alias Kollective.Chats.Participant
    alias Kollective.Repo
    import Ecto.Query

    sender = Repo.get(Kollective.Accounts.User, sender_id)

    recipient_id =
      from(p in Participant,
        where: p.conversation_id == ^conversation_id and p.user_id != ^sender_id,
        select: p.user_id
      )
      |> Repo.one()

    IO.inspect(recipient_id, label: "recipient_id")
    IO.inspect(sender, label: "sender")

    if recipient_id && sender do
      # Calculate the recipient's fresh unread message balances count
      unread_count = Kollective.Chats.Chats.get_unread_count(conversation_id, recipient_id)

      # 🚨 UNIFIED REAL-TIME DATA SCHEMA CONTRACT:
      # We pack all metrics into a flat map that mirrors your exact React payload expectations
      alert_payload = %{
        # Protects lists loops rendering errors on frontend
        "id" => Ecto.UUID.generate(),
        "type" => "dm_badge_update",
        "conversation_id" => to_string(conversation_id),
        "unread_count" => unread_count,
        "sender_id" => to_string(sender_id),
        "sender_username" => sender.username,
        # Double protection safety tracking fallback
        "operator_name" => sender.username,
        "preview_text" => "Sent you an encrypted direct transmission message."
      }

      IO.inspect(alert_payload, label: "alert_payload")

      # 🚀 THE BACKEND FIX:
      # Broadcasts across your explicit user topic lane using the standard "new_notification" key.
      # This bypasses channel structural restrictions and forces delivery across the pipeline.
      KollectiveWeb.Endpoint.broadcast!(
        "user_notifications:#{recipient_id}",
        "new_notification",
        alert_payload
      )

      IO.inspect(alert_payload, label: "alert_payload")
    end
  end

  defp trigger_unread_badge_bumpX(sender_id, conversation_id) do
    # 1. Fetch recipient and sender username references cleanly
    sender = Kollective.Repo.get(Kollective.Accounts.User, sender_id)

    recipient_id =
      from(p in Participant,
        where: p.conversation_id == ^conversation_id and p.user_id != ^sender_id,
        select: p.user_id
      )
      |> Repo.one()

    if recipient_id && sender do
      unread_count = Chats.get_unread_count(conversation_id, recipient_id)

      # 2. Enrich the alert payload with sender metadata parameters
      alert_payload = %{
        type: "dm_badge_update",
        conversation_id: to_string(conversation_id),
        unread_count: unread_count,
        sender_id: to_string(sender_id),
        sender_username: sender.username
      }

      # Broadcast down the recipient's secure notification lane instantly
      KollectiveWeb.Endpoint.broadcast(
        "user_notifications:#{recipient_id}",
        # Matches your exact frontend listener event name
        "new_notification",
        alert_payload
      )
    end
  end

  def trigger_desktop_app_badging_sync(recipient_id) do
    # Calculate current total unread message counts across all conversations for this specific user
    unread_matrix_count = Kollective.Chats.Chats.get_total_unread_count(recipient_id)

    # Fire a fast notification down the recipient's private user channel lane
    KollectiveWeb.Endpoint.broadcast(
      "user_notifications:#{recipient_id}",
      "badge_count_sync",
      %{
        "unread_count" => unread_matrix_count,
        "trigger_event" => "inbound_message_receipt"
      }
    )
  end
end
