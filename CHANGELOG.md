# Changelog

All notable changes to Buzznode are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.5.5] - 2026-07-31

### Fixed

- Update the shared Launcher desktop base to `0.1.3`, preserving host-managed
  ownership for the persistent configuration and data mounts used by Apple
  `container`.

## [0.5.4] - 2026-07-30

### Added

- Expose the shared desktop screenshot endpoint as the Launcher `preview`
  interface.

### Changed

- Update the shared Launcher desktop base to `0.1.2`.

## [0.5.3] - 2026-07-30

### Changed

- Replace the single Launcher viewer and container port with the `desktop`
  `kasmweb` interface required by application schema version 2.

## [0.5.2] - 2026-07-30

### Changed

- Remove fixed desktop-resolution configuration from the Launcher manifest
  and local Docker workflow. KasmVNC now sizes the remote desktop for the
  connected viewer.
- Remove the unused product-version copy from the Launcher application
  document. The root `VERSION` file remains authoritative.
- Update the shared Launcher desktop base to `0.1.1`.

## [0.5.1] - 2026-07-30

### Changed

- Publish the Launcher application definition and artwork as an OCI artifact
  attached to the final multi-architecture image digest.

## [0.5.0] - 2026-07-30

### Changed

- Update the Buzz headless tools to `0.5.2` from upstream commit `3e48f1b`.
- Re-cut the desktop-base release. 0.4.0 moved Buzznode onto
  `launcher-image-base-desktop` but was never built and run end to end; this is
  the first version verified by booting the image and confirming the setup
  wizard opens over the Buzz wallpaper.

## [0.4.0] - 2026-07-29

### Changed

- Build on the published Launcher desktop base
  (`ghcr.io/pdparchitect/launcher-image-base-desktop`) instead of assembling
  Ubuntu, Node, KasmVNC, Openbox, and the browser here. The Dockerfile keeps
  only what is actually Buzznode: the headless Buzz tools and the coding-agent
  runtimes.
- **Breaking.** The desktop account is the base's `agent`, homed at
  `/home/agent`. Volume targets move from `/home/buzznode/...` to
  `/home/agent/...`; an existing node must remount its volumes at the new paths
  or be re-enrolled from a fresh set. The Launcher catalog manifest is updated.
- **Breaking.** `BUZZNODE_RESOLUTION` and `BUZZNODE_VNC_STATS` are replaced by
  the base's `DESKTOP_RESOLUTION` and `DESKTOP_VNC_STATS`. Every other
  `BUZZNODE_*` variable is unchanged.
- Declare ports the way the other Launcher products do: the desktop's `6901` is
  inherited from the base rather than redeclared, and this image adds no
  `EXPOSE` or `HEALTHCHECK` of its own.
- The agent harness log moves from `/var/log/buzznode` to the base's
  `/var/log/launcher-desktop`.
- Product files are installed through `overlay/`, which is copied over the
  base's defaults, rather than through per-file `COPY` instructions. The
  entrypoint is the base's: the setup wizard and the node greeting are both
  reached through `desktop-welcome`, and the harness starts from
  `/etc/desktop/session.d/10-buzznode-harness`.

### Removed

- The Openbox, Cortile, KasmVNC, GTK-theme, and browser-wrapper sources, along
  with `init.sh`. All of them are the desktop base's now. What remains is the
  Buzz wallpaper, favicon, landing page, accent colours, root menu, and the
  panel entry that opens `buzznode status`.

### Fixed

- The wallpaper is a full-canvas SVG pattern rather than a 37px tile. The base
  applies wallpapers with `feh --bg-fill`, which would have scaled the old tile
  into a single enormous dot. It also carries no XML comment: the imlib2 loader
  feh uses rejects any SVG containing one, and the desktop then comes up with no
  wallpaper at all. `make check` guards both.

- Refresh the Launcher catalogue screenshot from the rebuilt desktop.

## [0.3.0] - 2026-07-28

### Changed

- Update the Buzz headless tools to 0.5.0 from upstream commit `4a977c5`.

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
