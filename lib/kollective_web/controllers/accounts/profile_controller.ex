defmodule KollectiveWeb.ProfileController do
  use KollectiveWeb, :controller
  alias Kollective.Accounts.Accounts

  @bucket_name "your-r2-profiles-bucket"
  # Replace with your custom domain or pub.r2.dev link
  @cdn_domain "https://r2.dev"

  # ─── ACTION 1: GENERATE PROFILE ASSET PRESIGNED TICKETS ───
  # GET /api/v1/profile/media/presign
  # Expected params: ?filename=avatar.png&type=avatar&content_type=image/png
  def presign_asset(conn, %{
        "filename" => filename,
        "type" => type,
        "content_type" => content_type
      })
      when type in ["avatar", "cover"] do
    user = conn.assigns.current_user
    config = ExAws.Config.new(:s3)

    # Scoped file mapping path strategy: profiles/USER_ID/type/timestamp_filename.ext
    cleaned_ext = Path.extname(filename) |> String.downcase()
    unique_name = "profile_#{System.system_time(:second)}#{cleaned_ext}"
    s3_path = "profiles/#{user.id}/#{type}/#{unique_name}"

    # Hand out a highly restrictive 15-minute write ticket straight to R2 edge pools
    {:ok, upload_url} =
      ExAws.S3.presigned_url(config, :put, @bucket_name, s3_path,
        expires_in: 900,
        query_params: [{"Content-Type", content_type}]
      )

    json(conn, %{
      status: "success",
      upload_url: upload_url,
      final_asset_url: "#{@cdn_domain}/#{s3_path}"
    })
  end

  def presign_asset(conn, _),
    do: conn |> put_status(:bad_request) |> json(%{error: "Invalid asset type parameters."})

  # ─── ACTION 2: MUTATE PROFILE PROPERTIES ───
  # PUT /api/v1/profile
  # Expected payload: %{"user" => %{"avatar_url" => "https://...", "bio" => "Hello!"}}
  def update(conn, %{"user" => user_params}) do
    user = conn.assigns.current_user

    case Accounts.update_user_profile(user, user_params) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        # Modern Phoenix 1.7 standard: Format response payload via uniform AccountJSON views
        |> json(%{
          status: "success",
          message: "Profile graphics updated successfully.",
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
end
