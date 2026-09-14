# dbt sandbox platform

This repo is the control plane (`packages/api`, `packages/web`) and sandbox image (`packages/sandbox`)
for disposable dbt workspaces on Railway. The dbt projects themselves live in separate GitHub repos
named `dbt-<ID>`, created from `Rybosyme/dbt-project-template`.

- Sessions are created through the API; each one gets its own Railway service running the sandbox image.
- The sandbox clones the project's repo, points `DBT_PROJECT_DIR` at it, and injects DB credentials.
- Deploy with `railway up --service api|web` from the repo root; pushing to `packages/sandbox` rebuilds the image.
