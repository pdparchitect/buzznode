#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

export HOME="$temporary_dir/home"
export BUZZNODE_CONFIG_DIR="$HOME/.config/buzznode"
mkdir -p "$HOME"

cli="$project_dir/overlay/usr/local/bin/buzznode"
token='token with spaces and $shell characters'
private_key='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
auth_tag='{"kind":"owner delegation","value":"$secret"}'

"$cli" configure \
    --relay-url 'wss://team.example.com' \
    --private-key "$private_key" \
    --auth-tag "$auth_tag" \
    --api-token "$token" \
    --runtime codex >/dev/null

test -f "$BUZZNODE_CONFIG_DIR/environment"
test "$(stat -c '%a' "$BUZZNODE_CONFIG_DIR/environment")" = "600"

# shellcheck disable=SC1090
source "$BUZZNODE_CONFIG_DIR/environment"
test "$BUZZ_RELAY_URL" = "wss://team.example.com"
test "$BUZZ_PRIVATE_KEY" = "$private_key"
test "$BUZZ_AUTH_TAG" = "$auth_tag"
test "$BUZZ_API_TOKEN" = "$token"
test "$BUZZNODE_RUNTIME" = "codex"
test "$BUZZ_ACP_AGENT_COMMAND" = "codex-acp"
test "$BUZZ_ACP_AGENT_ARGS" = ""
test "$BUZZ_ACP_MCP_COMMAND" = "buzz-dev-mcp"
test "$BUZZ_ACP_RESPOND_TO" = "anyone"

"$cli" configured
status_output="$("$cli" status)"
grep -q 'Relay:         wss://team.example.com' <<<"$status_output"
grep -q 'Agent key:     configured' <<<"$status_output"
for secret in "$private_key" "$auth_tag" "$token"; do
    if grep -Fq "$secret" <<<"$status_output"; then
        echo "status leaked a stored agent credential" >&2
        exit 1
    fi
done

color_status_output="$(env -u NO_COLOR FORCE_COLOR=1 "$cli" status)"
grep -Fq $'\033[' <<<"$color_status_output"
plain_status_output="$(FORCE_COLOR=1 NO_COLOR=1 "$cli" status)"
if grep -Fq $'\033[' <<<"$plain_status_output"; then
    echo "NO_COLOR did not disable Buzznode styling" >&2
    exit 1
fi

panel_status="$project_dir/overlay/usr/local/bin/desktop-panel-status"
mock_bin="$temporary_dir/bin"
mkdir -p "$mock_bin"
ln -s "$cli" "$mock_bin/buzznode"

unconfigured_panel_output="$(
    env -u BUZZ_RELAY_URL -u BUZZ_PRIVATE_KEY \
        PATH="$mock_bin:$PATH" \
        BUZZNODE_CONFIG_DIR="$temporary_dir/unconfigured" \
        "$panel_status"
)"
grep -Fq 'Set up Buzznode' <<<"$unconfigured_panel_output"

configured_panel_output="$(PATH="$mock_bin:$PATH" "$panel_status")"
grep -Eq '(running|stopped)' <<<"$configured_panel_output"

overlay_dir="$project_dir/overlay"
normalized_menu="$(
    tr '\n\t' '  ' < "$overlay_dir/etc/xdg/openbox/menu.xml" | tr -s ' '
)"
grep -Fq 'buzznode setup; exec bash' <<<"$normalized_menu"
grep -Fq 'kitty --title "Agent Harness Log" -e buzznode logs' \
    <<<"$normalized_menu"

# The session entry points the desktop base calls into. The wizard opens for an
# unenrolled node and the harness only starts once there is an identity, so
# both branches have to be present.
welcome="$overlay_dir/usr/local/bin/desktop-welcome"
grep -Fq 'buzznode setup; exec bash' "$welcome"
grep -Fq 'buzznode-greeting; exec bash' "$welcome"
grep -Fq 'buzznode start' \
    "$overlay_dir/etc/desktop/session.d/10-buzznode-harness"

# This image ships a tint2rc only to add the tooltip and the click action.
grep -Fq 'panel_items = PTSEC' "$overlay_dir/etc/xdg/tint2/tint2rc"
grep -Fq 'execp_command = desktop-panel-status' \
    "$overlay_dir/etc/xdg/tint2/tint2rc"
grep -Fq 'buzznode status; exec bash' "$overlay_dir/etc/xdg/tint2/tint2rc"
test -s "$overlay_dir/usr/share/kasmvnc/www/assets/favicon.svg"

if "$cli" configure --relay-url 'https://not-a-websocket.example.com' \
    --private-key "$private_key" >/dev/null 2>&1; then
    echo "configure accepted a non-WebSocket relay URL" >&2
    exit 1
fi

if "$cli" configure --relay-url 'wss://team.example.com' \
    --private-key "$private_key" --runtime unknown >/dev/null 2>&1; then
    echo "configure accepted an unknown runtime" >&2
    exit 1
fi

if "$cli" configure --relay-url 'wss://team.example.com' \
    --private-key "$private_key" --respond-to owner-only >/dev/null 2>&1; then
    echo "configure accepted owner-only mode without owner credentials" >&2
    exit 1
fi

if "$cli" configure --relay-url 'wss://team.example.com' \
    --private-key "$private_key" --respond-to allowlist >/dev/null 2>&1; then
    echo "configure accepted allowlist mode without public keys" >&2
    exit 1
fi

allowlist_key='1111111111111111111111111111111111111111111111111111111111111111'
enrollment_json="$(
    jq -nc \
        --arg private_key "$private_key" \
        --arg auth_tag "$auth_tag" \
        --arg allowlist_key "$allowlist_key" \
        '{
            version: 1,
            name: "Node agent",
            relay_url: "wss://enrollment.example.com",
            private_key: $private_key,
            auth_tag: $auth_tag,
            respond_to: "allowlist",
            respond_to_allowlist: [$allowlist_key]
        }'
)"
enrollment_bundle="buzznode-v1:$(
    printf '%s' "$enrollment_json" | base64 --wrap=0
)"
enrollment_dir="$temporary_dir/enrollment"
printf '%s\n' "$enrollment_bundle" |
    BUZZNODE_CONFIG_DIR="$enrollment_dir" "$cli" configure \
        --enrollment-stdin --runtime claude >/dev/null

# shellcheck disable=SC1090
source "$enrollment_dir/environment"
test "$BUZZ_RELAY_URL" = "wss://enrollment.example.com"
test "$BUZZ_PRIVATE_KEY" = "$private_key"
test "$BUZZ_AUTH_TAG" = "$auth_tag"
test "$BUZZ_ACP_RESPOND_TO" = "allowlist"
test "$BUZZ_ACP_RESPOND_TO_ALLOWLIST" = "$allowlist_key"
test "$BUZZNODE_RUNTIME" = "claude"

if printf '%s\n' 'buzznode-v1:not-base64' |
    BUZZNODE_CONFIG_DIR="$temporary_dir/invalid-enrollment" \
        "$cli" configure --enrollment-stdin >/dev/null 2>&1; then
    echo "configure accepted an invalid enrollment bundle" >&2
    exit 1
fi

empty_relay_json="$(
    jq -c '.relay_url = ""' <<<"$enrollment_json"
)"
empty_relay_bundle="buzznode-v1:$(
    printf '%s' "$empty_relay_json" | base64 --wrap=0
)"
empty_relay_error="$temporary_dir/empty-relay-error"
if printf '%s\n' "$empty_relay_bundle" |
    BUZZNODE_CONFIG_DIR="$temporary_dir/empty-relay-enrollment" \
        "$cli" configure --enrollment-stdin \
        >/dev/null 2>"$empty_relay_error"; then
    echo "configure accepted an enrollment bundle without a relay URL" >&2
    exit 1
fi
grep -q 'Enrollment bundle contains an invalid relay URL' \
    "$empty_relay_error"

missing_key_dir="$temporary_dir/missing-key"
env -u BUZZ_PRIVATE_KEY \
    BUZZNODE_CONFIG_DIR="$missing_key_dir" \
    BUZZ_RELAY_URL='wss://team.example.com' \
    "$cli" configured >/dev/null 2>&1 && {
        echo "configured accepted a node without an agent private key" >&2
        exit 1
    }

for runtime in claude goose; do
    runtime_dir="$temporary_dir/$runtime"
    BUZZNODE_CONFIG_DIR="$runtime_dir" "$cli" configure \
        --relay-url 'wss://team.example.com' \
        --private-key "$private_key" \
        --runtime "$runtime" >/dev/null
done

# shellcheck disable=SC1090
source "$temporary_dir/claude/environment"
test "$BUZZ_ACP_AGENT_COMMAND" = "claude-agent-acp"
test "$BUZZ_ACP_AGENT_ARGS" = ""
test -z "${BUZZ_ACP_MCP_COMMAND:-}"

# shellcheck disable=SC1090
source "$temporary_dir/goose/environment"
test "$BUZZ_ACP_AGENT_COMMAND" = "goose"
test "$BUZZ_ACP_AGENT_ARGS" = "acp"

echo "Buzznode CLI tests passed."
