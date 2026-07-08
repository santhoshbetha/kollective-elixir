# lib/kollective_web/views/filter_json.ex
defmodule KollectiveWeb.FilterJSON do
  def index(%{filters: filters}), do: Enum.map(filters, &data/1)
  def show(%{filter: filter}), do: data(filter)

  def data(filter) do
    %{
      id: to_string(filter.id),
      phrase: filter.phrase,
      whole_word: filter.whole_word,
      context: filter.context,
      expires_at:
        if(filter.expires_at,
          do: Calendar.strftime(filter.expires_at, "%Y-%m-%dT%H:%M:%SZ"),
          else: nil
        )
    }
  end
end
