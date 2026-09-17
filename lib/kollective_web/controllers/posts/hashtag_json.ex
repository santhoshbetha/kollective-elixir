# lib/kollective_web/controllers/posts/hashtag_json.ex
defmodule KollectiveWeb.HashtagJSON do
  @moduledoc """
  Unified JSON serializer for Hashtags, Trending Topics, and Tag Timelines.
  """

  alias KollectiveWeb.PostJSON

  @doc """
  Serializes trending hashtag tags.
  """
  def trending(tags) when is_list(tags) do
    %{data: Enum.map(tags, &tag_data/1)}
  end

  @doc """
  Serializes a single hashtag entity.
  """
  def tag_data(tag) do
    %{
      id: to_string(Map.get(tag, :id)),
      name: Map.get(tag, :name),
      score: Map.get(tag, :score) || Map.get(tag, :trending_score) || 0
    }
  end

  @doc """
  Serializes a single tag object with follow state.
  """
  def show(tag_name, following) when is_binary(tag_name) do
    base_url = KollectiveWeb.Endpoint.url()

    %{
      name: tag_name,
      url: "#{base_url}/api/discovery/hashtag?tag=#{tag_name}",
      history: [],
      following: following
    }
  end

  @doc """
  Serializes a list of followed tags.
  """
  def list_followed(tag_names) when is_list(tag_names) do
    Enum.map(tag_names, fn name -> show(name, true) end)
  end

  @doc """
  Formats hashtag discovery timeline payload.
  """
  def timeline(tag_name, entries, next_cursor) do
    %{
      status: "success",
      tag: String.downcase(String.trim(tag_name)),
      data: PostJSON.index(%{entries: entries}),
      next_cursor: next_cursor
    }
  end

  @doc """
  Formats missing tag parameter validation error.
  """
  def missing_tag_error do
    %{
      status: "error",
      code: "missing_tag_parameter",
      message: "You must provide a valid 'tag' parameter inside the URL query string parameters."
    }
  end
end
