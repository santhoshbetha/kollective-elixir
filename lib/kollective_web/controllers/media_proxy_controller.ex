# lib/kollective_web/controllers/media_proxy_controller.ex
defmodule KollectiveWeb.MediaProxyController do
  use KollectiveWeb, :controller

  @doc """
  Accepts raw binary media uploads (e.g., from browser direct-to-proxy PUTs)
  and persists them in the static media storage directory under the given key.
  Also syncs the binary to Cloudflare R2 if credentials are configured.
  """
  def upload(conn, %{"path" => path_parts}) do
    key = Enum.join(path_parts, "/")
    clean_key = key |> String.trim_leading("/") |> String.replace("..", "")

    priv_path = get_storage_path(clean_key)
    source_path = Path.expand("priv/static/media/#{clean_key}")

    File.mkdir_p!(Path.dirname(priv_path))
    File.mkdir_p!(Path.dirname(source_path))

    case read_full_body(conn, "") do
      {:ok, body, conn} ->
        File.write!(priv_path, body)

        try do
          {:ok, img} = Image.open(priv_path)
          {:ok, oriented} = Image.auto_orient(img)
          {:ok, optimized} = Image.minimize_metadata(oriented)
          {:ok, thumbnail} = Image.thumbnail(optimized, 2048)
          Image.write(thumbnail, priv_path, quality: 85)
        rescue
          _ -> :ok
        end

        final_body = File.read!(priv_path)

        if priv_path != source_path do
          File.write!(source_path, final_body)
        end

        maybe_upload_to_r2(clean_key, final_body)

        conn
        |> put_status(:ok)
        |> json(%{status: "ok", key: key, size: byte_size(final_body)})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to read body: #{inspect(reason)}"})
    end
  end

  @doc """
  Serves media files directly by relative path. If the file is not on local
  disk, attempts to fetch and cache it from Cloudflare R2 before responding.
  """
  def serve(conn, %{"path" => path_parts}) do
    key = Enum.join(path_parts, "/")
    clean_key = key |> String.trim_leading("/") |> String.replace("..", "")

    case find_existing_file(clean_key) do
      storage_path when is_binary(storage_path) ->
        content_type = MIME.from_path(storage_path)

        conn
        |> put_resp_content_type(content_type)
        |> send_file(200, storage_path)

      nil ->
        if Mix.env() != :test and has_r2_credentials?() do
          bucket = Kollective.Storage.bucket_name()

          case ExAws.S3.get_object(bucket, clean_key) |> ExAws.request() do
            {:ok, %{body: r2_body}} ->
              storage_path = get_storage_path(clean_key)
              File.mkdir_p!(Path.dirname(storage_path))
              File.write!(storage_path, r2_body)
              content_type = MIME.from_path(clean_key)

              conn
              |> put_resp_content_type(content_type)
              |> send_resp(200, r2_body)

            _ ->
              conn
              |> put_status(:not_found)
              |> json(%{error: "Media not found"})
          end
        else
          conn
          |> put_status(:not_found)
          |> json(%{error: "Media not found"})
        end
    end
  end

  defp read_full_body(conn, acc) do
    case Plug.Conn.read_body(conn, length: 1_000_000) do
      {:ok, body, conn} -> {:ok, acc <> body, conn}
      {:more, partial, conn} -> read_full_body(conn, acc <> partial)
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_existing_file(clean_key) do
    priv_path = get_storage_path(clean_key)
    source_path = Path.expand("priv/static/media/#{clean_key}")

    cond do
      File.exists?(priv_path) -> priv_path
      File.exists?(source_path) -> source_path
      true -> nil
    end
  end

  defp get_storage_path(clean_key) do
    priv_dir =
      case :code.priv_dir(:kollective) do
        {:error, :bad_name} -> Path.expand("priv")
        path when is_list(path) -> List.to_string(path)
        path -> path
      end

    base_dir = Path.join([priv_dir, "static", "media"])
    Path.join(base_dir, clean_key)
  end

  defp maybe_upload_to_r2(key, body) do
    if Mix.env() != :test and has_r2_credentials?() do
      bucket = Kollective.Storage.bucket_name()
      content_type = MIME.from_path(key)

      ExAws.S3.put_object(bucket, key, body, content_type: content_type)
      |> ExAws.request()
      |> case do
        {:ok, _} ->
          :ok

        {:error, err} ->
          require Logger
          Logger.warning("MediaProxy: failed to upload to R2 [#{key}]: #{inspect(err)}")
          {:error, err}
      end
    else
      :ok
    end
  end

  defp has_r2_credentials? do
    key = System.get_env("R2_ACCESS_KEY_ID") || Application.get_env(:ex_aws, :access_key_id)
    secret = System.get_env("R2_SECRET_ACCESS_KEY") || Application.get_env(:ex_aws, :secret_access_key)
    is_binary(key) and key != "" and is_binary(secret) and secret != ""
  end
end
