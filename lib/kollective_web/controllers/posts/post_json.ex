# lib/kollective_web/controllers/posts/post_json.ex
defmodule KollectiveWeb.PostJSON do
  @moduledoc """
  Unified Standalone Timeline Post Serializer.
  Formats structural database hydration wrapper maps cleanly for the React UI.
  """

  @doc "Serializes an array list collection of post wrapper entries or posts."
  def index(%{entries: entries}) do
    Enum.map(entries, &show/1)
  end

  def index(%{posts: posts}) do
    Enum.map(posts, &show/1)
  end

  def index(items) when is_list(items) do
    Enum.map(items, &show/1)
  end

  @doc "Serializes a single post entity or hydration item."
  def show(%{post: _post} = item) do
    render_item(item)
  end

  def show(%Kollective.Posts.Post{} = post) do
    show(%{
      post: post,
      likes_count: 0,
      reblogs_count: 0,
      has_liked: false,
      has_reblogged: false
    })
  end

  def show(item) do
    render_item(item)
  end

  @doc "Alias for show/1 to maintain uniformity across JSON serializers."
  def data(item), do: show(item)

  defp render_item(item) do
    post = item.post
    # Dynamically interpolate your base canonical domain path with the row's ULID key [INDEX]
    base_domain = KollectiveWeb.Endpoint.url()
    computed_permalink = "#{base_domain}/posts/#{to_string(post.id)}"

    %{
      id: to_string(post.id),
      content: post.content,
      # Safe access if category is optional
      category: Map.get(post, :category),
      # Standard ISO string
      inserted_at: Calendar.strftime(post.inserted_at, "%Y-%m-%dT%H:%M:%SZ"),
      published_at:
        (Map.get(post, :published_at) &&
           Calendar.strftime(post.published_at, "%Y-%m-%dT%H:%M:%SZ")) || nil,

      # 🟢 PASSES A CLEAN COMPUTED RUNTIME PERMALINK STRAIGHT TO REACT [INDEX]
      permalink: computed_permalink,

      # Social engagement metrics and flags
      likes_count: item.likes_count,
      reblogs_count: item.reblogs_count,
      has_liked: item.has_liked,
      has_reblogged: item.has_reblogged,
      bookmarked: post.bookmarked || false,
      favourited: Map.get(post, :favourited, false),
      reblogged: Map.get(post, :reblogged, false),
      vote_data: post.vote_data,
      my_reactions: Map.get(post.data || %{}, "my_reactions", []),

      # Author info
      author: serialize_author(Map.get(post, :author)),
      organization_id: (post.organization_id && to_string(post.organization_id)) || nil,
      organization: serialize_organization(Map.get(post, :organization)),

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
      media_attachments: serialize_attachments(Map.get(post, :attachments)),

      # POLL: Serializes the poll if attached
      poll: serialize_poll(Map.get(post, :poll)),

      # Additional Mastodon-like fields
      in_reply_to_id: (post.in_reply_to_id && to_string(post.in_reply_to_id)) || nil,
      replies_count: Map.get(post, :replies_count) || Map.get(item, :replies_count) || 0,
      muted: Map.get(post, :muted) || Map.get(item, :muted) || false,
      sensitive: Map.get(post, :sensitive) || false,
      spoiler_text: Map.get(post, :spoiler_text) || "",
      mentions: serialize_mentions(Map.get(post, :mentions)),
      tags: serialize_tags(Map.get(post, :hashtags)),
      language: Map.get(post, :language) || "english",
      emojis: Map.get(post, :emojis) || [],
      created_at: Calendar.strftime(post.inserted_at, "%Y-%m-%dT%H:%M:%SZ"),
      edited_at:
        (post.edited_at && Calendar.strftime(post.edited_at, "%Y-%m-%dT%H:%M:%SZ")) || nil,
      edit_count: Map.get(post, :edit_count) || 0,
      is_edited: (post.edit_count || 0) > 0,
      visibility: Map.get(post, :visibility) || "public",
      reblog: serialize_reblog(Map.get(post, :reblog_of))
    }
  end

  defp serialize_author(%Ecto.Association.NotLoaded{}), do: nil
  defp serialize_author(nil), do: nil

  defp serialize_author(author) do
    %{
      id: to_string(Map.get(author, :id)),
      username: Map.get(author, :username),
      avatar_url: Map.get(author, :avatar_url) || "/default-avatar.jpg"
    }
  end

  defp serialize_organization(%Ecto.Association.NotLoaded{}), do: nil
  defp serialize_organization(nil), do: nil

  defp serialize_organization(org) do
    %{
      id: to_string(Map.get(org, :id)),
      username: Map.get(org, :username),
      display_name: Map.get(org, :display_name),
      avatar_url: Map.get(org, :avatar_url) || "/default-avatar.jpg"
    }
  end

  defp serialize_reblog(%Ecto.Association.NotLoaded{}), do: nil
  defp serialize_reblog(nil), do: nil

  defp serialize_reblog(reblog_post) do
    reblog_post =
      Kollective.Repo.preload(reblog_post, [:author, :attachments, :hashtags, poll: :options])

    KollectiveWeb.PostJSON.show(reblog_post)
  end

  defp serialize_tags(%Ecto.Association.NotLoaded{}), do: []
  defp serialize_tags(nil), do: []

  defp serialize_tags(hashtags) when is_list(hashtags) do
    Enum.map(hashtags, fn tag ->
      %{
        name: tag.name,
        url: "#{KollectiveWeb.Endpoint.url()}/tag/#{URI.encode(tag.name)}"
      }
    end)
  end

  defp serialize_mentions(nil), do: []

  defp serialize_mentions(mentions) when is_list(mentions) do
    Enum.map(mentions, fn mention ->
      %{
        id: to_string(Map.get(mention, :id) || Map.get(mention, "id")),
        username: Map.get(mention, :username) || Map.get(mention, "username")
      }
    end)
  end

  # Safe preloading fallback checker blocks
  defp serialize_poll(%Ecto.Association.NotLoaded{}), do: nil
  defp serialize_poll(nil), do: nil

  defp serialize_poll(poll) do
    poll = Kollective.Repo.preload(poll, :options)
    KollectiveWeb.PollJSON.data(poll)
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
