# lib/kollective_web/controllers/trending_json.ex
defmodule KollectiveWeb.TrendingController do
  use KollectiveWeb, :controller
  alias Kollective.Hashtags.Hashtags

  def index(conn, _params) do
    tags = Hashtags.list_trending_tags(10)
    json(conn, %{data: tags})
  end
end
