import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :pbkdf2_elixir, :rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :kollective, Kollective.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "kollective_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  types: Kollective.PostgrexTypes

# config/test.exs
config :kollective, :media_uploader, Kollective.EventsMock

# config/test.exs
config :ex_aws,
  json_codec: Jason,
  # Prevents real AWS connection loops during tests
  http_client: ExAws.Request.HttpMock,
  access_key_id: "mock_key",
  secret_access_key: "mock_secret"

# ⚡ FIXED: Route S3 calculations straight to our static test harness module
config :kollective, :s3_engine, KollectiveWeb.S3Mock

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :kollective, KollectiveWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "/cXcHps34v0nW3z9IepcsxY86dwRWhl+spzLQ3Z38sEnmA5F/+q7GOHiVuov63J7",
  server: false

config :kollective, Oban,
  repo: Kollective.Repo,
  # Turns off the background engine queues
  queues: false,
  # Run jobs immediately inline during tests if needed
  testing: :manual,
  # 👈 Turn off all cron plugins/pruners for testing
  plugins: false

config :kollective, :http_client, Kollective.HTTPClientMock

# Configure Hammer rate limiter for the test environment
# Format for Hammer v6+
config :hammer,
  backend:
    {Hammer.Backend.ETS,
     [
       expiry_ms: 600_000,
       cleanup_interval_ms: 60_000
     ]}

# In test we don't send emails
# Use Swoosh's Test adapter to capture emails without sending them
config :kollective,
       Kollective.Mailer,
       adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger,
  level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix,
       :plug_init_mode,
       :runtime

config :kollective, :moderation_engine, Kollective.ModerationMock
config :kollective, :security_engine, Kollective.SecurityMock
config :kollective, :accounts_engine, Kollective.AccountsMock

config :req, default_options: [plug: {Req.Test, Kollective.Services.GeocodioClient}]

# Direct the application client to a Mock module instead of the real service
# We do not need to manually write or implement ServiceMock, Mox library handles this dynamically in memory when tests run
config :kollective, :geospatial_client, Kollective.Geospatial.ServiceMock
