#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_DIR="/home/sandbox/workspace"
REPO_DIR="${WORKSPACE_DIR}/repo"
REPO_URL="${SANDBOX_REPO_URL:-}"
GITHUB_TOKEN="${GITHUB_PERSONAL_ACCESS_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN:-}}}"

mkdir -p "${WORKSPACE_DIR}"

# Clone the working repo. A token is only needed for private repos.
if [ -n "${REPO_URL}" ] && [ ! -d "${REPO_DIR}/.git" ]; then
  CLONE_URL="${REPO_URL}"

  if [ -n "${GITHUB_TOKEN}" ] && [[ "${REPO_URL}" == https://github.com/* ]]; then
    CLONE_URL="https://x-access-token:${GITHUB_TOKEN}@${REPO_URL#https://}"
  fi

  git clone "${CLONE_URL}" "${REPO_DIR}"

  if [[ "${REPO_URL}" == https://github.com/* ]]; then
    git -C "${REPO_DIR}" remote set-url origin "${REPO_URL}"
  fi
fi

if [ -n "${GITHUB_TOKEN}" ]; then
  git config --global credential.helper '!f() { echo "username=x-access-token"; echo "password='"${GITHUB_TOKEN}"'"; }; f'
fi

CODE_SERVER_DIR="${WORKSPACE_DIR}"
if [ -d "${REPO_DIR}/.git" ]; then
  CODE_SERVER_DIR="${REPO_DIR}"
fi

# Point dbt at the project: the repo root itself, or <repo>/dbt for monorepos.
DBT_DIR="${REPO_DIR}"
if [ ! -f "${DBT_DIR}/dbt_project.yml" ]; then
  DBT_DIR="${REPO_DIR}/${SANDBOX_DBT_DIR:-dbt}"
fi
if [ -f "${DBT_DIR}/dbt_project.yml" ]; then
  export DBT_PROJECT_DIR="${DBT_DIR}"
fi

# Commit identity for pushes from the sandbox (override via GIT_USER_NAME / GIT_USER_EMAIL).
git config --global user.name "${GIT_USER_NAME:-dbt Sandbox Bot}"
git config --global user.email "${GIT_USER_EMAIL:-dbt-sandbox-bot@users.noreply.github.com}"

# Shell banner so a new terminal explains itself.
cat > /etc/profile.d/sandbox.sh <<BANNER
export PATH="/opt/dbt/bin:/root/.opencode/bin:/root/.local/bin:\$PATH"
export DBT_PROFILES_DIR="${DBT_PROFILES_DIR:-/root/.dbt}"
${DBT_PROJECT_DIR:+export DBT_PROJECT_DIR="${DBT_PROJECT_DIR}"}
BANNER

cat > /etc/motd <<BANNER
dbt sandbox
  database : ${PGUSER:-?}@${PGHOST:-?}:${PGPORT:-5432}/${PGDATABASE:-?}  (schema: ${DBT_SCHEMA:-dbt_sandbox})
  project  : ${DBT_PROJECT_ID:-?}  ${SANDBOX_REPO_URL:-}
  dbt      : ${DBT_PROJECT_DIR:-<no dbt project found>}
  agents   : opencode | claude | codex   (ANTHROPIC_API_KEY $( [ -n "${ANTHROPIC_API_KEY:-}" ] && echo set || echo NOT set ))
  try      : dbt debug && dbt run     |   psql
BANNER

if [ -f "${DBT_DIR}/dbt_project.yml" ] && [ -n "${PGHOST:-}" ]; then
  (cd "${DBT_DIR}" && dbt deps --quiet >/dev/null 2>&1 || true)
fi

exec code-server --host 0.0.0.0 --port 8080 --auth none "${CODE_SERVER_DIR}"
