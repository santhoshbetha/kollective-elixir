# lib/kollective/repo_types.ex
Postgrex.Types.define(
  Kollective.PostgrexTypes,
  # This merges the standard Ecto/Postgrex extensions with PostGIS decoding
  [Geo.PostGIS.Extension] ++ Ecto.Adapters.Postgres.extensions(),
  json: Jason
)
