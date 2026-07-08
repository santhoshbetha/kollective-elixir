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
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :kollective, KollectiveWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "/cXcHps34v0nW3z9IepcsxY86dwRWhl+spzLQ3Z38sEnmA5F/+q7GOHiVuov63J7",
  server: false

config :kollective, Oban,
  repo: Kollective.Repo,
  # Run jobs immediately inline during tests if needed
  testing: :inline,
  # 👈 Turn off all cron plugins/pruners for testing
  plugins: false

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
config :kollective, Kollective.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
