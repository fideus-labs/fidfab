# syntax=docker/dockerfile:1.7
#
# fidfab sandbox image
#
# A locally built Ubuntu 24.04 image that Fabro uses as its Docker sandbox.
# Everything an agent needs is preinstalled so no network installs happen at
# run time: pixi, Rust, Vite+, Claude Code, Codex, CodeRabbit CLI, the ACP
# adapters for Claude Code and Codex, Serena (for Claude), cocoindex-code (for
# Codex), the planning-with-files / CodeRabbit / Cloudflare security skills,
# and a warmed clone of the target repository.
#
# Build with ./docker/build.sh (see README.md).

ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

# ---------------------------------------------------------------------------
# Build arguments
# ---------------------------------------------------------------------------
# The repository this image is specialised for. The clone is used as a warm
# cache (compiled artefacts, pixi environments, node_modules) and as a
# `git clone --reference` source when Fabro does not clone the repo itself.
ARG TARGET_REPO_URL=""
ARG TARGET_REPO_REF="main"
# Toolchain pins. "latest" is fine for a local image; pin for reproducibility.
ARG NODE_MAJOR=22
ARG RUST_TOOLCHAIN=stable
ARG CLAUDE_CODE_VERSION=latest
ARG CODEX_VERSION=latest
ARG CLAUDE_AGENT_ACP_VERSION=latest
ARG CODEX_ACP_VERSION=latest
ARG PLANNING_WITH_FILES_REF="OthmanAdi/planning-with-files"
ARG CODERABBIT_SKILLS_REF="coderabbitai/skills"
ARG CLOUDFLARE_SECURITY_AUDIT_REF="https://github.com/cloudflare/security-audit-skill"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

# Installer pipelines below (`curl … | bash`) must fail the build when the
# download fails, not just when the shell step does.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---------------------------------------------------------------------------
# Base system
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget git git-lfs gnupg lsb-release \
        build-essential pkg-config cmake ninja-build clang lld lldb gdb \
        libssl-dev libclang-dev llvm-dev \
        python3 python3-venv python3-pip pipx \
        jq ripgrep fd-find fzf tree unzip zip xz-utils zstd \
        openssh-client sudo tini procps less vim-tiny shellcheck \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI (used by the PR and steward stages)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI (for workflows that build or run containers from inside the sandbox)
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Node.js (Claude Code, Codex, the ACP adapters and the skills CLI are npm packages)
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g npm@latest \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Fabro sandboxes run stages as root. Claude Code refuses
# `bypassPermissions` as root unless it is told it is in a sandbox.
# ---------------------------------------------------------------------------
ENV HOME=/root \
    IS_SANDBOX=1 \
    FIDFAB_HOME=/opt/fidfab \
    FIDFAB_CACHE=/opt/fidfab/cache \
    FIDFAB_REPO=/opt/fidfab/repo
RUN mkdir -p ${FIDFAB_HOME} ${FIDFAB_CACHE} ${FIDFAB_REPO}

# ---------------------------------------------------------------------------
# pixi (https://pixi.sh) — conda/PyPI environments for scientific stacks
# ---------------------------------------------------------------------------
ENV PIXI_HOME=/opt/pixi \
    PIXI_CACHE_DIR=/opt/fidfab/cache/pixi
RUN curl -fsSL https://pixi.sh/install.sh | PIXI_HOME=${PIXI_HOME} PIXI_NO_PATH_UPDATE=1 bash
ENV PATH="${PIXI_HOME}/bin:${PATH}"
# Keep pixi environments outside the project tree so a fresh clone can reuse them.
RUN pixi config set --global detached-environments ${FIDFAB_CACHE}/pixi-envs

# uv (Serena and other Python tools are run through uvx)
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh
ENV UV_CACHE_DIR=/opt/fidfab/cache/uv

# ---------------------------------------------------------------------------
# Rust
# ---------------------------------------------------------------------------
ENV RUSTUP_HOME=/opt/rust/rustup \
    CARGO_HOME=/opt/rust/cargo \
    CARGO_TARGET_DIR=/opt/fidfab/cache/target \
    CARGO_INCREMENTAL=0 \
    RUST_BACKTRACE=1
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --no-modify-path --default-toolchain ${RUST_TOOLCHAIN} --profile minimal \
            --component clippy,rustfmt,rust-src,rust-analyzer \
    && ${CARGO_HOME}/bin/rustup target add wasm32-unknown-unknown wasm32-wasip1
ENV PATH="${CARGO_HOME}/bin:${PATH}"
RUN cargo install --locked cargo-nextest cargo-llvm-cov cargo-deny cargo-audit wasm-pack \
    && rm -rf ${CARGO_HOME}/registry/cache

# ---------------------------------------------------------------------------
# Vite+ (https://vite.plus) — unified JS/TS toolchain (`vp`)
# ---------------------------------------------------------------------------
RUN curl -fsSL https://vite.plus | bash
# The installer puts its `vp` shims in ~/.local/share/vite-plus/bin. Its
# fallback-bin (node/npm shims) is left off PATH so the system Node stays first.
ENV PATH="/root/.local/share/vite-plus/bin:/root/.local/bin:${PATH}"

# ---------------------------------------------------------------------------
# Agents: Claude Code, Codex, and their ACP adapters
# ---------------------------------------------------------------------------
# npm 12 blocks install scripts that are not allowlisted. Claude Code's
# postinstall links its platform-native binary; without it `claude` is a stub.
RUN npm install -g --allow-scripts=@anthropic-ai/claude-code \
        @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
        @openai/codex@${CODEX_VERSION} \
        @agentclientprotocol/claude-agent-acp@${CLAUDE_AGENT_ACP_VERSION} \
        @agentclientprotocol/codex-acp@${CODEX_ACP_VERSION} \
    && npm cache clean --force

# Claude Code: settings (bypass permissions inside the sandbox, Serena hooks)
# and onboarding state; Codex: config (no approvals inside the sandbox).
COPY docker/config/claude-settings.json /root/.claude/settings.json
COPY docker/config/claude.json          /root/.claude.json
COPY docker/config/codex-config.toml    /root/.codex/config.toml
ENV CODEX_HOME=/root/.codex

# ---------------------------------------------------------------------------
# CodeRabbit CLI (https://docs.coderabbit.ai/cli)
# ---------------------------------------------------------------------------
RUN curl -fsSL https://cli.coderabbit.ai/install.sh | sh \
    && ln -sf /root/.local/bin/coderabbit /usr/local/bin/coderabbit \
    && ln -sf /root/.local/bin/coderabbit /usr/local/bin/cr

# ---------------------------------------------------------------------------
# Serena (semantic code tooling for Claude) and cocoindex-code (code index for Codex)
# ---------------------------------------------------------------------------
# Both are installed as uv tools so no network access is needed when a stage
# starts them. Serena is registered with Claude Code at user scope
# (~/.claude.json) and cocoindex-code (`ccc`) with Codex (~/.codex/config.toml).
RUN uv tool install -p 3.13 serena-agent \
    && uv tool install 'cocoindex-code[full]' \
    && ln -sf /root/.local/bin/serena /usr/local/bin/serena \
    && ln -sf /root/.local/bin/ccc /usr/local/bin/ccc \
    && serena init
# MCP servers can be slow to start on first use inside a fresh sandbox.
ENV MCP_TIMEOUT=60000

# ---------------------------------------------------------------------------
# Agent skills (portable SKILL.md packages via the skills CLI)
#   - planning-with-files : persistent task_plan.md / findings.md / progress.md
#   - coderabbit code-review : "4. Fix Issues (Autonomous Workflow)"
#   - cloudflare security-audit : six-phase verified security audit
# Installed globally for both Claude Code and Codex.
# ---------------------------------------------------------------------------
# Skills land in ~/.claude/skills (Claude Code) and ~/.agents/skills (Codex).
RUN npx -y skills add ${PLANNING_WITH_FILES_REF} --skill planning-with-files -g -y -a claude-code -a codex --copy \
    && npx -y skills add ${CODERABBIT_SKILLS_REF} --skill code-review -g -y -a claude-code -a codex --copy \
    && npx -y skills add ${CLOUDFLARE_SECURITY_AUDIT_REF} --skill security-audit -g -y -a claude-code -a codex --copy \
    && npm cache clean --force

# ---------------------------------------------------------------------------
# fidfab helper scripts
# ---------------------------------------------------------------------------
COPY docker/rootfs/ /
RUN chmod +x /usr/local/bin/fidfab-*

# ---------------------------------------------------------------------------
# Built-in clone of the target repository with warmed caches
# ---------------------------------------------------------------------------
# Skipped when TARGET_REPO_URL is empty, which produces a generic image.
# Private repositories can be given as SSH URLs (git@github.com:OWNER/REPO):
# build.sh forwards the host ssh-agent (`--ssh default`), which only the clone
# step can use (cache warming runs repository code, so it gets no agent), and
# GitHub's host keys come from /etc/ssh/ssh_known_hosts. The origin is then
# rewritten to HTTPS (ssh://[user@]host[:port]/path and user@host:path forms)
# because sandboxes authenticate to GitHub with GITHUB_TOKEN (see
# fidfab-bootstrap), not with an SSH key.
RUN --mount=type=ssh \
    if [ -n "${TARGET_REPO_URL}" ]; then \
        git clone --branch "${TARGET_REPO_REF}" "${TARGET_REPO_URL}" ${FIDFAB_REPO} \
        && git -C ${FIDFAB_REPO} remote set-url origin \
            "$(printf '%s' "${TARGET_REPO_URL}" | sed -E \
                -e 's#^ssh://([^@/]+@)?([^:/]+)(:[0-9]+)?/#https://\2/#' \
                -e 's#^[^@/:]+@([^:/]+):#https://\1/#')"; \
    else \
        echo "TARGET_REPO_URL not set; building a generic fidfab image"; \
    fi
RUN if [ -n "${TARGET_REPO_URL}" ]; then fidfab-warm-cache ${FIDFAB_REPO}; fi

# Record what was built for `fidfab-doctor` and the tests.
RUN fidfab-doctor --write-manifest ${FIDFAB_HOME}/manifest.json || true

WORKDIR /workspace
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/bash"]
