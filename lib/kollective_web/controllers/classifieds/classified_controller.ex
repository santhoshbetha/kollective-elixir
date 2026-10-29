defmodule KollectiveWeb.ClassifiedController do
  use KollectiveWeb, :controller

  alias Kollective.Classifieds.Classifieds
  alias Kollective.Classifieds.Classified
  alias KollectiveWeb.ClassifiedJSON

  action_fallback KollectiveWeb.FallbackController

  @doc """
  GET /api/v1/classifieds (also /classifieds)
  Lists active classified ads with optional search and category filters.
  """
  def index(conn, params) do
    user =
      conn.assigns[:current_user] ||
        (conn.assigns[:current_scope] && conn.assigns.current_scope.user)

    org_id =
      conn.assigns[:current_org_id] ||
        (conn.assigns[:current_organization] && conn.assigns[:current_organization].id)

    params =
      cond do
        Map.has_key?(params, "context") ->
          params

        conn.assigns[:account_type] in [:organization, "organization"] and not is_nil(org_id) ->
          params
          |> Map.put("context", "organization")
          |> Map.put("organization_id", to_string(org_id))

        true ->
          params
      end

    classifieds = Classifieds.list_classifieds(params, user)
    json(conn, ClassifiedJSON.index(%{classifieds: classifieds}))
  end

  @doc """
  GET /api/v1/classifieds/:id
  Retrieves single classified ad details.
  """
  def show(conn, %{"id" => id}) do
    case Classifieds.get_classified(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "Classified ad not found."})

      %Classified{} = classified ->
        json(conn, ClassifiedJSON.show(%{classified: classified}))
    end
  end

  @doc """
  POST /api/v1/classifieds (also /classifieds)
  Creates a new classified ad for the authenticated user.
  Accepts either %{"classified" => params} or flat params map.
  """
  def create(conn, params) do
    user =
      conn.assigns[:current_user] ||
        (conn.assigns[:current_scope] && conn.assigns.current_scope.user)

    if is_nil(user) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "unauthorized", message: "You must log in to post an ad."})
    else
      classified_params =
        params
        |> Map.get("classified", params)
        |> Map.put_new("email", user.email)

      org_id =
        conn.assigns[:current_org_id] ||
          (conn.assigns[:current_organization] && conn.assigns[:current_organization].id) ||
          (conn.assigns[:account_type] in [:organization, "organization"] && conn.assigns[:active_account_id])

      classified_params =
        cond do
          org_id && org_id not in ["personal", "usr-1", ""] ->
            Map.put(classified_params, "organization_id", to_string(org_id))

          true ->
            classified_params
        end

      case Classifieds.create_classified(user, classified_params) do
        {:ok, classified} ->
          rendered = ClassifiedJSON.data(classified)

          conn
          |> put_status(:created)
          # Merge both top-level keys for React's direct response unpacking and data wrapper
          |> json(Map.merge(rendered, %{status: "success", data: rendered, classified: rendered}))

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))
      end
    end
  end

  @doc """
  DELETE /api/v1/classifieds/:id
  Deletes an ad if the user is the author or a platform admin.
  """
  def delete(conn, %{"id" => id}) do
    user =
      conn.assigns[:current_user] ||
        (conn.assigns[:current_scope] && conn.assigns.current_scope.user)

    if is_nil(user) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "unauthorized", message: "You must log in to delete an ad."})
    else
      case Classifieds.get_classified(id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "not_found", message: "Classified ad not found."})

        %Classified{} = classified ->
          is_owner = to_string(classified.user_id) == to_string(user.id)
          is_admin = user.role in [:admin, "admin"]

          if is_owner or is_admin do
            case Classifieds.delete_classified(classified) do
              {:ok, _} ->
                json(conn, %{status: "success", message: "Classified ad deleted successfully."})

              {:error, changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "forbidden", message: "You are not authorized to delete this ad."})
          end
      end
    end
  end
end
