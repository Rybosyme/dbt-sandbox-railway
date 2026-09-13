FROM node:22-bookworm-slim

ARG OPENCODE_VERSION="latest"
ARG CODE_SERVER_VERSION="latest"
ARG CLAUDE_CODE_VERSION="latest"
ARG CODEX_VERSION="latest"

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    g++ \
    git \
    gh \
    jq \
    less \
    make \
    openssh-client \
    postgresql-client \
    python3 \
    python3-pip \
    python3-venv \
  && rm -rf /var/lib/apt/lists/*

RUN git config --global user.name "dbt Sandbox Bot" \
  && git config --global user.email "dbt-sandbox-bot@users.noreply.github.com"

RUN mkdir -p /root/.ssh \
  && chmod 700 /root/.ssh \
  && ssh-keyscan github.com >> /root/.ssh/known_hosts \
  && printf "Host github.com\n  HostName github.com\n  User git\n  StrictHostKeyChecking yes\n  UserKnownHostsFile /root/.ssh/known_hosts\n" > /root/.ssh/config \
  && chmod 600 /root/.ssh/config /root/.ssh/known_hosts

# dbt (core + postgres adapter) in its own venv
RUN python3 -m venv /opt/dbt \
  && /opt/dbt/bin/pip install --no-cache-dir --upgrade pip \
  && /opt/dbt/bin/pip install --no-cache-dir dbt-core dbt-postgres

RUN if [ "$OPENCODE_VERSION" = "latest" ]; then \
    curl -fsSL https://opencode.ai/install | bash; \
  else \
    curl -fsSL https://opencode.ai/install | bash -s -- --version "$OPENCODE_VERSION"; \
  fi

RUN if [ "${CODE_SERVER_VERSION}" = "latest" ]; then \
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone; \
  else \
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --version "${CODE_SERVER_VERSION}" --method=standalone; \
  fi

RUN npm install -g @anthropic-ai/claude-code@"${CLAUDE_CODE_VERSION}"
RUN npm install -g @openai/codex@"${CODEX_VERSION}"

WORKDIR /home/sandbox/workspace

COPY profiles.yml /root/.dbt/profiles.yml
COPY init.sh /usr/local/bin/sandbox-init.sh
RUN chmod +x /usr/local/bin/sandbox-init.sh

ENV PATH="/opt/dbt/bin:/root/.opencode/bin:/root/.local/bin:${PATH}"
ENV DBT_PROFILES_DIR=/root/.dbt

ENTRYPOINT ["/usr/local/bin/sandbox-init.sh"]
