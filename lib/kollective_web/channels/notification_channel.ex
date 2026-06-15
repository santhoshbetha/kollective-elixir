defmodule KollectiveWeb.NotificationChannel do
  use KollectiveWeb, :channel

  def join("notifications:" <> user_id, _params, socket) do
    if socket.assigns.user_id == user_id do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end


end
