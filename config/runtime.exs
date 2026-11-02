import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/kollective start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :kollective, KollectiveWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :kollective, Kollective.Repo,
    # ssl: true,
    url: database_url,
    # High pool_size to prevent worker starvation under heavy alert fan-outs
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "50"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6,
    types: Kollective.PostgrexTypes

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :kollective, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :kollective, KollectiveWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port,
      thousand_island_options: [silent_terminate_on_error: true]
    ],
    secret_key_base: secret_key_base

  r2_account_id = System.get_env("R2_ACCOUNT_ID") || "47701ef2e87f29505064cb21fd2513ed"
  r2_bucket = System.get_env("R2_BUCKET_NAME") || "kollective"

  # Public base for serving media to browsers. Default to the same-origin
  # /media proxy (MediaProxyController), which streams objects from R2
  # server-side. The raw *.r2.cloudflarestorage.com URL is the S3 API endpoint
  # (requires auth headers) and is NOT a public CDN, so it must never be used
  # as an <img src> default. Set R2_PUBLIC_DOMAIN to a real public CDN/custom
  # domain (e.g. an r2.dev URL) only when one is configured.
  r2_public_domain = System.get_env("R2_PUBLIC_DOMAIN") || "/media"

  config :ex_aws,
    access_key_id: System.get_env("R2_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("R2_SECRET_ACCESS_KEY"),
    region: "auto"

  config :ex_aws, :s3,
    host: "#{r2_account_id}.r2.cloudflarestorage.com",
    access_key_id: System.get_env("R2_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("R2_SECRET_ACCESS_KEY"),
    scheme: "https://",
    region: "auto"

  config :waffle,
    storage: Waffle.Storage.S3,
    bucket: r2_bucket

  config :kollective,
    r2_account_id: r2_account_id,
    r2_bucket: r2_bucket,
    r2_public_domain: r2_public_domain

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :kollective, KollectiveWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :kollective, KollectiveWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :kollective, Kollective.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end

if config_env() == :test do
  # 1. Keep it on ETS mode during local test suite runs
  config :hammer,
    backend:
      {Hammer.Backend.ETS,
       [
         expiry_ms: 600_000,
         cleanup_interval_ms: 60_000
       ]}
else
  # 2. Only activate Redis during Development (:dev) or Production (:prod)
  config :hammer,
    backend:
      {Hammer.Backend.Redis,
       [
         expiry_ms: 60_000,
         redis_url: System.get_env("REDIS_URL") || "redis://localhost:6379"
       ]}
end

# ## Dynamic Multi-Node Libcluster Topologies
# Configures the clustering strategy dynamically from environment variables:
# - "epmd" / "nodes" / "static": for multi-region VPS, fixed IPs, or WireGuard/Tailscale VPN mesh
# - "dns": for Docker Compose, Kubernetes, Fly.io, or AWS ECS headless services
# - "kubernetes": for native Kubernetes API pod discovery
# - "gossip": for local LAN / bare-metal hardware clusters (default in dev)
# - "none" / "disabled": disable clustering
if config_env() not in [:test, :e2e] do
  cluster_strategy =
    System.get_env("CLUSTER_STRATEGY") || if config_env() == :prod, do: "dns", else: "gossip"

  topologies =
    case String.downcase(cluster_strategy) do
      "dns" ->
        dns_query =
          System.get_env("CLUSTER_DNS_QUERY") || System.get_env("DNS_CLUSTER_QUERY") ||
            "kollective.internal"

        node_basename = System.get_env("CLUSTER_NODE_BASENAME") || "kollective"
        poll_interval = String.to_integer(System.get_env("CLUSTER_POLL_INTERVAL") || "5000")

        [
          kollective_mesh: [
            strategy: Cluster.Strategy.DNSPoll,
            config: [
              polling_interval: poll_interval,
              query: dns_query,
              node_basename: node_basename
            ]
          ]
        ]

      strategy when strategy in ["epmd", "nodes", "static"] ->
        raw_hosts = System.get_env("CLUSTER_NODES") || ""

        hosts =
          raw_hosts
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(&String.to_atom/1)

        [
          kollective_mesh: [
            strategy: Cluster.Strategy.Epmd,
            config: [hosts: hosts]
          ]
        ]

      "kubernetes" ->
        [
          kollective_mesh: [
            strategy: Cluster.Strategy.Kubernetes,
            config: [
              mode: :dns,
              kubernetes_node_basename: System.get_env("CLUSTER_NODE_BASENAME") || "kollective",
              kubernetes_selector: System.get_env("CLUSTER_K8S_SELECTOR") || "app=kollective"
            ]
          ]
        ]

      strategy when strategy in ["none", "disabled"] ->
        []

      _gossip ->
        port = String.to_integer(System.get_env("CLUSTER_PORT") || "45892")
        secret = System.get_env("CLUSTER_SECRET") || "kollective_secure_mesh_handshake_salt_2026"

        multicast_addr =
          case System.get_env("CLUSTER_MULTICAST_ADDR") do
            nil ->
              {230, 1, 1, 251}

            addr_str ->
              case :inet.parse_address(String.to_charlist(addr_str)) do
                {:ok, ip} -> ip
                _ -> {230, 1, 1, 251}
              end
          end

        [
          kollective_mesh: [
            strategy: Cluster.Strategy.Gossip,
            config: [
              port: port,
              if_addr: {0, 0, 0, 0},
              multicast_addr: multicast_addr,
              secret: secret
            ]
          ]
        ]
    end

  config :libcluster, topologies: topologies
end
