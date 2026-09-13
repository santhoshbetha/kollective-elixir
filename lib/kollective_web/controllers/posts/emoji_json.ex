# lib/kollective_web/controllers/posts/emoji_json.ex
defmodule KollectiveWeb.EmojiJSON do
  @moduledoc """
  Unified JSON serializer for Platform Custom Emojis and categorized palettes.
  """

  @doc """
  Formats emojis grouped cleanly by category.
  """
  def grouped(emojis) when is_list(emojis) do
    grouped_categories =
      emojis
      |> Enum.group_by(
        fn emoji -> Map.get(emoji, :category) || "Custom" end,
        &data/1
      )

    %{
      status: "success",
      categories: grouped_categories
    }
  end

  @doc """
  Serializes a list of emoji entities.
  """
  def index(%{emojis: emojis}), do: index(emojis)

  def index(emojis) when is_list(emojis) do
    Enum.map(emojis, &data/1)
  end

  @doc """
  Serializes an individual emoji record or map.
  """
  def data(emoji) do
    url = Map.get(emoji, :url)

    %{
      shortcode: Map.get(emoji, :shortcode),
      url: url,
      static_url: Map.get(emoji, :static_url) || url
    }
  end
end
