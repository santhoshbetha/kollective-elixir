defmodule KollectiveWeb.ConversationController do
  use KollectiveWeb, :controller

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
    conversations = Kollective.Repo.all(query)

    conn
    |> put_status(:ok)
    |> json(%{data: ConversationJSON.index(conversations, current_user.id)})
  end
end
