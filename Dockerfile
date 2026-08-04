# syntax=docker/dockerfile:1.7
#
# Buzznode - a browser-accessible computer for one Buzz agent.
#
# The Openbox/KasmVNC desktop, its browser, and the Ubuntu/Node foundation
# under it all come from the Launcher desktop base. Nothing about the desktop
# is configured here: branding and product programs are installed through
# overlay/, which is copied over the base's defaults.
#
# Buzznode connects to an existing relay and deliberately contains neither the
# Buzz Desktop client nor local relay/backing services.

ARG DESKTOP_IMAGE=ghcr.io/pdparchitect/launcher-image-base-desktop:0.1.9

# Upstream publishes a Linux package only for AMD64. Extract its headless tools
# there; on ARM64, build the same immutable tag and exact commit from source.
FROM rust:1.95-bookworm AS buzz-tools

ARG TARGETARCH
ARG BUZZ_VERSION=0.5.4
ARG BUZZ_RELEASE_TAG=desktop-v0.5.4
ARG BUZZ_DEB_SHA256=9c2f0df4589c08698dd940e09d911884a5468c35169d1068fc6ccc93012bfeff
ARG BUZZ_SOURCE_SHA=651f6372754e60e3f936b3397040eb0f1e44c9f3

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git pkg-config && \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    mkdir -p /out; \
    if [ "$arch" = "amd64" ]; then \
        buzz_deb="/tmp/Buzz_${BUZZ_VERSION}_amd64.deb"; \
        extract_dir="$(mktemp -d)"; \
        curl -fsSL \
            "https://github.com/block/buzz/releases/download/${BUZZ_RELEASE_TAG}/Buzz_${BUZZ_VERSION}_amd64.deb" \
            -o "$buzz_deb"; \
        echo "${BUZZ_DEB_SHA256}  ${buzz_deb}" | sha256sum -c -; \
        dpkg-deb --extract "$buzz_deb" "$extract_dir"; \
        for binary in buzz buzz-acp buzz-agent buzz-dev-mcp git-credential-nostr; do \
            install -m 0755 "$extract_dir/usr/bin/$binary" "/out/$binary"; \
        done; \
        rm -rf "$extract_dir" "$buzz_deb"; \
    elif [ "$arch" = "arm64" ]; then \
        git clone --branch "${BUZZ_RELEASE_TAG}" --depth 1 \
            https://github.com/block/buzz.git /tmp/buzz; \
        cd /tmp/buzz; \
        test "$(git rev-parse HEAD)" = "$BUZZ_SOURCE_SHA"; \
        cargo build --locked --release \
            -p buzz-cli \
            -p buzz-acp \
            -p buzz-agent \
            -p buzz-dev-mcp \
            -p git-credential-nostr; \
        for binary in buzz buzz-acp buzz-agent buzz-dev-mcp git-credential-nostr; do \
            install -m 0755 "target/release/$binary" "/out/$binary"; \
        done; \
        rm -rf /tmp/buzz; \
    else \
        echo "Buzznode does not support linux/$arch" >&2; \
        exit 1; \
    fi; \
    strip /out/*

FROM ${DESKTOP_IMAGE}

USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TARGETARCH

# The Python data stack the agent runtimes are expected to have on hand. The
# desktop base carries plain python3; these are the libraries on top of it.
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-numpy python3-pandas python3-scipy python3-requests ipython3 \
    && rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/bin/ipython3 /usr/bin/ipython

# Docker and GitHub CLIs remain available for coding-agent workflows. Buzznode
# does not require a host Docker socket.
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor \
        -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu noble stable" \
        > /etc/apt/sources.list.d/docker.list && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce-cli gh && \
    rm -rf /var/lib/apt/lists/*

# Coding CLIs and the ACP adapters that make them discoverable by Buzz. Node
# and npm come from the runtime layer in the base chain.
#
# npm's cache follows HOME, which the desktop base points at the session user's
# home. Without an explicit cache directory this root-run install leaves
# /home/agent/.npm owned by root, and then kitty cannot start and the session
# opens with no terminal at all.
ARG CODEX_VERSION=0.146.0
ARG CLAUDE_CODE_VERSION=2.1.221
ARG CODEX_ACP_VERSION=1.1.9
ARG CLAUDE_ACP_VERSION=0.64.2
ENV npm_config_cache=/tmp/npm-cache
RUN npm install -g \
        "@openai/codex@${CODEX_VERSION}" \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
        "@agentclientprotocol/codex-acp@${CODEX_ACP_VERSION}" \
        "@agentclientprotocol/claude-agent-acp@${CLAUDE_ACP_VERSION}" && \
    rm -rf /tmp/npm-cache && \
    codex --version && \
    claude --version && \
    codex-acp --version && \
    claude-agent-acp --version

# Goose exposes ACP natively, so it does not need a separate adapter.
ARG GOOSE_VERSION=1.45.0
ARG GOOSE_AMD64_SHA256=e0db638ac437ca0a60b0c1622f45322608d228d1a285214c3bf48fd9763346a5
ARG GOOSE_ARM64_SHA256=c9894106c90e404ac8b8d67c628aea2943dd6a1bc83bfd8e2171d482fa43d72a
RUN arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
        amd64) goose_arch=x86_64; goose_sha="$GOOSE_AMD64_SHA256" ;; \
        arm64) goose_arch=aarch64; goose_sha="$GOOSE_ARM64_SHA256" ;; \
        *) echo "Unsupported Goose architecture: $arch" >&2; exit 1 ;; \
    esac; \
    goose_archive="/tmp/goose-${GOOSE_VERSION}.tar.gz" && \
    curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 \
        "https://github.com/aaif-goose/goose/releases/download/v${GOOSE_VERSION}/goose-${goose_arch}-unknown-linux-gnu.tar.gz" \
        -o "$goose_archive" && \
    echo "${goose_sha}  ${goose_archive}" | sha256sum -c - && \
    goose_dir="$(mktemp -d)" && \
    tar -xzf "$goose_archive" -C "$goose_dir" && \
    install -m 0755 "$goose_dir/goose" /usr/local/bin/goose && \
    rm -rf "$goose_dir" "$goose_archive" && \
    goose --version && \
    goose acp --help >/dev/null

# Only the headless Buzz tools. The builder extracts the verified upstream
# package on AMD64 and builds the same pinned source tag on ARM64.
ARG BUZZ_VERSION=0.5.4
ARG BUZZ_SOURCE_SHA=651f6372754e60e3f936b3397040eb0f1e44c9f3
ARG BUZZ_SOURCE_URL=https://github.com/block/buzz
COPY --from=buzz-tools /out/ /usr/local/bin/
RUN for binary in buzz buzz-acp buzz-agent buzz-dev-mcp git-credential-nostr; do \
        test -x "/usr/local/bin/$binary"; \
    done; \
    command -v buzz; \
    command -v buzz-acp; \
    command -v buzz-agent; \
    command -v buzz-dev-mcp; \
    test ! -e /usr/bin/buzz-desktop; \
    test ! -e /usr/local/bin/buzz-desktop

# These paths are volumes, so a rebuilt image resumes enrolled and signed in.
# Creating them now means the entrypoint's ownership pass has something to
# normalise on a brand-new volume.
RUN mkdir -p \
        /home/agent/.config/buzznode \
        /home/agent/.buzz \
        /home/agent/.codex \
        /home/agent/.claude && \
    rm -rf /home/agent/.cache /home/agent/.npm && \
    chown -R agent:agent /home/agent

# Product branding and the programs that drive the node. Everything under
# overlay/ is installed over the base's defaults, so a file here wins without
# the base knowing this product exists.
COPY overlay /
RUN chmod 0755 \
        /etc/desktop/session.d/10-buzznode-harness \
        /etc/desktop/startup.d/05-agent-runtime-trust \
        /usr/local/bin/agent-runtime-login \
        /usr/local/bin/buzznode \
        /usr/local/bin/buzznode-greeting \
        /usr/local/bin/desktop-panel-status \
        /usr/local/bin/desktop-welcome

# Rebrand the KasmVNC client. The base already patched it, so this replaces the
# brand rather than injecting the asset links a second time.
RUN kasm-patch "Buzznode"

# DESKTOP_PERSISTENT_PATHS is the base entrypoint's contract: these are created
# and ownership-normalised before the session starts, and they are the paths
# declared as volumes below.
ENV DESKTOP_TITLE="Buzznode" \
    DESKTOP_PERSISTENT_PATHS="/home/agent/.config /home/agent/.local/share /home/agent/.buzz /home/agent/.codex /home/agent/.claude"

LABEL org.opencontainers.image.title="Buzznode" \
    org.opencontainers.image.description="A browser-accessible computer for one Buzz agent, in a Launcher-managed desktop" \
    org.opencontainers.image.source="https://github.com/pdparchitect/buzznode" \
    dev.pdparchitect.launcher.upstream.source="${BUZZ_SOURCE_URL}" \
    dev.pdparchitect.launcher.upstream.version="${BUZZ_VERSION}" \
    dev.pdparchitect.launcher.upstream.revision="${BUZZ_SOURCE_SHA}"

# The desktop's 6901 comes from the base, like every other Launcher product,
# and this image publishes nothing else.
WORKDIR /workspace
VOLUME ["/workspace", "/home/agent/.config", "/home/agent/.local/share", "/home/agent/.buzz", "/home/agent/.codex", "/home/agent/.claude"]
