defmodule KollectiveWeb.PoliticalDistrictJSON do
  alias Kollective.Locations.PoliticalDistrict
  alias Kollective.Posts.Posts
  alias Kollective.Repo
  alias KollectiveWeb.PostJSON

  @doc """
  Renders the district news feed with posts, pagination, and unread badges.
  """
  def news(
        %{
          posts: posts,
          meta: meta,
          scope: scope,
          current_user: current_user
        } = assigns
      ) do
    district =
      case Map.get(assigns, :district) do
        nil ->
          case Map.get(assigns, :district_id) do
            nil ->
              nil

            id ->
              case Repo.get(PoliticalDistrict, id) do
                nil -> nil
                d -> Repo.preload(d, parent: :parent)
              end
          end

        d ->
          d
      end

    %{
      data: %{
        district: data(district),
        scope: scope,
        # Pass current_user here so we can check 'has_reposted'
        posts: for(post <- posts, do: PostJSON.show(post)),
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

  @doc """
  Renders a single political district.
  """
  def show(%{district: district}) do
    %{data: data(district)}
  end

  def show(district) do
    %{data: data(district)}
  end

  @doc """
  Renders a list of political districts.
  """
  def index(%{districts: districts}) do
    %{data: for(d <- districts, do: data(d))}
  end

  def index(districts) when is_list(districts) do
    %{data: for(d <- districts, do: data(d))}
  end

  # Recursive district formatter for breadcrumbs
  def data(%Ecto.Association.NotLoaded{}), do: nil
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
