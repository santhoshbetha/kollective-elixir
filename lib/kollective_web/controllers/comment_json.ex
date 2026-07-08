# list_comments feature

defmodule KollectiveWeb.CommentJSON do
  def index(%{comments: comments}) do
    Enum.map(comments, &data/1)
  end

  def data(comment) do
    # Pull the nested replies array map safely if preloaded
    replies =
      case comment.replies do
        %Ecto.Association.NotLoaded{} -> []
        nil -> []
        list -> Enum.map(list, &data/1)
      end

    %{
      id: to_string(comment.id),
      content: comment.content || "",
      image_url: comment.image_url,
      moderation_status: comment.moderation_status,
      inserted_at: Calendar.strftime(comment.inserted_at, "%Y-%m-%dT%H:%M:%SZ"),

      # Interaction counters cache flags
      likes_count: Map.get(comment, :likes_count, 0),
      has_liked: Map.get(comment, :has_liked, false),
      parent_id: to_string(comment.parent_id),

      # Requester Author profile card signature block
      author: %{
        id: to_string(comment.user.id),
        username: comment.user.username,
        avatar_url: comment.user.avatar_url || "/default-avatar.jpg"
      },
      replies: replies
    }
  end

  def list_data(comments) when is_list(comments) do
    Enum.map(comments, &data/1)
  end
end
