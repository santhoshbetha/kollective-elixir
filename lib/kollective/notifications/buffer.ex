defmodule Kollective.Notifications.Buffer do
  use GenServer
  alias KollectiveWeb.Endpoint

  # Client API
  def enqueue(user_id, type, target_id) do
    GenServer.cast(__MODULE__, {:enqueue, user_id, type, target_id})
  end

  # Server Callbacks
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(_), do: {:ok, %{}}

  def handle_cast({:enqueue, user_id, type, target_id}, state) do
    key = {user_id, type, target_id}

    # If we aren't already tracking this specific event, start a timer
    new_state = if Map.has_key?(state, key) do
      # Increment the count for this group
      Map.update!(state, key, fn {count, timer} -> {count + 1, timer} end)
    else
      # Start a 5-second window
      timer = Process.send_after(self(), {:flush, key}, 5000)
      Map.put(state, key, {1, timer})
    end

    {:noreply, new_state}
  end

  def handle_info({:flush, key = {user_id, type, target_id}}, state) do
    {count, _timer} = Map.get(state, key)

    # ONE BROADCAST for the whole group
    Endpoint.broadcast("notifications:#{user_id}", "notifications_grouped", %{
      type: type,
      target_id: target_id,
      count: count
    })

    {:noreply, Map.delete(state, key)}
  end
end
