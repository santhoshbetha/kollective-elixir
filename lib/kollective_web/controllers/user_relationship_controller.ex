# React app will hit this endpoint, and you’ll return the new "following" status
# so the UI button can change from "Follow" to "Following".
defmodule KollectiveWeb.UserRelationshipController do
  use KollectiveWeb, :controller
  alias Kollective.Accounts.Users
  alias Kollective.Accounts.UserRelationship

  def toggle_follow(conn, %{"target_id" => target_id}) do
    source_id = conn.assigns.current_user.id

    case Users.follow_user2(source_id, target_id) do
      {:ok, %UserRelationship{}} ->
        json(conn, %{status: "following"})

      {:ok, _deleted_struct} ->
        json(conn, %{status: "not_following"})

      {:error, message} ->
        conn |> put_status(422) |> json(%{error: message})
    end
  end
end
