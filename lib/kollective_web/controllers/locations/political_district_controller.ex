# lib/kollective_web/controllers/locations/political_district_controller.ex
defmodule KollectiveWeb.PoliticalDistrictController do
  use KollectiveWeb, :controller
  alias Kollective.Locations.Locations
  alias Kollective.Posts.Posts
  alias KollectiveWeb.PoliticalDistrictJSON

  # /api/districts/:id/news
  def news(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user
    scope = Map.get(params, "scope", "local")

    district = Locations.get_district_with_hierarchy!(id)

    # The preloads are now handled inside these functions
    page =
      case scope do
        "local" -> Posts.list_local_feed(user, conn.params)
        "state" -> Posts.list_state_feed(user, conn.params)
        "country" -> Posts.list_country_feed(user, conn.params)
        "world" -> Posts.list_world_feed(user, conn.params)
        # Default safe fallback
        _ -> Posts.list_country_feed(user, params)
      end

    # Update timestamp silently whenever they fetch the first page
    # You can call it automatically inside your news controller action. Every time a user requests
    # their "Local" or "State" feed, the backend assumes they have "read" it and updates the timestamp.
    if params["page"] == "1" or is_nil(params["page"]) do
      Kollective.Accounts.Users.mark_feed_as_read(user)
    end

    data =
      PoliticalDistrictJSON.news(%{
        district: district,
        district_id: id,
        posts: page.entries,
        meta: page,
        scope: scope,
        # Pass this so PostJSON can use it
        current_user: user
      })

    conn
    |> put_status(:ok)
    |> json(data)
  end
end
