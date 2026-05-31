# Dockerfile — Hermes Agent
#
# Builds hermes-agent from the NousResearch GitHub repository.
# Uses uv for fast dependency resolution and installs all extras
# needed for the gateway, messaging adapters, and tool integrations.
#
# Build args:
#   HERMES_REF  — git ref to install (default: main)

ARG HERMES_REF=main

# ── Stage 1: build / install ───────────────────────────────────────────────
FROM ghcr.io/astral-sh/uv:python3.11-bookworm-slim AS builder

ARG HERMES_REF

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_NO_CACHE=1

# System dependencies required by hermes and its tool integrations
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    ripgrep \
    ffmpeg \
    procps \
    gcc \
    python3-dev \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 LTS (required for hermes TUI / dashboard assets)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/hermes

# Install hermes-agent (all extras + messaging adapters) from GitHub.
# Pinning to a ref keeps builds reproducible; update HERMES_REF to upgrade.
RUN uv pip install --system --no-cache \
    "hermes-agent[all,messaging,anthropic] @ git+https://github.com/NousResearch/hermes-agent.git@${HERMES_REF}"

# ── Runtime ────────────────────────────────────────────────────────────────
FROM ghcr.io/astral-sh/uv:python3.11-bookworm-slim

ENV PYTHONUNBUFFERED=1 \
    HERMES_HOME=/root/.hermes \
    PATH="/usr/local/bin:${PATH}"

# Copy only the installed packages and binaries from the builder stage
COPY --from=builder /usr/local /usr/local
COPY --from=builder /usr/bin/ripgrep /usr/bin/rg

# Runtime system deps (no build tools)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    ffmpeg \
    procps \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root

# Hermes persistent data (config, memory, sessions, skills)
VOLUME ["/root/.hermes"]

# Dashboard port
EXPOSE 9119

# Default: run the gateway. Override CMD when running interactively:
#   docker compose run --rm hermes hermes --tui
ENTRYPOINT ["hermes"]
CMD ["gateway", "run"]
