defmodule Kollective.Workers.JournalistCronOrchestrator do
  use Oban.Worker, queue: :default

  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Accounts.User
  alias Kollective.Workers.AuditJournalistLinks

  @impl Oban.Worker
  def perform(_job) do
    query = from(u in User, where: u.badge_type == "ProfessionalTeal", select: u.id)

    Repo.all(query)
    |> Enum.each(fn journalist_id ->
      %{user_id: journalist_id}
      |> AuditJournalistLinks.new()
      |> Oban.insert()
    end)

    :ok
  end
end
