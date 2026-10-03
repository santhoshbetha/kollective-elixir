defmodule KollectiveWeb.ConversationController do
  use KollectiveWeb, :controller
  alias Kollective.Chats.Chats
  alias KollectiveWeb.ConversationJSON

  def index(conn, _params) do
    current_user = conn.assigns[:current_user] || conn.assigns[:user]

    # Fetch recent rooms with preloaded last message and other participant profiles
    query = Chats.list_my_conversations(current_user_id)
    conversations = Kollective.Repo.all(query)

    conn
    |> put_status(:ok)
    |> json(%{data: ConversationJSON.index(conversations, current_user_id)})
  end
end
