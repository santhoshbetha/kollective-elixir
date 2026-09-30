import Config

# Production environment ensures Oban runs at maximum optimization limits
config :kollective, Oban,
  repo: Kollective.Repo,
  queues: [
    default: 20,
    maintenance: 10,
    # Mass real-time notifications allocation thread limit
    notifications: [limit: 100],
    # 📸 Panoramic banner worker thread processing limit
    media: [limit: 20]
  ]

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
