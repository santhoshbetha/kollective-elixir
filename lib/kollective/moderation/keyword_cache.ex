# Caching with Agent or ETS
# list_active_keyword_strings is called every time a post is created, hitting the database repeatedly
# can be slow. You can wrap this in a simple Agent to keep the list in memory:
defmodule Kollective.Moderation.KeywordCache do
  use Agent

  def start_link(_) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  def get_keywords do
    # If empty, load from DB; otherwise return state
    case Agent.get(__MODULE__, & &1) do
      [] ->
        keywords = Kollective.Moderation.Moderation.list_active_keyword_strings()
        Agent.update(__MODULE__, fn _ -> keywords end)
        keywords

      keywords ->
        keywords
    end
  end

  def invalidate do
    Agent.update(__MODULE__, fn _ -> [] end)
  end
end
