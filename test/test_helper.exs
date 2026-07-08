# 1. Force your application supervisor tree (and Kollective.Repo) to start first
{:ok, _} = Application.ensure_all_started(:kollective)

# 2. Initialize the test framework execution tracker
ExUnit.start()

# 3. Safely switch your active, running repository pool over to manual Sandbox mode
Ecto.Adapters.SQL.Sandbox.mode(Kollective.Repo, :manual)
