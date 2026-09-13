# lib/kollective_web/controllers/posts/post_reaction_controller.ex
defmodule KollectiveWeb.PostReactionController do
  use KollectiveWeb, :controller

  alias Kollective.Repo
  alias Kollective.Posts.PostReaction

  # POST /api/v1/posts/:post_id/reactions
  # Expected Body payload: %{"emoji" => "🔥"}
  def create(conn, %{"post_id" => post_id, "emoji" => emoji}) do
    user = conn.assigns.current_user

    attrs = %{user_id: user.id, post_id: post_id, emoji: emoji}

    # Atomic insert pass handles composite uniqueness instantly
    case Repo.insert(%PostReaction{} |> PostReaction.changeset(attrs)) do
      {:ok, _reaction} ->
        # Broadcast live changes across channels so other viewports update in real-time
        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          "timeline:global",
          {:reaction_added, post_id, emoji}
        )

        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Reaction recorded successfully."})

      {:error, _changeset} ->
        # Unique constraint fallback: If clicked again, treat as a toggle remove action
        Repo.get_by(PostReaction, user_id: user.id, post_id: post_id, emoji: emoji)
        |> Repo.delete!()

        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          "timeline:global",
          {:reaction_removed, post_id, emoji}
        )

        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Reaction removed successfully."})
    end
  end
end
