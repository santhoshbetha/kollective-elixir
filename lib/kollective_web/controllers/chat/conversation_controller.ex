defmodule KollectiveWeb.ConversationController do
  use KollectiveWeb, :controller

  alias Kollective.Repo
  alias Kollective.Accounts.User
  alias Kollective.Chats.Chats
  alias KollectiveWeb.ConversationJSON

  @doc """
  GET /api/v1/conversations
  Fetches the active user's inbox list, including preloaded last messages and partner public keys [1.4].
  """
  def index(conn, _params) do
    current_user = conn.assigns[:current_user] || conn.assigns[:user]

    # Fetch recent conversations from your Chats context
    query = Chats.list_my_conversations(current_user.id)
    conversations = Repo.all(query)

    conn
    |> put_status(:ok)
    |> json(%{data: ConversationJSON.index(conversations, current_user.id)})
  end

  @doc """
  POST /api/v1/conversations
  Finds or creates a 1-on-1 direct message conversation between current_user and target user.
  """
  def create(conn, params) do
    current_user = conn.assigns[:current_user] || conn.assigns[:user]

    target_user_id = Map.get(params, "user_id") || Map.get(params, "recipient_id")

    target_user =
      cond do
        target_user_id != nil ->
          Repo.get(User, target_user_id)

        username = Map.get(params, "username") || Map.get(params, "handle") ->
          clean_name = String.replace(to_string(username), ~r/^@/, "")

          Repo.get_by(User, username: clean_name) || Repo.get_by(User, handle: "@" <> clean_name) ||
            Repo.get_by(User, handle: clean_name)

        true ->
          nil
      end

    case target_user do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Target user profile not found."})

      %{id: target_id} ->
        case Chats.get_or_create_1on1(current_user.id, target_id) do
          {:ok, conversation} ->
            conv_id = to_string(conversation.id)

            conn
            |> put_status(:ok)
            |> json(%{id: conv_id, conversation_id: conv_id, data: %{id: conv_id}})

          {:error, _reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Unable to create conversation thread."})
        end
    end
  end
end
