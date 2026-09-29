defmodule KollectiveWeb.ProfileController do
  use KollectiveWeb, :controller
  alias Kollective.Accounts.Accounts

  # ─── ACTION 1: GENERATE PROFILE ASSET PRESIGNED TICKETS ───
  # GET /api/v1/profile/media/presign
  # Expected params: ?filename=avatar.png&type=avatar&content_type=image/png
  def presign_asset(
        conn,
        %{
          "filename" => filename,
          "type" => type
        } = params
      )
      when type in ["avatar", "cover", "banner", "header"] do
    user = conn.assigns.current_user
    content_type = Map.get(params, "content_type", "image/jpeg")
    config = ExAws.Config.new(:s3)

    cleaned_ext = Path.extname(filename) |> String.downcase()
    cleaned_ext = if cleaned_ext == "", do: ".jpg", else: cleaned_ext
    unique_name = "profile_#{System.system_time(:second)}#{cleaned_ext}"
    s3_path = "profiles/#{user.id}/#{type}/#{unique_name}"

    case ExAws.S3.presigned_url(config, :put, Kollective.Storage.bucket_name(), s3_path,
           expires_in: 900,
           query_params: [{"Content-Type", content_type}]
         ) do
      {:ok, upload_url} ->
        json(conn, %{
          status: "success",
          upload_url: upload_url,
          final_asset_url: "#{Kollective.Storage.cdn_domain()}/#{s3_path}"
        })

      _ ->
        final_url = "#{Kollective.Storage.cdn_domain()}/#{s3_path}"

        json(conn, %{
          status: "success",
          upload_url: final_url,
          final_asset_url: final_url
        })
    end
  end

  def presign_asset(conn, _),
    do: conn |> put_status(:bad_request) |> json(%{error: "Invalid asset type parameters."})

  # ─── ACTION 2: MUTATE PROFILE PROPERTIES ───
  # PUT /api/v1/profile
  # Expected payload: %{"user" => %{"avatar_url" => "https://...", "bio" => "Hello!"}} or top-level params
  def update(conn, params) do
    user = conn.assigns.current_user
    user_params = Map.get(params, "user", params)

    case Accounts.update_user_profile(user, user_params) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Profile graphics updated successfully.",
          user: KollectiveWeb.AccountJSON.profile_data(updated_user),
          data: KollectiveWeb.AccountJSON.show(%{user: updated_user, for: updated_user})
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          status: "error",
          message: "Profile update failed.",
          errors: KollectiveWeb.ChangesetJSON.error(changeset)
        })
    end
  end

  # GET /api/v1/accounts/:username_or_id
  def show(conn, %{"username_or_id" => username_or_id}) do
    current_user = conn.assigns[:current_user]

    # Call your newly optimized single-pass query look-up engine
    case Accounts.get_user_profile(username_or_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "User profile not found."})

      user_profile ->
        conn
        |> put_status(:ok)
        # Modern Phoenix 1.7 standard: Pass data straight to your AccountJSON
        |> json(%{
          status: "success",
          data:
            KollectiveWeb.AccountJSON.show(%{
              user: user_profile,
              for: current_user
            })
        })
    end
  end

  @doc """
  GET /api/v1/accounts/:username_or_id/posts
  Returns timeline posts published by or on behalf of the requested account handle/ULID.
  """
  def user_posts(conn, %{"username_or_id" => username_or_id} = params) do
    current_user = conn.assigns[:current_user]

    case Accounts.get_user_profile(username_or_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "Account profile not found."})

      target_user ->
        %{entries: entries, next_cursor: next_cursor} =
          Kollective.Posts.Posts.list_user_posts(target_user, current_user, params)

        serialized = KollectiveWeb.PostJSON.index(%{entries: entries})

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          data: serialized,
          posts: serialized,
          next_cursor: next_cursor
        })
    end
  end

  @doc """
  GET /api/v1/accounts/:username_or_id/followers
  Returns a paginated list of accounts following the requested user handle/ULID.
  """
  def followers(conn, %{"username_or_id" => username_or_id} = params) do
    current_user = conn.assigns[:current_user]

    case Accounts.get_user_profile(username_or_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "Account profile not found."})

      target_user ->
        %{entries: users, next_cursor: next_cursor} =
          Accounts.list_followers(target_user, params)

        serialized = KollectiveWeb.AccountJSON.index(%{users: users, for: current_user})

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          data: serialized,
          accounts: serialized,
          users: serialized,
          next_cursor: next_cursor
        })
    end
  end

  @doc """
  GET /api/v1/accounts/:username_or_id/following
  Returns a paginated list of accounts that the requested user handle/ULID is following.
  """
  def following(conn, %{"username_or_id" => username_or_id} = params) do
    current_user = conn.assigns[:current_user]

    case Accounts.get_user_profile(username_or_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "Account profile not found."})

      target_user ->
        %{entries: users, next_cursor: next_cursor} =
          Accounts.list_following(target_user, params)

        serialized = KollectiveWeb.AccountJSON.index(%{users: users, for: current_user})

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          data: serialized,
          accounts: serialized,
          users: serialized,
          next_cursor: next_cursor
        })
    end
  end

  @doc """
  GET /api/v1/profile/authorized_organizations
  Exposes all organization profiles the authenticated viewer has permission to act/post as.
  Feeds the identity toggle select dropdown row inside the React post composer .
  """
  def list_authorized_organizations(conn, _params) do
    # Read the verified account profile straight out of RAM memory
    user = conn.assigns.current_user

    # Call your context module layer function explicitly
    authorized_orgs = Accounts.list_authorized_organizations(user.id)

    conn
    |> put_status(:ok)
    # Modern Warning-Free Alternative: Serialize directly to json/2
    |> json(%{
      status: "success",
      data:
        Enum.map(authorized_orgs, fn org ->
          %{
            id: to_string(org.id),
            username: org.username,
            badge_type: org[:badge_type] || org["badge_type"] || "none"
          }
        end)
    })
  end

  @doc """
  Returns all profiles (the personal account + all active orgs) the logged-in user can access.
  Useful for rendering your navbar switcher dropdown on initial app load.
  """
  def index_profiles(conn, _params) do
    user =
      conn.assigns[:current_user] ||
        (conn.assigns[:current_scope] && conn.assigns.current_scope.user)

    profiles = Accounts.list_user_profiles(user)

    json(conn, %{
      status: "success",
      profiles: profiles,
      data: %{profiles: profiles}
    })
  end
end
