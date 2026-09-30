defmodule Kollective.Workers.UserMediaOptimizer do
  use Oban.Worker, queue: :media, max_attempts: 3

  import Ecto.Query
  alias Kollective.Repo
  # Adjust namespace to match your local account files directory
  alias Kollective.Accounts.User

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => id, "asset_type" => "avatar"}}) do
    user = Repo.get!(User, id)
    process_avatar(user)
  end

  def perform(%Oban.Job{args: %{"user_id" => id, "asset_type" => "cover"}}) do
    user = Repo.get!(User, id)
    process_cover(user)
  end

  # ─── AVATAR COMPRESSION PROCESSING SUITE ───
  defp process_avatar(%User{avatar_url: url} = user) when url in [nil, "", "/default-avatar.jpg"],
    do: :ok

  defp process_avatar(%User{avatar_url: input_url} = user) do
    optimized_path = "/tmp/avatar_opt_\#{user.id}.jpg"

    try do
      with {:ok, %{status: 200, body: raw_bytes}} <- Req.get(input_url),
           :ok <- File.write(optimized_path, raw_bytes),
           :ok <- compress_avatar_file(optimized_path),
           {:ok, processed_filename} <-
             Kollective.Media.UserAvatar.store(
               {%{path: optimized_path, filename: "avatar.jpg"}, user}
             ) do
        final_cdn_url = Kollective.Media.UserAvatar.url({processed_filename, user}, :original)

        user
        |> Ecto.Changeset.change(%{avatar_url: final_cdn_url})
        |> Repo.update()

        :ok
      else
        error -> {:error, "Avatar asset compression exception: \#{inspect(error)}"}
      end
    after
      File.rm(optimized_path)
    end
  end

  # ─── COVER BANNER COMPRESSION PROCESSING SUITE ───
  defp process_cover(%User{cover_image_url: url} = user)
       when url in [nil, "", "/default-banner-bg.jpg"],
       do: :ok

  defp process_cover(%User{cover_image_url: input_url} = user) do
    optimized_path = "/tmp/cover_opt_\#{user.id}.jpg"

    try do
      with {:ok, %{status: 200, body: raw_bytes}} <- Req.get(input_url),
           :ok <- File.write(optimized_path, raw_bytes),
           :ok <- compress_cover_file(optimized_path),
           {:ok, processed_filename} <-
             Kollective.Media.UserCover.store(
               {%{path: optimized_path, filename: "cover.jpg"}, user}
             ) do
        final_cdn_url = Kollective.Media.UserCover.url({processed_filename, user}, :original)

        user
        |> Ecto.Changeset.change(%{cover_image_url: final_cdn_url})
        |> Repo.update()

        :ok
      else
        error -> {:error, "Cover asset compression exception: \#{inspect(error)}"}
      end
    after
      File.rm(optimized_path)
    end
  end

  # ⚙️ ImageMagick Transformation Call Loops
  defp compress_avatar_file(path) do
    try do
      import Mogrify

      open(path)
      |> resize_to_limit("400x400^")
      |> custom("gravity", "center")
      |> custom("extent", "400x400")
      |> custom("interlace", "plane")
      |> custom("strip")
      |> quality(86)
      |> save(in_place: true)

      :ok
    rescue
      err -> {:error, err}
    end
  end

  defp compress_cover_file(path) do
    try do
      import Mogrify

      open(path)
      |> resize_to_limit("1200x400>")
      |> custom("interlace", "plane")
      |> custom("strip")
      |> quality(82)
      |> save(in_place: true)

      :ok
    rescue
      err -> {:error, err}
    end
  end
end
