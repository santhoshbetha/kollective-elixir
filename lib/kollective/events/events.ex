defmodule Kollective.Events.Events do
  import Ecto.Query, warn: false
  alias Kollective.Repo
  alias Kollective.Events.Event

  def get_event_with_hierarchy!(id) do
    Event
    |> Repo.get!(id)
    |> Repo.preload([
      :user,
      # This preloads the local district, its parent, and its grandparent
      # Get the "stack" (State Senate District → State District→ National District)
      # Preloading parent (L2) and grandparent (L1)
      # Walking up the tree: L3 -> L2 -> L1
      origin_district: [parent: :parent]
    ])
  end

  def list_events_with_hierarchy do
    Event
    |> Repo.all()
    |> Repo.preload([
      :user,
      # This preloads the local district, its parent, and its grandparent
      # Get the "stack" (State Senate District → State District→ National District)
      # Preloading parent (L2) and grandparent (L1)
      # Walking up the tree: L3 -> L2 -> L1
      district: [parent: :parent]
    ])
  end


 # def list_events_in_state_hierarchy(state_id) do
end
