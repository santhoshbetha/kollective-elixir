defmodule KollectiveWeb.CityController do
  use KollectiveWeb, :controller
  import Ecto.Query
  alias Kollective.{Locations.City, Repo}
  alias KollectiveWeb.LocationJSON

  # GET /api/v1/cities/search?q=Aus&country=US
  def search(conn, %{"q" => query, "country" => country}) do
    # Prefix matching allows index use
    search_term = "#{query}%"

    cities =
      City
      |> where([c], c.country == ^country)
      |> where([c], ilike(c.name, ^search_term))
      |> order_by([c], asc: c.name)
      |> limit(10)
      |> Repo.all()

    conn
    |> put_status(:ok)
    |> json(LocationJSON.cities(cities))
  end
end
