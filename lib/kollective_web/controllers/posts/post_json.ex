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
      likes_count: Map.get(post, :likes_count) || 0,
      reblogs_count: Map.get(post, :reblogs_count) || 0,
      replies_count: Map.get(post, :replies_count) || 0,
      has_liked: Map.get(post, :liked, false) || Map.get(post, :has_liked, false) || false,
      has_reblogged:
        Map.get(post, :reblogged, false) || Map.get(post, :has_reblogged, false) || false
    })
  end

  def show(item) do
    render_item(item)
  end

  @doc "Alias for show/1 to maintain uniformity across JSON serializers."
  def data(item), do: show(item)

  defp extract_first_integer(list) do
    Enum.find_value(list, nil, fn val ->
      if is_integer(val) and val >= 0, do: val, else: nil
    end) || 0
  end

  defp extract_first_boolean(list) do
    Enum.find_value(list, false, fn val ->
      if is_boolean(val), do: val, else: nil
    end)
  end

  defp render_item(item) do
    post = (is_map(item) && Map.get(item, :post)) || item
    base_domain = KollectiveWeb.Endpoint.url()
    computed_permalink = "#{base_domain}/posts/#{to_string(post.id)}"

    attachments = Map.get(post, :attachments)

    # 🚀 REFACTOR: Build rich object models for the images list loop to feed TimelineImagePlayer
    rich_image_objects =
      if is_list(attachments) and Ecto.assoc_loaded?(attachments) do
        Enum.map(attachments, fn att ->
          %{
            id: to_string(att.id),
            url: att.url,
            # Fallback to base url if background static png worker is still in progress
            static_url: Map.get(att, :static_url) || att.url,
            blurhash: Map.get(att, :blurhash) || "",
            description: Map.get(att, :description) || "",
            imageMeta: Map.get(att, :description) || post.text || "Timeline attachment asset node"
          }
        end)
      else
        []
      end

    # Legacy array string fallback list to prevent un-migrated client elements from breaking
    legacy_image_string_urls = Enum.map(rich_image_objects, & &1.url)

    likes_cnt =
      extract_first_integer([
        Map.get(item, :likes_count),
        Map.get(item, :likes),
        Map.get(post, :likes_count),
        Map.get(post, :likes)
      ])

    reblogs_cnt =
      extract_first_integer([
        Map.get(item, :reblogs_count),
        Map.get(item, :reblogsCount),
        Map.get(item, :reblogs),
        Map.get(post, :reblogs_count),
        Map.get(post, :shares)
      ])

    replies_cnt =
      extract_first_integer([
        Map.get(item, :replies_count),
        Map.get(item, :commentsCount),
        Map.get(post, :replies_count),
        Map.get(post, :commentsCount)
      ])

    has_liked =
      extract_first_boolean([
        Map.get(item, :has_liked),
        Map.get(item, :liked),
        Map.get(post, :has_liked),
        Map.get(post, :liked)
      ])

    has_reblogged =
      extract_first_boolean([
        Map.get(item, :has_reblogged),
        Map.get(item, :reblogged),
        Map.get(post, :has_reblogged),
        Map.get(post, :reblogged)
      ])

    bookmarked_val =
      extract_first_boolean([
        Map.get(item, :bookmarked),
        Map.get(item, :isBookmarked),
        Map.get(post, :bookmarked),
        Map.get(post, :isBookmarked)
      ])

    %{
      id: to_string(post.id),
      content: post.content,
      text: post.text || post.content,
      title: Map.get(post, :summary) || Map.get(post, :spoiler_text) || nil,
      category: Map.get(post, :category),
      inserted_at: Calendar.strftime(post.inserted_at, "%Y-%m-%dT%H:%M:%SZ"),
      published_at:
        (Map.get(post, :published_at) &&
           Calendar.strftime(post.published_at, "%Y-%m-%dT%H:%M:%SZ")) || nil,
      time: Calendar.strftime(post.inserted_at, "%b %d, %Y"),
      permalink: computed_permalink,
      likes: likes_cnt,
      likes_count: likes_cnt,
      reblogs_count: reblogs_cnt,
      reblogsCount: reblogs_cnt,
      shares: reblogs_cnt,
      commentsCount: replies_cnt,
      replies_count: replies_cnt,
      repliesCount: replies_cnt,
      liked: has_liked,
      has_liked: has_liked,
      has_reblogged: has_reblogged,
      bookmarked: bookmarked_val,
      favourited: Map.get(post, :favourited, false),
      reblogged: has_reblogged,
      vote_data: post.vote_data,
      my_reactions: Map.get(post.data || %{}, "my_reactions", []),
      author: serialize_author(Map.get(post, :author)),
      organization_id: (post.organization_id && to_string(post.organization_id)) || nil,
      organization: serialize_organization(Map.get(post, :organization)),

      # 📸 NEW & UPDATED INTERFACE BINDINGS
      # Now returns full, feature-rich object collections!
      images: rich_image_objects,
      image: List.first(rich_image_objects),
      legacy_images_fallback: legacy_image_string_urls,
      media_attachments: serialize_attachments(attachments),
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
      poll: serialize_poll(Map.get(post, :poll)),
      in_reply_to_id: (post.in_reply_to_id && to_string(post.in_reply_to_id)) || nil,
      in_reply_to_account_id: (post.in_reply_to_id && to_string(post.in_reply_to_id)) || nil,
      in_reply_to_username: Map.get(post, :in_reply_to_username),
      root_post_id: (post.root_post_id && to_string(post.root_post_id)) || nil,
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
    username = Map.get(author, :username) || Map.get(author, :name) || "user"

    handle =
      cond do
        Map.get(author, :handle) -> author.handle
        String.starts_with?(username, "@") -> username
        true -> "@#{username}"
      end

    name =
      Map.get(author, :display_name) || Map.get(author, :name) || Map.get(author, :username) ||
        "Anonymous"

    avatar = Map.get(author, :avatar) || Map.get(author, :avatar_url) || "/default-avatar.jpg"
    type = to_string(Map.get(author, :type) || "personal")

    %{
      id: to_string(Map.get(author, :id)),
      name: name,
      username: username,
      handle: handle,
      avatar: avatar,
      avatar_url: avatar,
      type: type,
      verified: Map.get(author, :is_verified) || Map.get(author, :verified) || false
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

  defp serialize_reblog(%Kollective.Posts.Post{} = reblog_post) do
    reblog_post =
      if Ecto.assoc_loaded?(reblog_post.author) do
        reblog_post
      else
        Kollective.Repo.preload(reblog_post, [:author, :attachments, :hashtags, poll: :options])
      end

    reblog_data = show(reblog_post)
    Map.put(reblog_data, :reblog, nil)
  end

  defp serialize_reblog(_), do: nil

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

  defp serialize_poll(%Ecto.Association.NotLoaded{}), do: nil
  defp serialize_poll(nil), do: nil

  defp serialize_poll(poll) do
    poll = Kollective.Repo.preload(poll, :options)
    KollectiveWeb.PollJSON.data(poll)
  end

  defp serialize_attachments(%Ecto.Association.NotLoaded{}), do: []
  defp serialize_attachments(nil), do: []

  defp serialize_attachments(attachments) do
    Enum.map(attachments, fn att ->
      %{
        id: to_string(att.id),
        url: att.url,
        description: Map.get(att, :description) || "",
        # 🚀 ADD NEW PROCESSING TELEMETRY FIELDS DYNAMICALLY
        static_url: Map.get(att, :static_url) || att.url,
        type:
          if(String.starts_with?(att.media_type || "image", "video"), do: "video", else: "image"),
        blurhash: att.blurhash || ""
      }
    end)
  end
end
