#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
overlay_test_dir="$(mktemp -d)"
trap 'rm -rf "$overlay_test_dir"' EXIT

grep -Fq 'background: #000;' "$project_dir/browser/index.html"
grep -Fq '<title>Buzznode Browser</title>' "$project_dir/browser/index.html"
grep -Fq '██████╗ ██╗   ██╗███████╗███████╗███╗' \
    "$project_dir/browser/index.html"
if grep -Fq '<h1>Buzznode</h1>' "$project_dir/browser/index.html"; then
    echo "The obsolete browser welcome card is still present." >&2
    exit 1
fi

grep -Fq 'ENV GTK_THEME=Buzznode' "$project_dir/Dockerfile"
grep -Fq \
    'ENV G_RESOURCE_OVERLAYS=/org/gtk/libgtk=/usr/share/buzznode/gtk-overlay' \
    "$project_dir/Dockerfile"
grep -Fq \
    'COPY gtk/Buzznode /usr/share/themes/Buzznode' \
    "$project_dir/Dockerfile"
grep -Fq \
    'COPY gtk/generate-resource-overlay.py /tmp/generate-gtk-resource-overlay.py' \
    "$project_dir/Dockerfile"

python3 "$project_dir/gtk/generate-resource-overlay.py" \
    "$project_dir/openbox/theme" "$overlay_test_dir"
for control in minimize maximize restore close; do
    control_path="$overlay_test_dir/icons/16x16/status/window-${control}-symbolic.symbolic.png"
    test -s "$control_path"
    python3 -c \
        'import pathlib, sys; assert pathlib.Path(sys.argv[1]).read_bytes().startswith(b"\x89PNG\r\n\x1a\n")' \
        "$control_path"
done

grep -Fq '"system_theme": 1' "$project_dir/Dockerfile"
grep -Fq 'for config_dir in google-chrome chromium' \
    "$project_dir/Dockerfile"
grep -Fq '/etc/chromium/policies/managed/buzznode-policy.json' \
    "$project_dir/Dockerfile"
grep -Fq 'browser=/opt/google/chrome/google-chrome' \
    "$project_dir/shell/chromium"
grep -Fq 'browser=/usr/bin/chromium' \
    "$project_dir/shell/chromium"
grep -Fq 'exec "$browser"' \
    "$project_dir/shell/chromium"
grep -Fq 'popover.background.menu' \
    "$project_dir/gtk/Buzznode/gtk-3.0/gtk.css"
grep -Fq 'background-color: #020303;' \
    "$project_dir/gtk/Buzznode/gtk-3.0/gtk.css"
grep -Fq 'window.background.csd decoration' \
    "$project_dir/gtk/Buzznode/gtk-3.0/gtk.css"
grep -Fq 'decoration:not(:backdrop)' \
    "$project_dir/gtk/Buzznode/gtk-3.0/gtk.css"
grep -Fq 'headerbar.header-bar.titlebar' \
    "$project_dir/gtk/Buzznode/gtk-3.0/gtk.css"
grep -Fq 'border-radius: 0;' \
    "$project_dir/gtk/Buzznode/gtk-3.0/gtk.css"
grep -Fq 'padding-right: 4px;' \
    "$project_dir/gtk/Buzznode/gtk-3.0/gtk.css"
grep -Fq 'button.titlebutton:backdrop' \
    "$project_dir/gtk/Buzznode/gtk-3.0/gtk.css"
grep -Fq 'caret-color: #d7d72e;' \
    "$project_dir/gtk/Buzznode/gtk-3.0/gtk.css"
grep -Fq 'color: #dc143c;' \
    "$project_dir/gtk/Buzznode/gtk-3.0/gtk.css"
grep -Fxq 'gtk-font-name = Noto Sans 9' \
    "$project_dir/gtk/Buzznode/gtk-3.0/settings.ini"
test "$(grep -Fc '<name>Noto Sans</name>' "$project_dir/openbox/rc.xml")" -eq 6
test "$(grep -Fc '<size>9</size>' "$project_dir/openbox/rc.xml")" -eq 6

if grep -Fq '"BrowserThemeColor"' "$project_dir/Dockerfile"; then
    echo "BrowserThemeColor still overrides the GTK Chrome theme." >&2
    exit 1
fi
if grep -Fq -- '--pack-extension=' "$project_dir/Dockerfile"; then
    echo "The obsolete Chrome extension theme is still packaged." >&2
    exit 1
fi

grep -Fq 'amd64|arm64)' "$project_dir/Dockerfile"
grep -Fq 'yq_linux_${arch}' "$project_dir/Dockerfile"
grep -Fq 'kasmvncserver_noble_${KASMVNC_VERSION}_${arch}.deb' \
    "$project_dir/Dockerfile"
grep -Fq 'google-chrome-stable_current_amd64.deb' \
    "$project_dir/Dockerfile"
grep -Fq "'deb [arch=arm64 signed-by=/etc/apt/keyrings/debian-archive-key-12.asc] https://deb.debian.org/debian bookworm main'" \
    "$project_dir/Dockerfile"
grep -Fq 'apt-get install -y --no-install-recommends chromium' \
    "$project_dir/Dockerfile"
grep -Fq 'git clone --branch "v${BUZZ_VERSION}" --depth 1' \
    "$project_dir/Dockerfile"
grep -Fq 'FROM rust:1.95-bookworm AS buzz-tools' \
    "$project_dir/Dockerfile"
grep -Fq 'test "$(git rev-parse HEAD)" = "$BUZZ_SOURCE_SHA"' \
    "$project_dir/Dockerfile"
grep -Fq 'arm64) goose_arch=aarch64' "$project_dir/Dockerfile"
if grep -Fq 'Buzznode currently supports linux/amd64 only' \
    "$project_dir/Dockerfile"; then
    echo "The Dockerfile still rejects ARM64 builds." >&2
    exit 1
fi

grep -Fq 'TARGETARCH ?= $(word 2,$(subst /, ,$(PLATFORM)))' \
    "$project_dir/Makefile"
grep -Fq -- '--build-arg "TARGETARCH=$(TARGETARCH)"' \
    "$project_dir/Makefile"
grep -Fq 'PLATFORM ?= linux/$(NATIVE_ARCH)' \
    "$project_dir/Makefile"

ci_workflow="$project_dir/.github/workflows/ci.yaml"
release_workflow="$project_dir/.github/workflows/release.yaml"
for workflow in "$ci_workflow" "$release_workflow"; do
    grep -Fq 'platform: linux/amd64' "$workflow"
    grep -Fq 'platform: linux/arm64' "$workflow"
    grep -Fq 'runner: ubuntu-24.04-arm' "$workflow"
done
grep -Fq 'bash tests/smoke-container.sh "$container" "$ARCH"' \
    "$ci_workflow"
grep -Fq 'push-by-digest=true' "$release_workflow"
grep -Fq 'merge-multiple: true' "$release_workflow"
grep -Fq 'docker buildx imagetools create' "$release_workflow"
