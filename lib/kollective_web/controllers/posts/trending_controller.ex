# lib/kollective_web/controllers/posts/trending_controller.ex
defmodule KollectiveWeb.TrendingController do
  use KollectiveWeb, :controller
  alias Kollective.Hashtags.Hashtags
  alias KollectiveWeb.HashtagJSON

  # GET /api/v1/trending/tags
  def index(conn, _params) do
    tags = Hashtags.list_trending_tags(10)

    conn
    |> put_status(:ok)
    |> json(HashtagJSON.trending(tags))
  end
end
