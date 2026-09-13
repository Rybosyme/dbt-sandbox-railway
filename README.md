# dbt sandbox on Railway

A web-based, disposable dbt workspace. Click "new session" in the dashboard and Railway spins up a
container with **code-server** (VS Code in the browser), **OpenCode**, **Claude Code**, **Codex**,
**dbt-core + dbt-postgres**, and **psql**, all pre-wired to a Postgres database through a restricted
role. Delete the session and the container is gone.

Forked from [sidpalas/background-agent-railway](https://github.com/sidpalas/background-agent-railway)
(companion repo to [this video](https://youtu.be/A-beOnncri8)).

## How it fits together

| Piece | What it is |
|---|---|
| `packages/api` | Express control plane. Creates/deletes sandbox services through the Railway API, stores sessions in its own Postgres, and reverse-proxies the browser into the sandbox over Railway's private network. |
| `packages/web` | React dashboard: log in with the admin password, create sessions, open them. |
| `packages/sandbox` | The sandbox image (`ghcr.io/rybosyme/dbt-sandbox`). Built by `.github/workflows/sandbox-image.yml` on every push that touches `packages/sandbox/`. |
| `dbt/` | Starter dbt project. Cloned into every sandbox; `DBT_PROJECT_DIR` points at it. `models/sources.yml` lists the source tables. |
| `AGENTS.md` / `CLAUDE.md` | Instructions the coding agents read inside the sandbox. |

### Variables the API needs

Everything the upstream template needs, plus:

| Variable | Purpose |
|---|---|
| `RAILWAY_PROJECT_TOKEN` **or** `RAILWAY_API_TOKEN` | Token used to create/delete sandbox services. A project token (Project settings → Tokens) is scoped to this project only. |
| `SANDBOX_VAR_<NAME>` | Injected into every sandbox as `<NAME>`. Used for `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`, `PGSSLMODE`, `ANTHROPIC_API_KEY`. |
| `SANDBOX_REPO_URL` | Repo cloned into the sandbox (public repos need no token). |

Each session also receives `DBT_SCHEMA=dbt_<session-name>` so concurrent sandboxes build into
separate schemas.

### Database access

The sandboxes connect as a dedicated Postgres role that can `SELECT` from the source schemas and
create/write only its own `dbt_*` schemas. Nothing in a sandbox can modify source tables.

## Deploying changes

```bash
railway up --service api     # from the repo root; uses packages/api/Dockerfile
railway up --service web     # root directory is /packages/web
git push                     # rebuilds the sandbox image if packages/sandbox changed
```

The API runs `pnpm db:migrate` as a pre-deploy step.

## Local development

See the upstream README section below; unchanged except that `packages/api/.env.example` now lists
the extra variables.

```bash
docker compose up -d
cp packages/api/.env.example packages/api/.env
pnpm install --dir packages/api && pnpm install --dir packages/web
pnpm --dir packages/api dev
pnpm --dir packages/web dev
```
