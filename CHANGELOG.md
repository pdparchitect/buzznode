# Changelog

All notable changes to Buzznode are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-07-27

### Added

- Publish one multi-architecture Buzznode image for `linux/amd64` and
  `linux/arm64`, with native builds and headed-browser smoke tests for both
  architectures before their digests are combined into a release manifest.
- Build the pinned headless Buzz tools from their exact upstream source commit
  on ARM64, where upstream does not publish a Linux package.

### Changed

- Keep Google Chrome on AMD64 and use signed Debian Chromium on ARM64 behind
  the same launcher, Buzz-branded GTK theme, managed policy, and desktop
  integration.
- Select native Buzz, Goose, yq, Cortile, and KasmVNC artifacts for the target
  architecture, and let local builds select the host architecture by default.
- Pin GTK and Chrome's Linux UI typography to Noto Sans 9, matching every
  Openbox title, menu, and on-screen-display font declaration instead of
  inheriting GTK's larger Sans 10 default.
- Give Chrome a self-contained, Buzz-branded near-black GTK system theme that
  darkens native menus and popups as well as the tab strip, active tab,
  toolbar, controls, and address field; render Chrome's window controls from
  the same XBM masks and state colors as Openbox, square the GTK-controlled
  outer frame corners, and replace the bundled welcome card with the
  terminal's ASCII banner on pure black.
- Remove the window handle, which drew a second line under the client area
  with a resize grip boxed off at each end. Resizing stays available through
  the window edges and corners and through Alt+right-drag anywhere on the
  frame.
- Declare Codex's sandbox mode as `danger-full-access` at boot. Codex sandboxes
  commands with bubblewrap, which cannot create a user namespace inside the
  container, so no sandbox mode is enforceable and Codex warned on every start
  about falling back to its bundled copy. Override with `BUZZNODE_CODEX_SANDBOX_MODE`.
- Start terminals in `/workspace` instead of the home directory, so the desktop
  and the agent harness work in the same tree. Openbox chdirs to `$HOME` at
  startup whatever directory it was started from and hands that to everything
  it launches, so this is set in the shell - the one place every terminal
  passes through - and only when the shell landed in `$HOME`, which leaves
  non-interactive shells and deliberate directories alone.
- Widen the window grab margin with client padding. With the handle gone the
  frame offered 1px to grab at the bottom against a 28px titlebar, so the
  bottom corners were nearly unhittable. Client padding adds frame around the
  client and paints it in the frame background, taking the grabbable ring from
  1px to 7px without drawing anything new.

### Fixed

- Record the workspace as trusted for Codex and Claude Code at boot. Both
  prompt once per directory before working in it, and `codex-acp` consults the
  same `trust_level`, so the harness `buzznode launch` starts unattended in
  `/workspace` would stop on a prompt nobody is present to answer, with the
  reason buried in its log. Set `BUZZNODE_TRUST_WORKSPACE=false` to keep the
  prompts.

## [0.1.0] - 2026-07-26

### Added

- Create a persistent, browser-accessible Linux computer for one Buzz agent.
- Run that agent through the headless `buzz-acp` harness against an existing
  external relay. The image contains no Buzz Desktop, relay, database, or
  object store, and has no runtime dependency on any particular Buzz client.
- Add a terminal-first setup wizard for the relay URL, optional API token, and
  Codex, Claude Code, or Goose runtime.
- Add agent-identity setup and direct `buzz-acp` lifecycle management.
- Add sensitive Buzzbox enrollment-bundle import so a stopped managed agent's
  identity, authorization, relay, and response policy move together.
- Validate the relay URL, private key, owner authorization, and allowlist
  before reporting that an enrollment bundle was accepted.
- Add `allowlist` response-policy configuration and validation.
- Add node status, diagnostics, lifecycle, runtime-login, and log commands.
- Route the desktop log menu through `buzznode logs` and keep shell commands on
  single lines so Openbox cannot split arguments into unintended commands.
- Add an interactive runtime authentication chooser. Codex offers device code,
  desktop browser, API key, and status flows; Claude Code offers subscription,
  Console, long-lived setup token, SSO, and status flows.
- Keep setup windows open as normal terminal sessions after confirmation.
- Add ANSI headings, steps, success states, warnings, errors, diagnostics, and
  styled prompts to the Buzznode CLI, with `NO_COLOR` support.
- Add optional `BUZZ_NETWORK` support for pairing with an independent Buzzbox
  project over a private Docker network.
- Add `make connection-test` for verifying the configured external relay.
- Persist the desktop, workspace, Buzz nest, and agent-runtime state in
  dedicated volumes, normalizing ownership once per volume lifetime rather
  than on every boot.
- Enable KasmVNC `hw3d` and Chrome's GPU flags only when the desktop user can
  actually open the render node, and pass through only `/dev/dri/renderD*`
  rather than the whole `/dev/dri` directory, which would also hand over the
  `card*` DRM master/modesetting node. The startup log distinguishes an absent
  render node from an inaccessible one.
- Add `make size-report` and `tools/size-report.sh`, which measure the
  graphical stack's share of the image as an apt dependency closure.
- Document the graphical stack's measured cost, the rationale for keeping it,
  and its role as the computer-use substrate in `IMAGE-SIZE.md`.
- Add node-specific shell tests, container smoke checks, and release workflows.
