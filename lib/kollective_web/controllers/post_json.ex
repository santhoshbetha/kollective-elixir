# lib/kollective_web/views/post_json.ex
defmodule KollectiveWeb.PostJSON do
  @moduledoc """
  Unified Standalone Timeline Post Serializer.
  Formats structural database hydration wrapper maps cleanly for the React UI.
  """
  @doc "Serializes an array list collection of post wrapper entries."
  def index(%{entries: entries}) do
    Enum.map(entries, &show/1)
  end

  @doc "Serializes a single post wrapper entry with full interaction states and media logs."
  def show(item) do
    post = item.post

    %{
      id: to_string(post.id),
      content: post.content,
      # Safe access if category is optional
      category: Map.get(post, :category),
      # Standard ISO string
      inserted_at: Calendar.strftime(post.inserted_at, "%Y-%m-%dT%H:%M:%SZ"),

      # Social engagement metrics and flags
      likes_count: item.likes_count,
      reblogs_count: item.reblogs_count,
      has_liked: item.has_liked,
      has_reblogged: item.has_reblogged,
      bookmarked: post.bookmarked || false,
      vote_data: post.vote_data,
      my_reactions: Map.get(post.data || %{}, "my_reactions", []),

      # Author info
      author: %{
        id: to_string(post.author.id),
        username: post.author.username,
        avatar_url: post.author.avatar_url || "/default-avatar.jpg"
      },

      # INTERACTIVE CARD PREVIEW OBJECT: Returns nil if no link was pasted
      link_preview:
        if post.link_url do
          %{
            url: post.link_url,
            title: post.link_title || "Loading Preview...",
            description: post.link_description || "",
            image_url: post.link_preview_image
          }
        else
          nil
        end,

      # MEDIA ATTACHMENTS PORTFOLIO ARRAY: Serializes S3/R2 picture data maps
      media_attachments: serialize_attachments(Map.get(post, :attachments))
    }
  end

  # Safe preloading fallback checker blocks
  defp serialize_attachments(%Ecto.Association.NotLoaded{}), do: []
  defp serialize_attachments(nil), do: []

  defp serialize_attachments(attachments) do
    Enum.map(attachments, fn att ->
      %{
        id: to_string(att.id),
        # e.g. "https://r2.dev..."
        url: att.url,
        type:
          if(String.starts_with?(att.media_type || "image", "video"), do: "video", else: "image"),
        blurhash: att.blurhash
      }
    end)
  end
end
