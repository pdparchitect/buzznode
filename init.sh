#!/bin/bash
# Buzznode container entrypoint.
# Starts one persistent browser-accessible desktop that connects to an external
# Buzz relay. Buzznode deliberately runs no relay or backing data services.

set -euo pipefail

export HOME=/home/buzznode
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"

agent_uid="$(id -u agent)"
export XDG_RUNTIME_DIR="/run/user/${agent_uid}"

resolution="${BUZZNODE_RESOLUTION:-1920x1080}"
if [[ ! "$resolution" =~ ^[0-9]{3,5}x[0-9]{3,5}$ ]]; then
    echo "[buzznode] invalid BUZZNODE_RESOLUTION: $resolution" >&2
    exit 1
fi

width="${resolution%x*}"
height="${resolution#*x}"

mkdir -p \
    "$HOME/.vnc" \
    "$HOME/.config/buzznode" \
    "$HOME/.local/share/applications" \
    "$HOME/.buzz" \
    "$HOME/.codex" \
    "$HOME/.claude" \
    "$XDG_RUNTIME_DIR" \
    /workspace \
    /var/log/buzznode \
    /tmp/.X11-unix

# Keep the durable workspace and the agent's home available as Ranger
# bookmarks without replacing any bookmarks the user has already assigned.
ranger_data_dir="$XDG_DATA_HOME/ranger"
ranger_bookmarks="$ranger_data_dir/bookmarks"
mkdir -p "$ranger_data_dir"
touch "$ranger_bookmarks"
if ! grep -q '^W:' "$ranger_bookmarks"; then
    printf 'W:/workspace\n' >> "$ranger_bookmarks"
fi
if ! grep -q '^H:' "$ranger_bookmarks"; then
    printf 'H:%s\n' "$HOME" >> "$ranger_bookmarks"
fi

# Ownership only needs normalizing once per volume lifetime. Recursing the home
# directory and the workspace on every boot walks the browser profile, the agent
# nest, and every checked-out repository, which becomes minutes of startup
# latency once they hold real data. Anything created later is created by the
# agent user already.
persistent_paths=(
    "$HOME"
    /workspace
)
ownership_stamp="$HOME/.config/buzznode/.ownership-normalized"

chown agent:agent \
    "${persistent_paths[@]}" \
    "$XDG_RUNTIME_DIR" \
    /var/log/buzznode

if [ ! -e "$ownership_stamp" ]; then
    chown -R agent:agent "${persistent_paths[@]}" /var/log/buzznode
    touch "$ownership_stamp"
    chown agent:agent "$ownership_stamp"
    echo "[buzznode] normalized ownership of the persistent volumes"
fi

chmod 700 "$XDG_RUNTIME_DIR" "$HOME/.config/buzznode"
chmod 1777 /tmp/.X11-unix

if getent group ssl-cert >/dev/null 2>&1; then
    usermod -a -G ssl-cert agent
fi

# Codex and Claude Code each prompt once per directory before working in it
# ("Do you trust the contents of this directory?"). `buzznode launch` runs the
# harness unattended - it does `cd /workspace` and execs buzz-acp with
# codex-acp, backgrounded into a log file - so there is nobody present to
# answer, and the agent would sit on the prompt with the reason buried in the
# log. codex-acp consults trust_level, so record the decision at boot instead.
#
# This grants no access the harness is not already started with. Set
# BUZZNODE_TRUST_WORKSPACE=false to leave both prompts in place.
harness_workdir="${BUZZNODE_HARNESS_WORKDIR:-/workspace}"
codex_config="$HOME/.codex/config.toml"

# Codex sandboxes the commands it runs with bubblewrap, and warns when it has to
# fall back to its bundled copy. Neither copy can work here: the container blocks
# unprivileged user namespaces, so bwrap cannot create one, and installing the
# distro package only adds a second binary that fails the same way. Declare the
# mode that matches reality rather than leaving a config that implies an
# isolation boundary which is not there - the boundary is the container itself.
#
# Set BUZZNODE_CODEX_SANDBOX_MODE to read-only or workspace-write to choose a
# different mode, or to an empty value to leave the setting out entirely.
codex_sandbox_mode="${BUZZNODE_CODEX_SANDBOX_MODE-danger-full-access}"
if [ -n "$codex_sandbox_mode" ] &&
    ! grep -Eq '^sandbox_mode *=' "$codex_config" 2>/dev/null; then
    codex_sandbox_tmp="$(mktemp)"
    # Prepended, not appended: sandbox_mode is a top-level key, and TOML assigns
    # any key following a [table] header to that table. The trust block below
    # writes [projects."..."] tables, so appending would quietly turn this into a
    # per-project setting instead of a global one.
    {
        printf 'sandbox_mode = "%s"\n\n' "$codex_sandbox_mode"
        [ -s "$codex_config" ] && cat "$codex_config"
    } > "$codex_sandbox_tmp"
    install -m 0600 -o agent -g agent "$codex_sandbox_tmp" "$codex_config"
    rm -f "$codex_sandbox_tmp"
    echo "[buzznode] set Codex sandbox_mode=$codex_sandbox_mode" \
        "(no usable bubblewrap in a container)"
fi

if [ "${BUZZNODE_TRUST_WORKSPACE:-true}" = "true" ]; then
    if ! grep -Fq "[projects.\"$harness_workdir\"]" "$codex_config" 2>/dev/null; then
        printf '\n[projects."%s"]\ntrust_level = "trusted"\n' \
            "$harness_workdir" >> "$codex_config"
        chown agent:agent "$codex_config"
        echo "[buzznode] recorded $harness_workdir as trusted for Codex"
    fi

    claude_config="$HOME/.claude.json"
    if ! jq -e --arg dir "$harness_workdir" \
        '.projects[$dir].hasTrustDialogAccepted == true' \
        "$claude_config" >/dev/null 2>&1; then
        [ -s "$claude_config" ] || echo '{}' > "$claude_config"
        claude_trust_tmp="$(mktemp)"
        # Leave the file untouched if it is not valid JSON rather than
        # replacing a config the operator may have hand-written.
        if jq --arg dir "$harness_workdir" \
            '.projects[$dir].hasTrustDialogAccepted = true' \
            "$claude_config" > "$claude_trust_tmp" 2>/dev/null; then
            install -m 0600 -o agent -g agent \
                "$claude_trust_tmp" "$claude_config"
            echo "[buzznode] recorded $harness_workdir as trusted for Claude Code"
        fi
        rm -f "$claude_trust_tmp"
    fi
fi

# Use a GPU only when the host exposes a render node *and* the desktop user can
# open it; otherwise keep software rendering. A passed-through node is normally
# root:render 0660 and the host's render group does not exist in this image, so
# presence alone does not mean usable. Announcing hw3d in that case leaves Xvnc
# and Chrome retrying against a device they cannot open.
gpu_node=""
gpu_node_blocked=""
for node in /dev/dri/renderD*; do
    [ -e "$node" ] || continue
    printf -v node_q '%q' "$node"
    if su -s /bin/bash -c "test -r $node_q && test -w $node_q" agent; then
        gpu_node="$node"
        break
    fi
    gpu_node_blocked="$node"
done

if [ -n "$gpu_node" ]; then
    gpu_config="  gpu:
    hw3d: true
    drinode: $gpu_node"
    echo "[buzznode] GPU acceleration enabled via $gpu_node"
else
    gpu_config="  gpu:
    hw3d: false"
    if [ -n "$gpu_node_blocked" ]; then
        echo "[buzznode] $gpu_node_blocked is not readable by the agent user;" \
            "using software rendering"
    else
        echo "[buzznode] no GPU render node found; using software rendering"
    fi
fi

cat > "$HOME/.vnc/kasmvnc.yaml" <<YAML
network:
  protocol: http
  ssl:
    require_ssl: false
  interface: 0.0.0.0
  websocket_port: 6901

desktop:
  resolution:
    width: $width
    height: $height
  pixel_depth: 24
$gpu_config

encoding:
  max_frame_rate: 30

security:
  brute_force_protection:
    blacklist_threshold: 0
YAML

if [ "${BUZZNODE_VNC_STATS:-false}" = "true" ]; then
    cat >> "$HOME/.vnc/kasmvnc.yaml" <<'YAML'

logging:
  log_writer_name: EncodeManager
  log_dest: logfile
  level: 100
YAML
    echo "[buzznode] KasmVNC encoder statistics enabled"
fi

cat > "$HOME/.vnc/xstartup" <<'XSTARTUP'
#!/bin/bash
exec openbox-session
XSTARTUP
chmod +x "$HOME/.vnc/xstartup"
touch "$HOME/.vnc/.de-was-selected"
chown -R agent:agent "$HOME/.vnc"

# KasmVNC checks these even while browser authentication and TLS are disabled.
su -s /bin/bash -c '
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$HOME/.vnc/self.pem" \
        -out "$HOME/.vnc/self.pem" \
        -subj "/CN=buzznode" >/dev/null 2>&1
    printf "buzznode\nbuzznode\n" | kasmvncpasswd -u agent -wo >/dev/null 2>&1 || true
' agent

# shellcheck disable=SC2329
cleanup() {
    echo "[buzznode] stopping"
    su -s /bin/bash -c 'kasmvncserver -kill :1 >/dev/null 2>&1 || true' agent
    pkill -TERM -u agent -f '(^|/)buzz-acp($| )' 2>/dev/null || true
}
trap cleanup EXIT INT TERM

su -s /bin/bash -c 'kasmvncserver -kill :1 >/dev/null 2>&1 || true' agent
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

su -s /bin/bash -c "
    export HOME='$HOME'
    export DISPLAY=:1
    export XDG_CONFIG_HOME='$XDG_CONFIG_HOME'
    export XDG_DATA_HOME='$XDG_DATA_HOME'
    export XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR'
    exec kasmvncserver :1 \
        -disableBasicAuth \
        -interface 0.0.0.0 \
        -websocketPort 6901 \
        -publicIP 127.0.0.1 \
        -geometry '$resolution' \
        -depth 24 \
        -httpd /usr/share/kasmvnc/www \
        -BlacklistThreshold 0 \
        -FreeKeyMappings
" agent >>/var/log/buzznode/kasmvnc.log 2>&1 &

for attempt in $(seq 1 40); do
    if curl -fsS http://127.0.0.1:6901/ >/dev/null 2>&1; then
        echo "[buzznode] desktop ready at http://localhost:6901"
        break
    fi
    if [ "$attempt" -eq 40 ]; then
        echo "[buzznode] KasmVNC did not become ready" >&2
        tail -n 100 /var/log/buzznode/kasmvnc.log >&2 || true
        exit 1
    fi
    sleep 1
done

while curl -fsS http://127.0.0.1:6901/ >/dev/null 2>&1; do
    sleep 5
done

echo "[buzznode] browser environment stopped unexpectedly" >&2
exit 1
