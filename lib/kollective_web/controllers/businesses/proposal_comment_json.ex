# lib/kollective_web/controllers/businesses/proposal_comment_json.ex
defmodule KollectiveWeb.ProposalCommentJSON do
  @moduledoc """
  JSON serializer for Business Proposal discussion threads.

  Emits both `author` (the canonical comment shape used by the event engine) and
  `user` aliases so existing discussion UI components can hydrate author cards
  without a second lookup.
  """

  def index(%{comments: comments}), do: index(comments)

  def index(comments) when is_list(comments) do
    Enum.map(comments, &data/1)
  end

  def show(%{comment: comment}), do: show(comment)

  def show(comment) do
    %{status: "success", data: data(comment)}
  end

  def data(comment) do
    author = serialize_author(Map.get(comment, :user))

    %{
      id: to_string(comment.id),
      content: Map.get(comment, :content) || "",
      image_url: Map.get(comment, :image_url),
      moderation_status: Map.get(comment, :moderation_status),
      inserted_at:
        (Map.get(comment, :inserted_at) &&
           Calendar.strftime(comment.inserted_at, "%Y-%m-%dT%H:%M:%SZ")) || nil,
      business_id: (comment.business_id && to_string(comment.business_id)) || nil,
      parent_id: (comment.parent_id && to_string(comment.parent_id)) || nil,
      author: author,
      # Alias kept for the shared discussion renderers
      user: author,
      user_id: author && author[:id],
      replies: serialize_replies(Map.get(comment, :replies))
    }
  end

  defp serialize_replies(%Ecto.Association.NotLoaded{}), do: []
  defp serialize_replies(nil), do: []
  defp serialize_replies(list) when is_list(list), do: Enum.map(list, &data/1)
  defp serialize_replies(_), do: []

  defp serialize_author(%Ecto.Association.NotLoaded{}), do: nil
  defp serialize_author(nil), do: nil

  defp serialize_author(user) do
    %{
      id: to_string(Map.get(user, :id)),
      username: Map.get(user, :username),
      name: Map.get(user, :display_name) || Map.get(user, :username),
      avatar_url: Map.get(user, :avatar_url) || "/default-avatar.jpg"
    }
  end
end
