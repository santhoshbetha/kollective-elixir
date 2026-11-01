defmodule KollectiveWeb.ProfileController do
  use KollectiveWeb, :controller
  alias Kollective.Accounts.Accounts

  @s3_engine Application.compile_env(:kollective, :s3_engine, ExAws.S3)

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
      when type in ["avatar", "cover", "banner", "header", "event", "business"] do
    user = conn.assigns.current_user
    content_type = Map.get(params, "content_type", "image/jpeg")

    cleaned_ext = Path.extname(filename) |> String.downcase()
    cleaned_ext = if cleaned_ext == "", do: ".jpg", else: cleaned_ext
    unique_name = "profile_#{System.system_time(:second)}_#{System.unique_integer([:positive])}#{cleaned_ext}"
    relative_path = "profiles/#{user.id}/#{type}/#{unique_name}"
    file_key = Kollective.Storage.object_key(relative_path)

    upload_url =
      cond do
        Mix.env() == :e2e ->
          "/media/#{file_key}"

        @s3_engine != ExAws.S3 ->
          case @s3_engine.presigned_url(s3_config(), :put, Kollective.Storage.bucket_name(), file_key,
                 expires_in: 900,
                 query_params: [{"Content-Type", content_type}]
               ) do
            {:ok, url} -> url
            _ -> "/media/#{file_key}"
          end

        has_r2_credentials?() ->
          case @s3_engine.presigned_url(s3_config(), :put, Kollective.Storage.bucket_name(), file_key,
                 expires_in: 900,
                 query_params: [{"Content-Type", content_type}]
               ) do
            {:ok, url} -> url
            _ -> "/media/#{file_key}"
          end

        true ->
          "/media/#{file_key}"
      end

    final_asset_url = "#{Kollective.Storage.cdn_domain()}/#{file_key}"

    json(conn, %{
      status: "success",
      upload_url: upload_url,
      final_asset_url: final_asset_url
    })
  end

  def presign_asset(conn, _),
    do: conn |> put_status(:bad_request) |> json(%{error: "Invalid asset type parameters."})

  defp has_r2_credentials? do
    key = System.get_env("R2_ACCESS_KEY_ID") || Application.get_env(:ex_aws, :access_key_id)
    secret = System.get_env("R2_SECRET_ACCESS_KEY") || Application.get_env(:ex_aws, :secret_access_key)
    is_binary(key) and key != "" and is_binary(secret) and secret != ""
  end

  defp s3_config do
    if @s3_engine == ExAws.S3 do
      ExAws.Config.new(:s3)
    else
      %{}
    end
  end

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
        if current_user && Accounts.blocks?(user_profile, current_user) do
          conn
          |> put_status(:forbidden)
          |> json(%{
            error: "blocked",
            message: "You are blocked from viewing this resource."
          })
        else
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
        if current_user && Accounts.blocks?(target_user, current_user) do
          conn
          |> put_status(:forbidden)
          |> json(%{
            error: "blocked",
            message: "You are blocked from viewing this resource."
          })
        else
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
        if current_user && Accounts.blocks?(target_user, current_user) do
          conn
          |> put_status(:forbidden)
          |> json(%{
            error: "blocked",
            message: "You are blocked from viewing this resource."
          })
        else
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
        if current_user && Accounts.blocks?(target_user, current_user) do
          conn
          |> put_status(:forbidden)
          |> json(%{
            error: "blocked",
            message: "You are blocked from viewing this resource."
          })
        else
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
