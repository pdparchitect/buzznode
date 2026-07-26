# Changelog

All notable changes to Buzznode are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
