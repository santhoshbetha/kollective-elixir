# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :kollective, :scopes,
  user: [
    default: true,
    module: Kollective.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Kollective.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :kollective,
  ecto_repos: [Kollective.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :geo, :ecto_repos, [Kollective.Repo]

# to ensure binary_id is used by default in all your schemas
config :kollective, Kollective.Repo,
  migration_primary_key: [name: :id, type: :binary_id, autogenerate: false],
  migration_foreign_key: [type: :binary_id]

config :kollective, Oban,
  repo: Kollective.Repo,
  queues: [default: 10, maintenance: 5],
  plugins: [
    # 1. Essential: Cleans up Oban's own internal job history (keeping 24h of data)
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24}, # Recommended: cleans up Oban's own job table
    # 2. Cron: Manages your custom recurring tasks
    {Oban.Plugins.Cron,
     crontab: [
        {"*/15 * * * *", Kollective.Workers.TrendCalculatorWorker},
        # Existing: Check for expired Voice/Urgent posts every minute
        {"* * * * *", Kollective.Workers.MentionNotificationWorker},
        # Sync official bot IPs daily at 01:00 AM
        {"0 1 * * *", Kollective.Workers.VideoTranscoder},
        #{"0 1 * * *", Kollective.Workers.BotIPSyncWorker}
     ]}
  ]

# Configures the endpoint
config :kollective, KollectiveWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: KollectiveWeb.ErrorHTML, json: KollectiveWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Kollective.PubSub

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :kollective, Kollective.Mailer, adapter: Swoosh.Adapters.Local

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
