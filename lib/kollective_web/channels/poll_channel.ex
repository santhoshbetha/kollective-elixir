defmodule KollectiveWeb.PollChannel do
  use KollectiveWeb, :channel
  alias Kollective.Polls.Polls

  @impl true
  def join("poll:" <> poll_id, _payload, socket) do
    {:ok, assign(socket, :poll_id, poll_id)}
  end

  @impl true
  # 🟢 EXPECTS AN ARRAY/LIST OF IDS FROM REACT: %{"option_ids" =>}
  def handle_in("submit_vote", %{"option_ids" => option_ids}, socket) when is_list(option_ids) do
    poll_id = socket.assigns.poll_id
    user_id = socket.assigns.user_id

    case Polls.cast_votes(user_id, poll_id, option_ids) do
      {:ok, :voted} ->
        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{message: to_string(reason)}}, socket}
    end
  end
end
