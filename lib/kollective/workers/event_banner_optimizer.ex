defmodule Kollective.Workers.EventBannerOptimizer do
  use Oban.Worker, queue: :media, max_attempts: 3

  alias Kollective.Repo
  alias Kollective.Events.Event

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => id}}) do
    event = Repo.get!(Event, id)
    input_url = extract_url(event.banner_url)

    case input_url do
      nil ->
        :ok

      "" ->
        :ok

      url ->
        optimized_path = "/tmp/optimized_event_#{id}.jpg"

        try do
          with {:ok, %{status: 200, body: raw_bytes}} <- Req.get(url),
               :ok <- File.write(optimized_path, raw_bytes),
               :ok <- compress_banner_image(optimized_path),
               {:ok, processed_filename} <-
                 Kollective.Media.EventBanner.store(
                   {%{path: optimized_path, filename: "banner.jpg"}, event}
                 ) do
            final_cdn_url =
              Kollective.Media.EventBanner.url({processed_filename, event}, :original)

            event
            |> Ecto.Changeset.change(%{banner_url: final_cdn_url, is_banner_processed: true})
            |> Repo.update()

            :ok
          else
            error ->
              {:error, "Event banner compression transactional loop exception: #{inspect(error)}"}
          end
        after
          File.rm(optimized_path)
        end
    end
  end

  defp extract_url(%{file_name: url}) when is_binary(url), do: url
  defp extract_url(%{"file_name" => url}) when is_binary(url), do: url
  defp extract_url(url) when is_binary(url), do: url
  defp extract_url(_), do: nil

  defp compress_banner_image(path) do
    try do
      import Mogrify

      open(path)
      |> resize_to_limit("1500x500>")
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
