# syntax=docker/dockerfile:1.7
# Dockerfile.app — single container: llama.cpp (CUDA) + Hermes Agent + CloakBrowser
#
# Three processes managed by supervisord:
#   llama-server  — OpenAI-compatible inference API    :8080
#   cloakserve    — CloakBrowser stealth CDP browser   :9222
#   hermes        — Hermes Agent gateway / dashboard   :9119
#
# Build:
#   docker build -f Dockerfile.app -t hermes-all .
#
# Run (NVIDIA GPU + nvidia-container-toolkit required):
#   docker run --gpus all \
#     -p 127.0.0.1:8080:8080 \
#     -p 127.0.0.1:9222:9222 \
#     -p 127.0.0.1:9119:9119 \
#     -v "$(pwd)/models:/models:ro" \
#     -v "$(pwd)/data:/root/.hermes" \
#     -e LLAMA_MODEL=model.gguf \
#     hermes-all
#
# macOS note: NVIDIA CUDA is not supported on macOS. Run on Linux / WSL2.

ARG HERMES_REF=main

# ── Stage 1: Node.js 22 LTS binaries ──────────────────────────────────────
FROM node:22-bookworm-slim AS node_source

# ── Stage 2: Python venv (Hermes + CloakBrowser + supervisor) ─────────────
# uv's managed Python is built as a manylinux2014 binary (glibc >= 2.17),
# and --relocatable embeds it inside the venv so it runs on any modern Linux,
# including the Ubuntu-based llama.cpp CUDA final stage.
FROM ghcr.io/astral-sh/uv:python3.11-bookworm-slim AS py_builder

ARG HERMES_REF

ENV CLOAKBROWSER_CACHE_DIR=/opt/cloakbrowser \
    CLOAKBROWSER_AUTO_UPDATE=false

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc git ca-certificates curl libffi-dev \
    ripgrep ffmpeg \
    fonts-noto-color-emoji fonts-freefont-ttf \
    && rm -rf /var/lib/apt/lists/*

# Relocatable venv: Python interpreter is copied (not symlinked) into the
# venv and all paths are made relative, making it safe to copy across images.
RUN uv venv --relocatable --python 3.11 /opt/venv

ENV VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:${PATH}"

# Install Hermes Agent, CloakBrowser, and supervisor together
RUN uv pip install --no-cache \
    "hermes-agent[all,messaging,anthropic] @ git+https://github.com/NousResearch/hermes-agent.git@${HERMES_REF}" \
    cloakbrowser \
    supervisor

# Pre-download the stealth Chromium binary (~200 MB, cached at CLOAKBROWSER_CACHE_DIR)
RUN python -m cloakbrowser install

# ── Final: llama.cpp CUDA as base (provides llama-server binary + CUDA) ────
FROM ghcr.io/ggml-org/llama.cpp:server-cuda

ARG HERMES_REF

# ── Environment ────────────────────────────────────────────────────────────
ENV PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:/usr/local/bin:${PATH}" \
    HERMES_HOME=/root/.hermes \
    CLOAKBROWSER_CACHE_DIR=/opt/cloakbrowser \
    CLOAKBROWSER_AUTO_UPDATE=false \
    # llama.cpp defaults — override at runtime via -e LLAMA_MODEL=...
    LLAMA_MODEL=Hermes-3-Llama-3.1-8B.Q4_K_M.gguf \
    N_GPU_LAYERS=99 \
    CTX_SIZE=8192 \
    N_PARALLEL=4 \
    LLAMA_API_KEY=""

# Runtime system deps (no build tools — the venv is fully pre-built)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git procps \
    ripgrep ffmpeg \
    fonts-noto-color-emoji fonts-freefont-ttf \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 22 LTS ─────────────────────────────────────────────────────────
COPY --chmod=0755 --from=node_source /usr/local/bin/node /usr/local/bin/
COPY --from=node_source /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# ── Python venv (Hermes + CloakBrowser + supervisor) ──────────────────────
COPY --from=py_builder /opt/venv /opt/venv

# ── Pre-downloaded stealth Chromium binary ─────────────────────────────────
COPY --from=py_builder /opt/cloakbrowser /opt/cloakbrowser

# ── supervisord configuration ──────────────────────────────────────────────
RUN mkdir -p /etc/supervisor /run/supervisor && \
cat > /etc/supervisor/supervisord.conf << 'EOF'
[supervisord]
nodaemon=true
logfile=/dev/null
logfile_maxbytes=0
pidfile=/run/supervisor/supervisord.pid
childlogdir=/dev/null

[unix_http_server]
file=/run/supervisor/supervisor.sock

[rpcinterface:supervisor]
supervisor.rpcinterface_factory=supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///run/supervisor/supervisor.sock

; ── 1. llama.cpp CUDA inference server ────────────────────────────────────
[program:llama-server]
command=/bin/sh -c '/llama-server \
    --model "/models/%(ENV_LLAMA_MODEL)s" \
    --host 0.0.0.0 \
    --port 8080 \
    --n-gpu-layers %(ENV_N_GPU_LAYERS)s \
    --ctx-size %(ENV_CTX_SIZE)s \
    --parallel %(ENV_N_PARALLEL)s \
    --flash-attn'
autostart=true
autorestart=true
startsecs=5
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
priority=100

; ── 2. CloakBrowser stealth Chromium CDP server ───────────────────────────
[program:cloakbrowser]
command=cloakserve
autostart=true
autorestart=true
startsecs=5
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
priority=200

; ── 3. Hermes Agent gateway ───────────────────────────────────────────────
; Override docker-compose service hostnames to localhost for single-container.
[program:hermes]
command=hermes gateway run
environment=
    CAMOFOX_URL="http://localhost:9222",
    LLAMA_CPP_BASE_URL="http://localhost:8080/v1",
    LLAMA_CPP_API_KEY="%(ENV_LLAMA_API_KEY)s"
autostart=true
autorestart=true
startsecs=10
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
priority=300
EOF

# ── Model download ────────────────────────────────────────────────────────
RUN mkdir -p /models && \
    curl -fL --retry 3 --progress-bar \
    "https://huggingface.co/NousResearch/Hermes-3-Llama-3.1-8B-GGUF/resolve/main/Hermes-3-Llama-3.1-8B.Q4_K_M.gguf" \
    -o "/models/Hermes-3-Llama-3.1-8B.Q4_K_M.gguf"

# ── Volumes, ports, entrypoint ─────────────────────────────────────────────
VOLUME ["/models", "/root/.hermes"]

# llama-server  CloakBrowser CDP  Hermes dashboard
EXPOSE 8080 9222 9119

CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
