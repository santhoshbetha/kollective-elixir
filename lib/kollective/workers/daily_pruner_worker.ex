defmodule Kollective.Workers.DailyPrunerWorker do
  use Oban.Worker, queue: :default
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Civic.TokenSchema

  @impl Oban.Worker
  def perform(_job) do
    # Clear tokens where expires_at is older than right now
    from(t in TokenSchema, where: t.expires_at < ^DateTime.utc_now())
    |> Repo.delete_all()

    :ok
  end
end
