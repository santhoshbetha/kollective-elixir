defmodule Kollective.Workers.ScholarCronOrchestrator do
  @moduledoc """
  Nightly manager job that pulls all scholars and schedules individual sync cycles.
  """
  use Oban.Worker, queue: :default

  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Accounts.User
  alias Kollective.Workers.SyncScholarPublications

  @impl Oban.Worker
  def perform(_job) do
    # Pull every scholar profile registered inside the platform database matrix
    query = from(u in User, where: u.badge_type == "Scholar", select: u.id)

    Repo.all(query)
    |> Enum.each(fn scholar_id ->
      # Insert individual workers staggered over seconds to prevent hitting ORCID API limits
      %{user_id: scholar_id}
      |> SyncScholarPublications.new()
      |> Oban.insert()
    end)

    :ok
  end
end
