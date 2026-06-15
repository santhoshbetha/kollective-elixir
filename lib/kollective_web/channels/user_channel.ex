# Real-time Delivery (Phoenix Channels)
# Unlike public feeds, DMs use a Personal Control Channel for each user.

defmodule KollectiveWeb.UserChannel do
  use KollectiveWeb, :channel

  def join("user:" <> user_id, _payload, socket) do
    if socket.assigns.user_id == String.to_integer(user_id) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_in("send_dm", %{"recipient_id" => rid, "blob" => blob}, socket) do
    # 1. Save the encrypted blob to the database
    # 2. Push to the recipient's private topic
    KollectiveWeb.Endpoint.broadcast("user:#{rid}", "new_dm", %{
      from: socket.assigns.user_id,
      blob: blob
    })
    {:reply, :ok, socket}
  end

end
