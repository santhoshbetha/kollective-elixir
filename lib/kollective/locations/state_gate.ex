# lib/kollective/locations/state_gate.ex
defmodule Kollective.Locations.StateGate do
  @moduledoc """
  Server-side state boundary enforcement for localized discussion channels.

  A discussion thread belongs to a physical state (the proposal's `state` column
  or the event's `origin_state`). Only verified residents of that state may read
  or write inside it.

  Semantics:
    * records with **no** recorded state are treated as ungated (there is no
      boundary to enforce),
    * records **with** a state require the actor to expose the same 2-letter
      state code (case/whitespace insensitive).
  """

  @doc """
  Normalizes any state input ("tx", " TX ", "Texas") into a comparable token.

  Full state names are intentionally not expanded here — the API persists 2-letter
  codes — but whitespace/case differences are folded so `" tx "` == `"TX"`.
  """
  def normalize(nil), do: nil

  def normalize(state) when is_binary(state) do
    cleaned =
      state
      |> String.trim()
      |> String.upcase()

    case cleaned do
      "" -> nil
      value -> value
    end
  end

  def normalize(_), do: nil

  @doc """
  Returns true when `actor_state` is allowed through a boundary declared as
  `target_state`.
  """
  def resident?(target_state, actor_state) do
    case normalize(target_state) do
      nil ->
        # No declared boundary → nothing to geofence.
        true

      target ->
        normalize(actor_state) == target
    end
  end

  @doc """
  Convenience inverse used by controllers/JSON renderers.
  """
  def locked?(target_state, actor_state), do: not resident?(target_state, actor_state)

  @doc """
  Message surfaced to clients when the boundary blocks a request.
  """
  def locked_message, do: "Discussion locked to local state residents"
end
