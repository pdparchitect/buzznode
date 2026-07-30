#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

helper="$project_dir/overlay/usr/local/bin/agent-runtime-login"
runtime_log="$temporary_dir/runtime.log"
export runtime_log

mock_runtime() {
    local input=""
    printf '%s\n' "$*" >>"$runtime_log"
    if [ "${*: -1}" = "--with-api-key" ]; then
        IFS= read -r input || true
        printf 'stdin-length=%s\n' "${#input}" >>"$runtime_log"
    fi
}
export -f mock_runtime

run_helper() {
    CODEX_COMMAND=mock_runtime \
        CLAUDE_COMMAND=mock_runtime \
        GOOSE_COMMAND=mock_runtime \
        bash "$helper" "$@" >/dev/null
}

run_helper codex device
run_helper codex browser
printf 'test-only-secret\n' |
    CODEX_COMMAND=mock_runtime bash "$helper" codex api-key >/dev/null
run_helper codex status

grep -Fxq 'login --device-auth' "$runtime_log"
grep -Fxq 'login' "$runtime_log"
grep -Fxq 'login --with-api-key' "$runtime_log"
grep -Fxq 'stdin-length=16' "$runtime_log"
grep -Fxq 'login status' "$runtime_log"
if grep -Fq 'test-only-secret' "$runtime_log"; then
    echo "Codex API key was passed as a command argument" >&2
    exit 1
fi

run_helper claude subscription
run_helper claude console
run_helper claude setup-token
run_helper claude sso
run_helper claude status

grep -Fxq 'auth login --claudeai' "$runtime_log"
grep -Fxq 'auth login --console' "$runtime_log"
grep -Fxq 'setup-token' "$runtime_log"
grep -Fxq 'auth login --sso' "$runtime_log"
grep -Fxq 'auth status' "$runtime_log"

printf '\n' |
    CODEX_LOGIN_DEFAULT=device CODEX_COMMAND=mock_runtime \
        bash "$helper" codex >/dev/null 2>/dev/null
test "$(tail -n 1 "$runtime_log")" = 'login --device-auth'

printf '\n' |
    CODEX_LOGIN_DEFAULT=browser CODEX_COMMAND=mock_runtime \
        bash "$helper" codex >/dev/null 2>/dev/null
test "$(tail -n 1 "$runtime_log")" = 'login'

run_helper goose
grep -Fxq 'configure' "$runtime_log"

if run_helper codex unknown >/dev/null 2>&1; then
    echo "Unknown Codex authentication method was accepted" >&2
    exit 1
fi

# Codex and Claude Code prompt once per directory before working in it, and
# codex-acp consults the same trust_level. `buzznode launch` starts the harness
# unattended in the workspace, so that prompt has to be settled at boot or the
# agent stops with the reason buried in its log.
grep -Fq 'BUZZNODE_TRUST_WORKSPACE' "$project_dir/overlay/etc/desktop/startup.d/05-agent-runtime-trust"
grep -Fq 'trust_level = "trusted"' "$project_dir/overlay/etc/desktop/startup.d/05-agent-runtime-trust"
grep -Fq 'hasTrustDialogAccepted' "$project_dir/overlay/etc/desktop/startup.d/05-agent-runtime-trust"
# The directory trusted at boot must be the one the harness is launched in.
grep -Fq 'BUZZNODE_HARNESS_WORKDIR:-/workspace' "$project_dir/overlay/etc/desktop/startup.d/05-agent-runtime-trust"
grep -Fq 'cd /workspace' "$project_dir/overlay/usr/local/bin/buzznode"

echo "Agent runtime login tests passed."
