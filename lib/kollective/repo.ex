defmodule Kollective.Repo do
  use Ecto.Repo,
    otp_app: :kollective,
    adapter: Ecto.Adapters.Postgres
end
