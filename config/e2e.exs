import Config

database_url =
  System.get_env("DATABASE_URL") ||
    "postgres://postgres:ec9LwfROv1JEXoMRsIB7so6r@kollective-e2e-peak-hawk-pooler.sage.cloud.layerbase.dev:5432/kollective_e2e"

config :kollective, Kollective.Repo,
  url: database_url,
  ssl: true,
  ssl_opts: [verify: :verify_none],
  types: Kollective.PostgrexTypes,
  pool_size: 10,
  queue_target: 10_000,
  queue_interval: 10_000,
  timeout: 30_000,
  connect_timeout: 30_000,
  log: false

config :kollective, Oban,
  repo: Kollective.Repo,
  queues: false,
  plugins: false

config :logger, level: :warning

# Storage configuration for E2E
config :kollective, :r2_prefix, "kollective-test"
config :kollective, :s3_bucket, "kollective"

# 2. Configure ExAws (or your project's S3 client) to point to Cloudflare R2
config :ex_aws,
  access_key_id: System.get_env("R2_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("R2_SECRET_ACCESS_KEY"),
  region: "auto"

config :ex_aws, :s3,
  scheme: "https://",
  host: "47701ef2e87f29505064cb21fd2513ed.r2.cloudflarestorage.com",
  access_key_id: System.get_env("R2_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("R2_SECRET_ACCESS_KEY"),
  region: "auto"

config :kollective, KollectiveWeb.Endpoint,
  # Choose a dedicated port for e2e testing
  http: [ip: {127, 0, 0, 1}, port: 4002],
  # 👈 CRITICAL: Must be true for Playwright to reach it
  server: true,
  code_reloader: true,
  secret_key_base: "something_secure_and_long_at_least_64_characters..."

# Disable libcluster topologies in e2e to prevent UDP port conflicts (:eaddrinuse)
config :libcluster, topologies: []
