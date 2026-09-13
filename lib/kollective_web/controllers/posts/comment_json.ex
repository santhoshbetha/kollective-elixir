# lib/kollective_web/controllers/posts/comment_json.ex
defmodule KollectiveWeb.CommentJSON do
  @moduledoc """
  Unified JSON serializer for Post Comments and threaded conversation replies.
  """

  @doc """
  Serializes a collection of comment records.
  """
  def index(%{comments: comments}), do: index(comments)

  def index(comments) when is_list(comments) do
    Enum.map(comments, &data/1)
  end

  @doc """
  Serializes a single comment entity.
  """
  def show(%{comment: comment}), do: show(comment)

  def show(comment) do
    %{data: data(comment)}
  end

  @doc """
  Serializes a single comment data map.
  """
  def data(comment) do
    # Pull the nested replies array map safely if preloaded
    replies =
      case Map.get(comment, :replies) do
        %Ecto.Association.NotLoaded{} -> []
        nil -> []
        list when is_list(list) -> Enum.map(list, &data/1)
      end

    %{
      id: to_string(comment.id),
      content: Map.get(comment, :content) || "",
      image_url: Map.get(comment, :image_url),
      moderation_status: Map.get(comment, :moderation_status),
      inserted_at:
        (Map.get(comment, :inserted_at) &&
           Calendar.strftime(comment.inserted_at, "%Y-%m-%dT%H:%M:%SZ")) || nil,

      # Interaction counters cache flags
      likes_count: Map.get(comment, :likes_count, 0),
      has_liked: Map.get(comment, :has_liked, false),
      parent_id: (comment.parent_id && to_string(comment.parent_id)) || nil,

      # Requester Author profile card signature block
      author: serialize_author(Map.get(comment, :user)),
      replies: replies
    }
  end

  def list_data(comments) when is_list(comments) do
    Enum.map(comments, &data/1)
  end

  defp serialize_author(%Ecto.Association.NotLoaded{}), do: nil
  defp serialize_author(nil), do: nil

  defp serialize_author(user) do
    %{
      id: to_string(Map.get(user, :id)),
      username: Map.get(user, :username),
      avatar_url: Map.get(user, :avatar_url) || "/default-avatar.jpg"
    }
  end
end
