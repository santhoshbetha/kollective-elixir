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
  generators: [
    timestamp_type: :utc_datetime,
    binary_id: true,
    #
    sample_binary_id: "01H2E3456789ABCDEFGHJKMNPQ"
  ]

config :kollective, :http_client, Kollective.HTTPClient.Impl

# to ensure binary_id is used by default in all your schemas
config :kollective, Kollective.Repo,
  migration_primary_key: [name: :id, type: :binary_id, autogenerate: false],
  migration_foreign_key: [type: :binary_id]

config :geo, :ecto_repos, [Kollective.Repo]

config :kollective, Oban,
  repo: Kollective.Repo,
  queues: [
    default: 10,
    maintenance: 5,
    # 🔔 High-concurrency queue tailored for mass voice broadcasts & alerts
    notifications: [limit: 50],
    media_processing: 10
  ],
  plugins: [
    # 1. Essential: Cleans up Oban's own internal job history (keeping 24h of data)
    # Recommended: cleans up Oban's own job table
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24},
    # 2. Cron: Manages your custom recurring tasks
    {Oban.Plugins.Cron,
     crontab: [
       {"*/15 * * * *", Kollective.Workers.TrendCalculatorWorker},
       # Existing: Check for expired Voice/Urgent posts every minute
       {"* * * * *", Kollective.Workers.MentionNotificationWorker},
       # Sync official bot IPs daily at 01:00 AM
       {"0 1 * * *", Kollective.Workers.VideoTranscoder},
       # {"0 1 * * *", Kollective.Workers.BotIPSyncWorker}
       # Runs at exactly 02:00 every single night
       {"0 2 * * *", Kollective.Workers.ReconcileCountersWorker},
       # Evaluates database checks every single midnight automatically
       # {"0 0 * * *", Kollective.Workers.ScholarCronOrchestrator},
       # Runs automatically at 12:05 AM every single night
       # {"5 0 * * *", Kollective.Workers.OrganizationProbationWorker},
       # {"0 0 * * *", Kollective.Workers.JournalistCronOrchestrator},

       # Runs every night at midnight to delete expired, unconsumed rows
       {"0 0 * * *", Kollective.Workers.DailyPrunerWorker}

       # Runs your out-of-band counter cache repair every Sunday at midnight smoothly
       # {"0 0 * * 0", Kollective.Workers.RepairCountsWorker}
     ]}
  ]

# Configures the endpoint
config :kollective, KollectiveWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: KollectiveWeb.ErrorJSON],
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
config :kollective, Kollective.OrganizationMailer, adapter: Swoosh.Adapters.Local
config :joken, default_signer: "kollective_jwt_token_signing_secret_key_minimum_32_bytes"

# -------------------------------------------------------------------
# Application Architecture Bridge (Application Layer)
# -------------------------------------------------------------------
# Registers which structural module handles your global app calls
# Configures your application's internal wrapper module (Kollective.External.GeospatialService).
# Instructs this wrapper to route its global requests to the Nominatim provider.
config :kollective, Kollective.External.GeospatialService, service: Geospatial.Providers.Nominatim

# Creates an application-wide shortcut atom (:geospatial_client).
# Allows you to call Application.get_env(:kollective, :geospatial_client) in the code to fetch the service module dynamically.
# This is useful for making your code more flexible and easier to test.
# This makes it easy to swap out the geospatial service during tests.
config :kollective, :geospatial_client, Kollective.External.GeospatialService

# -------------------------------------------------------------------
# Third-Party Library Configuration
# -------------------------------------------------------------------
# Configures the third-party Hex provider library explicitly
# Configures an external dependency library named :geospatial
# Explicitly tells that library's core system to use Nominatim as its active engine.
config :geospatial, Geospatial.Service, service: Geospatial.Providers.Nominatim

# Sets the specific connection details for the Nominatim provider.
# Nominatim provides open-source geocoding services based on OpenStreetMap data.
config :geospatial, Geospatial.Providers.Nominatim,
  endpoint: "https://nominatim.openstreetmap.org",
  api_key: nil

# -------------------------------------------------------------------
# A custom HTTP configuration for Nominatim requests
# -------------------------------------------------------------------
config :geospatial, Geospatial.HTTP,
  user_agent: fn -> "KollectivePoliticalPlatform/1.0 (admin@kollective.app)" end

# Configures global network headers enforced system-wide by the geospatial runtime
config :geospatial, :headers, [
  {"user-agent", "KollectivePoliticalPlatform/1.0 (admin@kollective.app)"},
  {"accept-language", "en"}
]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
