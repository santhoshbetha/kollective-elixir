defmodule KollectiveWeb.PreviewCardController do
  use KollectiveWeb, :controller

  def fetch(conn, params) do
    url = params["url"] || params[:url]

    case validate_url(url) do
      {:ok, uri} ->
        domain = uri.host

        case Req.get(url,
               headers: [{"user-agent", "KollectiveBot/1.0 (OpenGraph Live Crawler; +https://kollective.social)"}],
               retry: false,
               receive_timeout: 4000
             ) do
          {:ok, %Req.Response{status: status, body: html_body}}
          when status in 200..299 and is_binary(html_body) ->
            case Floki.parse_document(html_body) do
              {:ok, doc} ->
                title =
                  extract_og_tag(doc, "og:title") ||
                    extract_text_tag(doc, "title") ||
                    extract_meta_tag(doc, "twitter:title") ||
                    domain

                description =
                  extract_og_tag(doc, "og:description") ||
                    extract_meta_description(doc) ||
                    extract_meta_tag(doc, "twitter:description") ||
                    ""

                image_url =
                  extract_og_tag(doc, "og:image") ||
                    extract_meta_tag(doc, "twitter:image") ||
                    ""

                card = %{
                  id: "card-#{System.unique_integer([:positive])}",
                  title: String.trim(to_string(title || "")),
                  description: String.trim(to_string(description || "")),
                  image_url: String.trim(to_string(image_url || "")),
                  domain: domain,
                  url: url
                }

                conn
                |> put_status(:ok)
                |> json(%{
                  preview_card: card,
                  title: card.title,
                  description: card.description,
                  image_url: card.image_url,
                  domain: card.domain,
                  url: card.url
                })

              _ ->
                render_fallback(conn, url, domain)
            end

          _ ->
            render_fallback(conn, url, domain)
        end

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: reason})
    end
  end

  defp validate_url(url) when is_binary(url) do
    uri = URI.parse(String.trim(url))

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" do
      {:ok, uri}
    else
      {:error, "Invalid scheme or host. Only http and https URLs are supported."}
    end
  end

  defp validate_url(_), do: {:error, "Missing or invalid URL parameter."}

  defp render_fallback(conn, url, domain) do
    card = %{
      id: "card-#{System.unique_integer([:positive])}",
      title: domain,
      description: "",
      image_url: "",
      domain: domain,
      url: url
    }

    conn
    |> put_status(:ok)
    |> json(%{
      preview_card: card,
      title: card.title,
      description: card.description,
      image_url: card.image_url,
      domain: card.domain,
      url: card.url
    })
  end

  defp extract_og_tag(doc, property) do
    doc
    |> Floki.find("meta[property=\"#{property}\"]")
    |> Floki.attribute("content")
    |> List.first()
  end

  defp extract_meta_tag(doc, name) do
    doc
    |> Floki.find("meta[name=\"#{name}\"]")
    |> Floki.attribute("content")
    |> List.first()
  end

  defp extract_text_tag(doc, selector) do
    case Floki.find(doc, selector) do
      [] -> nil
      elements -> Floki.text(elements)
    end
  end

  defp extract_meta_description(doc) do
    extract_meta_tag(doc, "description")
  end
end

