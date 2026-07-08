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
      KollectiveWeb.Presence,
      {DNSCluster, query: Application.get_env(:kollective, :dns_cluster_query) || :ignore},

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
