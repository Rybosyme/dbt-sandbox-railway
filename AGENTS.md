# dbt sandbox

You are working inside an ephemeral sandbox that has read access to a production Postgres
database and write access to one scratch schema.

- The dbt project lives in `dbt/`. `DBT_PROJECT_DIR` already points at it, so `dbt run`,
  `dbt test`, `dbt build` work from any directory.
- Connection details are in the `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`
  environment variables, so `psql` works with no arguments.
- The database role is `dbt_sandbox`. It can SELECT from the `public`, `gutenberg`, `library`,
  `primetime`, and `mcp` schemas and can create/write only schemas named `dbt_*`.
  Models are built into the schema in `DBT_SCHEMA` (unique per sandbox session).
- Declared sources are in `dbt/models/sources.yml`. Prefer `{{ source() }}` and `{{ ref() }}`
  over hard-coded table names.
- Do not try to modify source tables. If a source is missing from `sources.yml`, add it.
- Commit your work and push a branch; the sandbox is destroyed when the session ends.
