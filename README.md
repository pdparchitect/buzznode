# Buzznode

<img width="1760" height="894" alt="44340f8d-6e7f-4d1c-a11c-06e187b1f68b" src="https://github.com/user-attachments/assets/92db3018-9ce9-4415-9a38-a159dad8faca" />

Buzznode is one persistent, browser-accessible Linux computer for one
[Buzz](https://github.com/block/buzz) agent. It joins an existing Buzz
workspace and runs that agent through the headless `buzz-acp` harness.

Buzznode is not a Buzz workspace client. It does not contain Buzz Desktop, and
it does not run a relay, database, object store, or other server-side Buzz
service. Use [Buzzbox](https://github.com/pdparchitect/buzzbox) or another Buzz
client to manage the workspace, create agents, and communicate with them. Use
Buzznode to give one of those agents a dedicated browser, terminal, filesystem,
runtime login, and long-lived state.

> **Not an official Buzz project.** Buzznode is an independent, community-built
> environment that packages published Buzz releases. It is not affiliated with,
> endorsed by, or sponsored by the Buzz project, [buzz.xyz](https://buzz.xyz),
> or Block, Inc. "Buzz" is used here only to describe what this image runs and
> what it is compatible with; all trademarks belong to their respective owners.
> Report problems with Buzznode here, not to the upstream Buzz project.

<img width="3456" height="2234" alt="tpsmlhvh-6904 euw devtunnels ms_(MacBook Pro 16_)" src="https://github.com/user-attachments/assets/dd8b96bc-36fc-4978-90b9-c07fc442b2c9" />

## Quick start

You need credentials for a managed agent — either a `buzznode-v1:` enrollment
bundle, which [Buzzbox](https://github.com/pdparchitect/buzzbox) produces, or
the agent's relay URL and private key from any other Buzz client. Then:

```bash
docker run --detach \
  --name buzznode \
  --platform linux/amd64 \
  --shm-size 1g \
  --publish 127.0.0.1:6904:6901 \
  ghcr.io/pdparchitect/buzznode:latest
```

Open <http://127.0.0.1:6904>. The setup window asks for the bundle; paste it, or
press Enter to type the relay URL and private key instead. Pick Codex, Claude
Code, or Goose, and the node connects to your relay and starts handling messages
for that agent.

Buzznode targets `linux/amd64`. This command is for trying the node out: its
state lives in anonymous volumes, so replacing the container loses the
enrollment and leaves the old volumes behind on disk. For anything you intend to
keep, use the [persistent setup](#persistent-setup) below.

## Setup in detail

Create or select a managed agent in the Buzz client associated with your
relay. You need either:

- a `buzznode-v1:` enrollment bundle; or
- the relay URL, agent private key, authorization, and response policy for
  manual setup.

When using Buzzbox, its convenience flow is:

1. Right-click the Buzzbox desktop and choose **Agent Setup → Create New Agent
   for Buzznode**.
2. Complete Buzz's managed-agent form and save it.
3. Copy the `buzznode-v1:` enrollment bundle displayed by Buzzbox.

To use an existing agent instead, stop its local harness and choose **Agent
Setup → Move Existing Agent to Buzznode**.

When using another Buzz workspace, obtain the managed agent credentials through
that workspace's client or provisioning process. Buzznode does not contact,
discover, or require a Buzzbox instance.

Once the container is running, the first desktop opens a larger terminal setup
window. Paste the enrollment bundle, then choose a Codex, Claude Code, or Goose
runtime. The wizard confirms completion and waits for Enter before becoming a
normal Buzznode terminal; it does not close the window. The bundle supplies:

- the workspace relay WebSocket URL, such as `wss://buzz.example.com`;
- the agent private key;
- its authorization tag; and
- whether anyone, its owner, an allowlist, or nobody may activate it.

Buzznode separately asks for an optional relay API token because Buzzbox does
not store that token with the managed agent.

Buzznode validates the bundle's relay, private key, authorization, and response
policy before reporting that enrollment was accepted.

The enrollment bundle is base64-encoded, not encrypted, and contains the agent
private key. Treat it like a password and paste it only into Buzznode setup.
Once the node is connected, do not run the same agent's local harness in
Buzzbox.

The wizard stores connection credentials in
`~/.config/buzznode/environment` with mode `0600`, offers to configure the
selected runtime, and starts `buzz-acp`. Buzznode discovers the channels that
contain this agent and handles messages addressed to it.

### Persistent setup

A long-lived node should survive being recreated, so name its volumes and give
it a restart policy. If you already started the container above, remove it and
its anonymous volumes first with `docker rm --force --volumes buzznode`.

```bash
docker run --detach \
  --name buzznode \
  --platform linux/amd64 \
  --restart unless-stopped \
  --shm-size 1g \
  --publish 127.0.0.1:6904:6901 \
  --volume buzznode-workspace:/workspace \
  --volume buzznode-config:/home/buzznode/.config \
  --volume buzznode-data:/home/buzznode/.local/share \
  --volume buzznode-nest:/home/buzznode/.buzz \
  --volume buzznode-codex:/home/buzznode/.codex \
  --volume buzznode-claude:/home/buzznode/.claude \
  ghcr.io/pdparchitect/buzznode:latest
```

Setup then runs once. Enrollment, runtime login, browser sessions, and working
files stay put across `docker rm` and image upgrades. See
[Persistence](#persistence) for what each volume holds, and
[One node, one agent](#one-node-one-agent) for running more than one.

### Unattended provisioning

To skip the wizard, configure the node from its terminal:

```bash
printf '%s\n' "$BUZZNODE_ENROLLMENT_BUNDLE" |
  buzznode configure --enrollment-stdin --runtime codex
buzznode runtime-login
buzznode start
```

Manual `--relay-url`, `--private-key`, `--auth-tag`, `--respond-to`, and
`--respond-to-allowlist` options remain available for non-Buzzbox clients. Use
`buzznode setup` for normal interactive configuration so secrets do not appear
in shell history. A raw key from `buzz-admin generate-key` is not a replacement
for creating a managed agent because it has no Buzz profile, owner attestation,
or channel membership.

## Deployment model

Buzznode has no runtime dependency on Buzzbox. It can connect to any compatible
Buzz relay that is reachable from the container, including a hosted relay over
`wss://`, a relay on another server, or a local development relay.

Buzzbox is only an optional onboarding convenience. Its Agent Setup menu can
create a managed agent and package the relay URL, identity, authorization, and
response policy into a `buzznode-v1:` enrollment bundle. Another Buzz client or
provisioning system can supply the same information instead.

The `buzz-local` Docker network, `ws://buzzbox:3000` relay address, and the two
projects' coordinated Makefile examples are strictly for local testing. They
are not part of the Buzznode architecture and are not required in deployment.

## How the pieces fit

```text
Any compatible Buzz workspace           Independent Buzznode
---------------------------------       ---------------------------
Create and manage workspace             Run one existing agent
Provide enrollment or credentials ----> Connect to its configured relay
Add agent to channels                   Run Codex, Claude, or Goose
Chat with and mention agent       <---- Handle messages through buzz-acp
```

The `buzz` command-line tool remains in the node because `buzz-acp` makes it
available to the running agent for Buzz messaging and tools. The graphical
`buzz-desktop` application is deliberately absent and cannot be started.

## Test locally with Buzzbox

[Buzzbox](https://github.com/pdparchitect/buzzbox) is a ready-to-run Buzz
workspace — desktop, relay, and storage in one image — which makes it the
easiest way to exercise a node end to end. The two remain independent projects;
their Makefiles coordinate only through an optional Docker network and the relay
URL.

Clone Buzzbox next to this repository, then from the `buzzbox` directory:

```bash
make up \
  BUZZ_NETWORK=buzz-local \
  PUBLIC_RELAY_URL=ws://buzzbox:3000
```

Open Buzzbox at <http://127.0.0.1:6903> and choose **Agent Setup → Create New
Agent for Buzznode**. Complete the Buzz form and copy the enrollment bundle.

From this `buzznode` directory:

```bash
make up \
  BUZZ_NETWORK=buzz-local \
  RELAY_URL=ws://buzzbox:3000
```

Open Buzznode at <http://127.0.0.1:6904>. The relay URL is prefilled in the
setup wizard for manual setup, but the recommended flow is to paste the
Buzzbox enrollment bundle. Leave the local API token empty, select a runtime,
and complete its login.

Once setup is complete, verify the saved configuration and relay connection:

```bash
make connection-test
```

The first project started creates `buzz-local`; Docker DNS resolves `buzzbox`
on that network. Each Makefile still owns only its own container. `make stop`
in either directory does not stop or remove the other project.

## One node, one agent

Create another Buzznode container with a different container name and volume
prefix for another agent. Keeping nodes isolated gives each agent its own:

- Buzz identity and harness process;
- browser sessions and runtime credentials;
- desktop and filesystem state;
- `/workspace`; and
- start, stop, restart, and logs lifecycle.

## What is included

- the headless `buzz-acp`, `buzz`, `buzz-agent`, and `buzz-dev-mcp` tools;
- Codex with `codex-acp`;
- Claude Code with `claude-agent-acp`;
- Goose with native ACP support;
- Chrome for login flows and browser-based agent tasks;
- a terminal, Git, GitHub CLI, Docker CLI, Python, Node.js, pnpm, and common
  development tools; and
- an Openbox desktop exposed through KasmVNC.

Buzznode contains no `buzz-desktop`, `buzz-relay`, PostgreSQL, Redis, or MinIO.

The desktop is about a quarter of the image. It is kept because the node is
meant to be inspectable, because runtime authentication needs a real browser,
and because it is the substrate for computer use: `scrot`, `xdotool`, `wmctrl`,
and Chrome are already present, so an agent can drive the same display a human
watches through KasmVNC. See [IMAGE-SIZE.md](IMAGE-SIZE.md) for the measured
breakdown and the reasoning, and run `make size-report` to reproduce it.

A purpose-built web application could have taken the desktop's place as the way
to reach the node: a terminal, a log view, and a file browser served over HTTP
would be far smaller than an X session. That was considered and set aside. It
would be a second product to design, build, secure, and maintain alongside the
node itself, which is not where the early effort belongs. More to the point, it
would not actually remove the graphical stack. Runtime authentication needs a
real browser, and computer use needs a real display with real input, so Chrome,
Xvnc, the fonts, and the software GL renderer stay in the image either way —
and those are the bulk of the cost. Openbox, tint2, and the rest of the desktop
shell add roughly 22 MiB on top of components already being paid for. Given
that, the node lives off the land: it surfaces what is already installed rather
than reimplementing a thinner version of it.

## Node commands

```bash
buzznode setup
buzznode status
buzznode doctor
buzznode runtime-login
buzznode runtime-login codex device
buzznode start
buzznode stop
buzznode restart
buzznode logs
```

Right-click the desktop for the same agent controls, runtime login actions,
terminal, browser, task manager, and harness logs. Runtime login opens a
chooser instead of assuming browser authentication. Codex supports device code,
desktop browser, or API-key authentication. Claude Code supports Claude
subscription, Anthropic Console, long-lived setup-token, or organization SSO
flows.

## Build locally

From this directory:

```bash
make check
make up
make smoke
```

The desktop opens at <http://127.0.0.1:6904>. Useful overrides include:

```bash
PORT=8080 RESOLUTION=1600x900 make up
DOCKER=podman make up
```

`make stop` removes the node container but preserves its named volumes.

## Pinned components

| Component           | Version   |
| ------------------- | --------- |
| Buzz headless tools | `0.4.26`  |
| Codex               | `0.145.0` |
| Claude Code         | `2.1.220` |
| Goose               | `1.44.0`  |
| Codex ACP adapter   | `1.1.7`   |
| Claude ACP adapter  | `0.62.0`  |

The Buzz `.deb` and Goose archive are SHA-256 verified during the image build.
Only the required headless Buzz binaries are extracted from the `.deb`; the
package and its desktop application are not installed.

## Persistence

Keep separate volumes for:

- `/workspace` — the node's working files;
- `~/.config` and `~/.local/share` — node, browser, desktop, and Goose state;
- `~/.buzz` — the Buzz agent nest;
- `~/.codex` — Codex state; and
- `~/.claude` — Claude Code state.

## Security

Buzznode is a trusted, single-user workstation:

- the saved agent private key can act as that agent;
- KasmVNC browser authentication and TLS are disabled;
- the `agent` user has passwordless sudo;
- coding agents can operate on `/workspace`; and
- browser sessions and agent credentials persist in volumes.

The provided Makefile binds the desktop to `127.0.0.1`. Keep that default, or
put Buzznode behind authentication, TLS, and suitable network controls. Never
publish port `6901` directly to an untrusted network, expose the saved agent
key, or reuse a human Buzz private key as the node identity.

See [RELEASES.md](RELEASES.md) for the image release process.

### Authentication is delegated by design

Access to the desktop web application is not authenticated. KasmVNC is started
with `-disableBasicAuth` and TLS disabled, and the KasmVNC password written on
first boot exists only because KasmVNC checks that the file is there. It is not
an access control and should not be treated as one.

This is a deliberate decision, and built-in authentication is not planned. A
node reachable beyond loopback is expected to be fronted by whichever access
layer already suits its environment: a conventional reverse proxy, or
preferably a zero-trust access proxy such as Cloudflare Access or an equivalent
identity-aware proxy. Those systems already own identity, session lifetime,
device posture, revocation, and audit, and in an enterprise deployment they are
the layer that has to be satisfied regardless of what the node does.

Adding a second mechanism inside the node would not strengthen that
arrangement, it would compete with it: two session models to keep aligned, two
places to revoke an operator, and an open question about which one wins when
they disagree. Leaving the node unauthenticated keeps a single enforcement
point and a single path forward — the proxy is the front door, and there is no
second door to reason about or accidentally leave open.

The practical consequence is that the loopback bind is the only boundary until
an access layer is put in front of it. Treat exposing the node without one as
publishing an unauthenticated root shell, because that is what it is.
