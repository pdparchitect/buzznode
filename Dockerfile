# syntax=docker/dockerfile:1.7
#
# Buzznode - a browser-accessible computer for one Buzz agent.
#
# Buzznode connects to an existing relay and deliberately contains neither the
# Buzz Desktop client nor local relay/backing services.

# Upstream publishes a Linux package only for AMD64. Extract its headless tools
# there; on ARM64, build the same immutable tag and exact commit from source.
FROM rust:1.95-bookworm AS buzz-tools

ARG TARGETARCH
ARG BUZZ_VERSION=0.5.0
ARG BUZZ_DEB_SHA256=9674cf098eca88333e8d895ec9d0a5c56c796fbc358fe1087b645890b8e2faca
ARG BUZZ_SOURCE_SHA=4a977c588a540be38bd8ddb268cd24437bac8165

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
            "https://github.com/block/buzz/releases/download/v${BUZZ_VERSION}/Buzz_${BUZZ_VERSION}_amd64.deb" \
            -o "$buzz_deb"; \
        echo "${BUZZ_DEB_SHA256}  ${buzz_deb}" | sha256sum -c -; \
        dpkg-deb --extract "$buzz_deb" "$extract_dir"; \
        for binary in buzz buzz-acp buzz-agent buzz-dev-mcp git-credential-nostr; do \
            install -m 0755 "$extract_dir/usr/bin/$binary" "/out/$binary"; \
        done; \
        rm -rf "$extract_dir" "$buzz_deb"; \
    elif [ "$arch" = "arm64" ]; then \
        git clone --branch "v${BUZZ_VERSION}" --depth 1 \
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

# ═══════════════════════════════════════════════════════════════════
# Stage: core - shared runtime/tooling baseline for agent workloads.
# ═══════════════════════════════════════════════════════════════════
FROM ubuntu:24.04 AS core

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive

RUN arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
        amd64|arm64) ;; \
        *) echo "Buzznode does not support linux/$arch" >&2; exit 1 ;; \
    esac

# Core tools for the node and its coding-agent runtimes.
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash coreutils curl git openssh-client jq socat wget ca-certificates sudo \
    tar zip unzip file procps openssl gnupg \
    dnsutils iproute2 haveged \
    sqlite3 \
    python3 python3-pip python-is-python3 \
    python3-numpy python3-pandas python3-scipy python3-requests \
    ipython3 \
    vim ripgrep git-lfs \
    && rm -rf /var/lib/apt/lists/*

# Node.js 24, matching the current Buzz development toolchain.
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/* && \
    node --version && npm --version

RUN corepack enable && corepack prepare pnpm@10.13.1 --activate && \
    pnpm --version

# Coding CLIs and the ACP adapters that make them discoverable by Buzz.
ARG CODEX_VERSION=0.145.0
ARG CLAUDE_CODE_VERSION=2.1.220
ARG CODEX_ACP_VERSION=1.1.7
ARG CLAUDE_ACP_VERSION=0.62.0
RUN npm install -g \
    "@openai/codex@${CODEX_VERSION}" \
    "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    "@agentclientprotocol/codex-acp@${CODEX_ACP_VERSION}" \
    "@agentclientprotocol/claude-agent-acp@${CLAUDE_ACP_VERSION}" && \
    codex --version && \
    claude --version && \
    codex-acp --version && \
    claude-agent-acp --version

# Goose exposes ACP natively, so it does not need a separate adapter.
ARG GOOSE_VERSION=1.44.0
ARG GOOSE_AMD64_SHA256=07febc8b4f73bdfdc3ece3d34d0e21b005f3a4f43008f95b85d6538da8f6bac1
ARG GOOSE_ARM64_SHA256=da6cb005d421b0bdcb83fe8386ba5ae8060ef17adf64641a684d4fc4b9e1c15f
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

# Mike Farah yq.
ARG YQ_VERSION=4.44.6
RUN arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${arch}" \
        -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq && \
    yq --version

# Copy only the headless Buzz tools. The builder extracts the verified upstream
# package on AMD64 and builds the same pinned source tag on ARM64.
ARG BUZZ_VERSION=0.5.0
ARG BUZZ_DEB_SHA256=9674cf098eca88333e8d895ec9d0a5c56c796fbc358fe1087b645890b8e2faca
ARG BUZZ_SOURCE_SHA=4a977c588a540be38bd8ddb268cd24437bac8165
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

# Required directories.
RUN mkdir -p /data /outputs /workspace /var/log/buzznode

# Alias ipython to ipython3 and pip to pip3 for consistency.
RUN ln -sf /usr/bin/ipython3 /usr/bin/ipython && \
    ln -sf /usr/bin/pip3 /usr/bin/pip

# ═══════════════════════════════════════════════════════════════════
# Stage: base - desktop UI substrate layered on top of core.
# ═══════════════════════════════════════════════════════════════════
FROM core AS base

# KasmVNC supplies its own X server (Xvnc), so the `xorg` metapackage is not
# installed: it would add xserver-xorg-core, input/video drivers, keyboard-
# configuration, and udev/systemd for hardware this container never has.
# `x11-xserver-utils` is skipped for the same reason - its only consumer would
# be the xrdb call in KasmVNC's generated xstartup, and xstartup is replaced
# below with `exec openbox-session`. Together they cost ~90 MiB.
# xauth, xkb-data, and x11-xkb-utils are listed explicitly even though
# kasmvncserver depends on them, so an autoremove can never take them out.
# xfonts-base supplies the core font path Xvnc is started with.
RUN apt-get update && apt-get install -y --no-install-recommends \
    xdg-utils ssl-cert \
    xauth xkb-data x11-xkb-utils xfonts-base \
    xterm dbus-x11 x11-utils \
    scrot \
    openbox obconf tint2 kitty ranger feh picom htop xdotool wmctrl \
    fonts-noto fonts-noto-color-emoji \
    libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 libdrm2 \
    libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 libgbm1 \
    libpango-1.0-0 libasound2t64 libxshmfence1 \
    && rm -rf /var/lib/apt/lists/*

# Cortile provides optional dynamic tiling on top of Openbox.
ARG CORTILE_VERSION=2.5.2
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) cortile_arch=amd64 ;; \
        arm64) cortile_arch=arm64 ;; \
        *) echo "Unsupported Cortile architecture: $arch" >&2; exit 1 ;; \
    esac; \
    tmp_dir="$(mktemp -d)"; \
    curl -fsSL \
        "https://github.com/leukipp/cortile/releases/download/v${CORTILE_VERSION}/cortile_${CORTILE_VERSION}_linux_${cortile_arch}.tar.gz" \
        | tar -xz -C "$tmp_dir"; \
    install -m 0755 "$tmp_dir/cortile" /usr/local/bin/cortile; \
    rm -rf "$tmp_dir"

# KasmVNC exposes the desktop in a browser.
ARG KASMVNC_VERSION=1.4.0
RUN arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    curl -fsSL \
        "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_noble_${KASMVNC_VERSION}_${arch}.deb" \
        -o /tmp/kasmvnc.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends /tmp/kasmvnc.deb && \
    rm -f /tmp/kasmvnc.deb && \
    rm -rf /var/lib/apt/lists/*

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

# Google does not publish Chrome for Linux ARM64. Keep Chrome on AMD64 and use
# Debian's signed Chromium package on ARM64 behind the same Buzznode launcher.
RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    if [ "$arch" = "amd64" ]; then \
        curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
            -o /tmp/browser.deb; \
        apt-get update; \
        apt-get install -y --no-install-recommends /tmp/browser.deb; \
        rm -f /tmp/browser.deb; \
    else \
        mkdir -p /etc/apt/keyrings; \
        curl -fsSL https://ftp-master.debian.org/keys/archive-key-12.asc \
            -o /etc/apt/keyrings/debian-archive-key-12.asc; \
        printf '%s\n' \
            'deb [arch=arm64 signed-by=/etc/apt/keyrings/debian-archive-key-12.asc] https://deb.debian.org/debian bookworm main' \
            > /etc/apt/sources.list.d/debian-bookworm.list; \
        printf '%s\n' \
            'Package: *' \
            'Pin: release n=bookworm' \
            'Pin-Priority: 100' \
            > /etc/apt/preferences.d/debian-bookworm; \
        apt-get update; \
        apt-get install -y --no-install-recommends chromium; \
        rm -f \
            /etc/apt/keyrings/debian-archive-key-12.asc \
            /etc/apt/preferences.d/debian-bookworm \
            /etc/apt/sources.list.d/debian-bookworm.list; \
    fi; \
    rm -rf /var/lib/apt/lists/*

# ═══════════════════════════════════════════════════════════════════
# Stage: buzznode - one persistent desktop connected to an existing Buzz relay.
# ═══════════════════════════════════════════════════════════════════
FROM base AS buzznode

RUN if id -u agent >/dev/null 2>&1; then \
        usermod -d /home/buzznode -m agent; \
    elif id -u ubuntu >/dev/null 2>&1; then \
        usermod -l agent -d /home/buzznode -m ubuntu && groupmod -n agent ubuntu; \
    else \
        groupadd --system agent && \
        useradd --system --create-home --home-dir /home/buzznode \
            --gid agent --shell /bin/bash agent; \
    fi && \
    mkdir -p \
        /home/buzznode/.vnc \
        /home/buzznode/.config/buzznode \
        /home/buzznode/.local/share/applications \
        /home/buzznode/.buzz \
        /home/buzznode/.codex \
        /home/buzznode/.claude \
        /workspace \
        /var/log/buzznode && \
    chown -R agent:agent \
        /home/buzznode \
        /workspace \
        /var/log/buzznode

ENV HOME=/home/buzznode \
    BROWSER=chromium
ENV GTK_THEME=Buzznode
# Chrome and Chromium ask GTK for embedded symbolic window-control resources.
# Overlay only those four resources so their custom frames use the exact
# Openbox glyph masks.
ENV G_RESOURCE_OVERLAYS=/org/gtk/libgtk=/usr/share/buzznode/gtk-overlay

# Browser popup menus come from Linux's native color pipeline rather than
# extension-theme colors. A GTK system theme therefore styles the menus,
# dialogs, toolbar, tabs, and omnibox as one coherent near-black surface.
COPY gtk/Buzznode /usr/share/themes/Buzznode
COPY gtk/generate-resource-overlay.py /tmp/generate-gtk-resource-overlay.py
COPY openbox/theme /tmp/openbox-theme
# Generate real symbolic PNGs directly from the Openbox XBM source assets.
RUN python3 /tmp/generate-gtk-resource-overlay.py \
        /tmp/openbox-theme /usr/share/buzznode/gtk-overlay && \
    rm -rf /tmp/generate-gtk-resource-overlay.py /tmp/openbox-theme

RUN echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent && \
    chmod 0440 /etc/sudoers.d/agent && \
    touch /home/buzznode/.sudo_as_admin_successful /home/buzznode/.hushlogin && \
    chown agent:agent \
        /home/buzznode/.sudo_as_admin_successful \
        /home/buzznode/.hushlogin

# KasmVNC UI customisation.
COPY kasm/custom.css /usr/share/kasmvnc/www/assets/custom.css
COPY kasm/favicon.svg /usr/share/kasmvnc/www/assets/favicon.svg
COPY kasm/patch.sh /tmp/kasm-patch.sh
RUN chmod +x /tmp/kasm-patch.sh && /tmp/kasm-patch.sh && rm /tmp/kasm-patch.sh

# Match the Buzz website's chartreuse background and subtle dot grid.
COPY wallpaper/buzz-grid.svg /usr/share/backgrounds/buzz-grid.svg

# Browser preferences. `system_theme: 1` selects GTK on Linux; unlike an
# extension theme, it also reaches native menus and other popup surfaces.
RUN for config_dir in google-chrome chromium; do \
        mkdir -p "/home/buzznode/.config/$config_dir/Default"; \
        printf '{\n  "browser": {\n    "has_seen_welcome_page": true,\n    "check_default_browser": false\n  },\n  "bookmark_bar": { "show_on_all_tabs": false },\n  "distribution": {\n    "skip_first_run_ui": true,\n    "show_welcome_page": false,\n    "import_bookmarks": false,\n    "make_chrome_default_for_user": false,\n    "suppress_first_run_default_browser_prompt": true\n  },\n  "extensions": {\n    "theme": {\n      "system_theme": 1\n    }\n  }\n}' \
            > "/home/buzznode/.config/$config_dir/Default/Preferences"; \
        touch "/home/buzznode/.config/$config_dir/First Run"; \
    done && \
    chown -R agent:agent \
        /home/buzznode/.config/google-chrome \
        /home/buzznode/.config/chromium

# Suppress the default-browser prompt via managed policy. Do not set
# BrowserThemeColor here: that policy overrides the GTK system theme.
RUN mkdir -p \
        /etc/opt/chrome/policies/managed \
        /etc/chromium/policies/managed && \
    printf '{\n  "DefaultBrowserSettingEnabled": false,\n  "BrowserSignin": 0,\n  "HomepageLocation": "file:///opt/browser/index.html",\n  "HomepageIsNewTabPage": false,\n  "ShowHomeButton": true\n}\n' \
        > /etc/opt/chrome/policies/managed/buzznode-policy.json && \
    cp /etc/opt/chrome/policies/managed/buzznode-policy.json \
        /etc/chromium/policies/managed/buzznode-policy.json

COPY openbox/rc.xml /etc/xdg/openbox/rc.xml
COPY openbox/menu.xml /etc/xdg/openbox/menu.xml
COPY openbox/autostart /etc/xdg/openbox/autostart
COPY openbox/theme /usr/share/themes/Triste-Crimson/openbox-3
COPY cortile/cortilectl /usr/local/bin/cortilectl
COPY shell/welcome /usr/local/bin/welcome
COPY shell/chromium /usr/local/bin/chromium
COPY shell/buzznode /usr/local/bin/buzznode
COPY shell/buzznode-panel-status /usr/local/bin/buzznode-panel-status
COPY shell/agent-runtime-login /usr/local/bin/agent-runtime-login
RUN mkdir -p /etc/bash.bashrc.d
COPY shell/bashrc /etc/bash.bashrc.d/buzznode-prompt.sh
COPY browser /opt/browser
COPY tint2/tint2rc /etc/xdg/tint2/tint2rc
RUN chmod +x \
        /etc/xdg/openbox/autostart \
        /usr/local/bin/cortilectl \
        /usr/local/bin/welcome \
        /usr/local/bin/chromium \
        /usr/local/bin/buzznode \
        /usr/local/bin/buzznode-panel-status \
        /usr/local/bin/agent-runtime-login && \
    echo '[ -d /etc/bash.bashrc.d ] && for f in /etc/bash.bashrc.d/*.sh; do . "$f"; done' \
        >> /etc/bash.bashrc

RUN mkdir -p /usr/share/xsessions && \
    printf '[Desktop Entry]\nName=Openbox\nExec=openbox-session\nType=Application\n' \
        > /usr/share/xsessions/openbox.desktop

USER agent

RUN mkdir -p "$HOME/.config/cortile"
COPY --chown=agent:agent cortile/cortile-config.toml /home/buzznode/.config/cortile/config.toml

RUN printf '#!/bin/bash\nexec openbox-session\n' > "$HOME/.vnc/xstartup" && \
    chmod +x "$HOME/.vnc/xstartup" && \
    touch "$HOME/.vnc/.de-was-selected" && \
    printf 'network:\n  ssl:\n    require_ssl: false\n  websocket_port: 6901\n' \
        > "$HOME/.vnc/kasmvnc.yaml"

USER root

COPY init.sh /init
RUN chmod +x /init

EXPOSE 6901
WORKDIR /workspace
VOLUME ["/workspace", "/home/buzznode/.config", "/home/buzznode/.local/share", "/home/buzznode/.buzz", "/home/buzznode/.codex", "/home/buzznode/.claude"]

HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=6 \
    CMD curl -fsS http://127.0.0.1:6901/ >/dev/null || exit 1

ENTRYPOINT ["/init"]
