defmodule Kollective.Repo do
  use Ecto.Repo,
    otp_app: :kollective,
    adapter: Ecto.Adapters.Postgres,
    types: Kollective.PostgrexTypes

  use Scrivener, page_size: 10
end
