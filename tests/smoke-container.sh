#!/usr/bin/env bash

set -euo pipefail

container="${1:?usage: smoke-container.sh CONTAINER [ARCH]}"
expected_arch="${2:-}"
docker="${DOCKER:-docker}"

actual_arch="$("$docker" exec "$container" dpkg --print-architecture)"
if [ -n "$expected_arch" ] && [ "$actual_arch" != "$expected_arch" ]; then
    echo "Expected $expected_arch container, got $actual_arch" >&2
    exit 1
fi

"$docker" exec "$container" bash -ec '
    for command in agent-runtime-login buzznode buzz buzz-acp \
        buzz-agent buzz-dev-mcp git-credential-nostr \
        codex codex-acp claude claude-agent-acp goose chromium; do
        command -v "$command" >/dev/null || {
            echo "[smoke] FAILED: $command is not on PATH" >&2
            exit 1
        }
    done

    case "$(dpkg --print-architecture)" in
        amd64)
            test -x /opt/google/chrome/google-chrome
            test ! -x /usr/bin/chromium
            ;;
        arm64)
            test -x /usr/bin/chromium
            test ! -x /opt/google/chrome/google-chrome
            ;;
        *)
            exit 1
            ;;
    esac

    buzz --help >/dev/null
    buzz-acp --help >/dev/null
    goose --version
    chromium --version
    ! command -v buzz-desktop >/dev/null
    ! command -v buzz-relay >/dev/null
    ! command -v postgres >/dev/null
    curl -fsS http://127.0.0.1:6901/ >/dev/null
'

# The desktop base owns this contract. Product processes must be able to use
# the inherited display environment without locating or copying X11 cookies.
x_access=false
for attempt in $(seq 1 20); do
    if "$docker" exec --user agent "$container" xprop -root >/dev/null 2>&1; then
        x_access=true
        break
    fi
    sleep 1
done
if [ "$x_access" != "true" ]; then
    echo "The agent account could not authenticate to the X display." >&2
    exit 1
fi

# Prove that the architecture's actual headed browser reaches the desktop, not
# merely that its executable loader and --version path work.
"$docker" exec --detach \
    --user agent \
    --env DISPLAY=:1 \
    --env HOME=/home/agent \
    "$container" \
    chromium file:///opt/browser/index.html

browser_ready=false
for attempt in $(seq 1 30); do
    if "$docker" exec \
        --user agent \
        --env DISPLAY=:1 \
        "$container" \
        xdotool search --onlyvisible --name 'Buzznode Browser' \
        >/dev/null 2>&1; then
        browser_ready=true
        break
    fi
    sleep 1
done

if [ "$browser_ready" != "true" ]; then
    echo "The $actual_arch browser did not create a visible desktop window." >&2
    "$docker" exec "$container" ps aux >&2 || true
    exit 1
fi

"$docker" exec \
    --user agent \
    --env DISPLAY=:1 \
    "$container" \
    scrot /tmp/buzznode-browser-smoke.png
"$docker" exec "$container" test -s /tmp/buzznode-browser-smoke.png
"$docker" exec "$container" rm -f /tmp/buzznode-browser-smoke.png

echo "Buzznode container and headed browser passed on linux/$actual_arch."
