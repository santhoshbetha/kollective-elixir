defmodule KollectiveWeb.BusinessSearchController do
  use KollectiveWeb, :controller

  alias Kollective.Businesses.SearchEngine
  alias KollectiveWeb.BusinessJSON

  @doc """
  GET /api/v1/businesses/search
  Maps incoming query maps into your geospatial query processor loops.
  Supports: ?q=cafe&category=food_beverage&north=30.5&south=30.2&east=-97.6&west=-97.9
  """
  def index(conn, params) do
    # Run the filters against your optimized database engine index layers
    matched_businesses = SearchEngine.search_businesses(params)

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      count: Enum.count(matched_businesses),
      # Leverages your BusinessJSON index block to attach processed images, tags, and coordinates
      data: BusinessJSON.index(matched_businesses)
    })
  end
end
