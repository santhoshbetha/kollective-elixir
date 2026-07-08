# lib/kollective_web/controllers/political_district_controller.ex
defmodule KollectiveWeb.PoliticalDistrictController do
  use KollectiveWeb, :controller
  alias Kollective.Posts.Posts

  # /api/districts/:id/news
  def news(conn, %{"id" => id, "scope" => scope} = params) do
    user = conn.assigns.current_user

    # The preloads are now handled inside these functions
    page =
      case scope do
        "local" -> Posts.list_local_feed(user, conn.params)
        "state" -> Posts.list_state_feed(user, conn.params)
        "country" -> Posts.list_country_feed(user, conn.params)
        "world" -> Posts.list_world_feed(user, conn.params)
        _ -> Posts.list_local_feed(user, conn.params)
      end

    # Update timestamp silently whenever they fetch the first page
    # You can call it automatically inside your news controller action. Every time a user requests
    # their "Local" or "State" feed, the backend assumes they have "read" it and updates the timestamp.
    if params["page"] == "1" or is_nil(params["page"]) do
      Kollective.Accounts.Users.mark_feed_as_read(user)
    end

    render(conn, :news,
      posts: page.entries,
      meta: page,
      # Pass this so PostJSON can use it
      current_user: user,
      district_id: id,
      scope: scope
    )
  end
end
