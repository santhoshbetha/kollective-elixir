defmodule KollectiveWeb.CityController do
  use KollectiveWeb, :controller
  import Ecto.Query
  alias Kollective.{Repo, Locations.City}

  # GET /api/cities/search?q=Aus&country=US
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

    json(conn, %{
      data:
        Enum.map(cities, fn c ->
          %{id: c.id, name: "#{c.name}, #{c.state}", lat: c.latitude, lon: c.longitude}
        end)
    })
  end
end
