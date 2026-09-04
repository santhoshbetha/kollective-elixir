# This worker calls an AI API. Sightengine is highly recommended for its simplicity and 99% accuracy.

defmodule Kollective.Workers.ImageModerationWorker do
  use Oban.Worker, queue: :moderation

  alias Kollective.Repo
  alias Kollective.Events.Comment

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"comment_id" => id, "image_url" => url}}) do
    # 1. Call AI API (Example using Sightengine)
    case call_moderation_api(url) do
      {:ok, %{status: "success", nudity: nudity}} when nudity > 0.95 ->
        reject_image(id)

      {:ok, _} ->
        approve_image(id)

      {:error, _} ->
        # Retry logic is built into Oban
        {:error, "API connection failed"}
    end
  end

  defp call_moderation_api(url) do
    # You can use HTTPoison or Req to call the API
    # e.g., https://api.sightengine.com
    case Req.get(url) do
      {:ok, response} -> Jason.decode(response.body)
      {:error, reason} -> {:error, reason}
    end
  end

  defp approve_image(id) do
    comment =
      Repo.get!(Comment, id)
      |> Ecto.Changeset.change(moderation_status: "approved")
      |> Repo.update!()

    # Broadcast to the channel so the UI unblurs the image
    # 🟢 FIXED: Scope the broadcast string dynamically by room/event topic structure
    KollectiveWeb.Endpoint.broadcast("event_chat:#{comment.event_id}", "image_moderated", %{
      id: id,
      status: "approved"
    })
  end

  defp reject_image(id) do
    comment =
      Repo.get!(Comment, id)
      |> Ecto.Changeset.change(moderation_status: "rejected")
      |> Repo.update!()

    # Broadcast to the channel so the UI can hide the image
    KollectiveWeb.Endpoint.broadcast("event_chat:#{comment.event_id}", "image_moderated", %{
      id: id,
      status: "rejected"
    })
  end
end
