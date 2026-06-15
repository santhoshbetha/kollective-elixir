defmodule KollectiveWeb.PoliticalDistrictJSON do
  alias Kollective.Posts.Posts

  def news(%{posts: posts, meta: meta, scope: scope, current_user: current_user}) do
    %{
      data: %{
        scope: scope,
        # Pass current_user here so we can check 'has_reposted'
        posts: for(post <- posts, do: KollectiveWeb.PostJSON.data(post, current_user)),
        pagination: %{
          current_page: meta.page_number,
          total_pages: meta.total_pages
        },

        # UNREAD BADGES FOR REACT TABS
        badges: %{
          local: Posts.has_unread_posts?(current_user, :local),
          state: Posts.has_unread_posts?(current_user, :state),
          country: Posts.has_unread_posts?(current_user, :country),
          world: Posts.has_unread_posts?(current_user, :world)
        }
      }
    }
  end

  # Recursive district formatter for breadcrumbs
  def data(nil), do: nil
  def data(district) do
    %{
      id: district.id,
      name: district.name,
      level: district.level,
      parent: data(district.parent)
    }
  end
end
