defmodule Kollective.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      KollectiveWeb.Telemetry,
      Kollective.Repo,

      # Cachex handles the token cache from the vouch system, which is used for secure token-based authentication.
      {Cachex, name: :vouch_secure_tokens},
      {Phoenix.PubSub, name: Kollective.PubSub},

      # Oban automatically picks up your Buffer module configurations when it boots!
      {Oban, Application.fetch_env!(:kollective, Oban)},

      # Start the Phoenix Presence supervisor tracking pool
      # Presence supervisor must boot right after PubSub servers mount
      KollectiveWeb.Presence,

      # Boots up your ultra-fast in-memory flags cache engine [1.4]
      Kollective.Admin.FeatureFlags,
      {DNSCluster, query: Application.get_env(:kollective, :dns_cluster_query) || :ignore},

      # 🛡️ THE CACHEX FIREWALL BUCKET:
      # Configures an in-memory cache explicitly for IP blacklisting
      # 🛡️ 2. THE BLACKLIST FIREWALL CACHE (FIXED FOR CACHEX v3.4)
      # We define a custom worker map to safely override the process ID
      # and force the supervisor to invoke start_link/2 cleanly
      %{
        id: :kollective_cache_worker,
        start:
          {Cachex, :start_link, [:kollective_cache, [janitor: [interval: :timer.minutes(5)]]]},
        type: :worker
      },

      # Start a worker by calling: Kollective.Worker.start_link(arg)
      # {Kollective.Worker, arg},
      # Start to serve requests, typically the last entry
      KollectiveWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Kollective.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    KollectiveWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
