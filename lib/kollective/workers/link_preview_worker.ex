# lib/kollective/workers/link_preview_worker.ex
defmodule Kollective.Workers.LinkPreviewWorker do
  use Oban.Worker, queue: :media, max_attempts: 4

  import Ecto.Query
  alias Kollective.Repo
  # Adjust to match your application namespace
  alias Kollective.Posts.Post

  @http_client Application.compile_env(:kollective, :http_client, Kollective.HTTPClient.Impl)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"post_id" => post_id, "url" => url}}) do
    case @http_client.get(url,
           headers: [{"user-agent", "KollectiveBot/1.0"}],
           retry: false,
           timeout: 5000
         ) do
      {:ok, %Req.Response{status: 200, body: html_body}} ->
        {:ok, document} = Floki.parse_document(html_body)

        title =
          extract_og_tag(document, "og:title") || extract_text_tag(document, "title") ||
            "Link Overview"

        description =
          extract_og_tag(document, "og:description") || extract_meta_description(document) || ""

        preview_image = extract_og_tag(document, "og:image") || ""

        # Update the main row caches safely
        from(p in Post, where: p.id == ^post_id)
        |> Repo.update_all(
          set: [
            link_title: String.slice(title, 0, 255),
            link_description: String.slice(description, 0, 500),
            link_preview_image: preview_image
          ]
        )

        # Broadcast the real-time card over the websocket engine
        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          "timeline:global",
          {:link_preview_ready,
           %{
             post_id: post_id,
             link_title: title,
             link_description: description,
             link_preview_image: preview_image
           }}
        )

        :ok

      {:ok, %Req.Response{status: status}} ->
        # Don't retry client errors like 404 or 403, just discard them
        if status in 400..499, do: :ok, else: {:error, "HTTP Status #{status}"}

      {:error, reason} ->
        # Trigger an Oban retry for network failures or timeouts
        {:error, reason}
    end
  end

  # Helper functions to extract metadata fields from HTML using Floki
  defp extract_og_tag(doc, property) do
    doc
    |> Floki.find("meta[property=\"#{property}\"]")
    |> Floki.attribute("content")
    |> List.first()
  end

  defp extract_text_tag(doc, selector) do
    doc
    |> Floki.find(selector)
    |> Floki.text()
  end

  defp extract_meta_description(doc) do
    doc
    |> Floki.find("meta[name=\"description\"]")
    |> Floki.attribute("content")
    |> List.first()
  end
end
