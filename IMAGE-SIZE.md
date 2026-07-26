# Image size and the graphical stack

Buzznode runs its agent through the headless `buzz-acp` harness, yet roughly a
quarter of the image is a graphical desktop. This document records what that
costs, why it is there, and which parts have been trimmed.

Regenerate every number here with:

```bash
make build
make size-report
```

## Measured composition

`pdparchitect/buzznode:local`, **3.54 GB** (3380 MiB) uncompressed:

| Layer                                   |   Size |
| --------------------------------------- | -----: |
| Codex, Claude Code, and the ACP adapters | 1.31 GB |
| Core apt baseline                        |  516 MB |
| Desktop apt layer                        |  466 MB |
| Google Chrome                            |  441 MB |
| Goose                                    |  299 MB |
| Node.js 24                               |  197 MB |
| Docker and GitHub CLIs                   | 88.6 MB |
| Ubuntu base                              | 78.1 MB |
| Buzz headless binaries                   |   70 MB |
| KasmVNC                                  | 35.3 MB |

The graphical substrate is **899 MiB, or 26.6% of the image**. It is not the
largest contributor: the three coding CLIs alone are larger.

Measured as a dependency closure — what apt would remove if the desktop
top-level packages were purged — so transitively shared libraries are counted
once and attributed correctly:

| Component                             |     Size |
| ------------------------------------- | -------: |
| Chrome                                | 413.6 MiB |
| Mesa and LLVM software GL             | 186.1 MiB |
| Fonts and icon themes                 | 144.3 MiB |
| KasmVNC and its perl dependencies     |  36.1 MiB |
| Ghostscript, via openbox/tint2 imlib2 |  26.3 MiB |
| GTK, Pango, GStreamer                 |  23.8 MiB |
| kitty terminal                        |  18.8 MiB |
| X11 server and utilities              |   7.7 MiB |
| Openbox, tint2, picom                 |   5.2 MiB |
| Other shared libraries                |  37.3 MiB |

Plus 13 MB of non-package assets: the cortile binary, the patched KasmVNC web
client, the Openbox theme, and the wallpaper.

**The desktop itself is nearly free.** Openbox, tint2, picom, the X utilities,
and cortile together are about 22 MiB. The weight is Chrome, software GL, and
fonts — three things that exist to make the display *useful*, not to make it
exist.

## Why a headless node ships a desktop

Buzznode's agent does not need a desktop to answer a Buzz message. The desktop
is there for three reasons, and the third is the one that matters going
forward.

**1. The node is meant to be inspectable.** A long-lived agent computer that
cannot be looked at is difficult to trust or debug. The desktop provides a
terminal, a file manager, and a browser against the same filesystem and process
namespace the agent is working in.

**2. Runtime authentication genuinely requires a browser.** `agent-runtime-login`
drives Codex and Claude Code sign-in. Device-code, Console, and SSO flows all
end at a real browser session, and doing that inside the node keeps the
resulting credentials in the node's own volumes rather than pasted in from
somewhere else.

**3. Computer use.** This is the forward-looking rationale, and it applies to
Buzznode more than to Buzzbox.

## Computer use

The graphical stack is not overhead awaiting removal — it is the substrate for
letting the agent drive a real computer, and Buzznode already contains the
complete toolchain:

| Capability          | Component                | Present |
| ------------------- | ------------------------ | ------- |
| Screen capture      | `scrot`                  | yes     |
| Input injection     | `xdotool`                | yes     |
| Window management   | `wmctrl`, Openbox        | yes     |
| Target application  | Google Chrome            | yes     |
| Display server      | Xvnc, via KasmVNC        | yes     |
| Human co-observation| KasmVNC in a browser     | yes     |

Nothing needs to be added to give the agent a mouse, a keyboard, and eyes. The
same `:1` display that a human watches through KasmVNC is the display an agent
can screenshot and click, which means a human can watch a computer-use session
live and take over mid-task.

This shapes what is worth trimming. Chrome is the single largest graphical item
at 414 MiB, and it is also precisely the surface a computer-use agent operates.
Fonts are 144 MiB, and font coverage is what stops screenshots from rendering
as tofu boxes that a vision model cannot read. Both stay.

Buzznode is the better home for this than Buzzbox: it is one persistent
computer for one agent, with its own volumes, browser profile, and login state.
That is the natural unit for a computer-use session.

## What was trimmed

KasmVNC supplies its own X server, so the packages Ubuntu ships for driving
real display hardware were never reachable:

| Removed              | Why                                                                |
| -------------------- | ------------------------------------------------------------------ |
| `xorg` metapackage   | Pulls `xserver-xorg-core`, input/video drivers, `keyboard-configuration`, and `udev`/`systemd` for hardware the container does not have. |
| `x11-xserver-utils`  | Its only consumer would be the `xrdb` call in KasmVNC's generated `xstartup`, and `xstartup` is replaced with `exec openbox-session`. It also drags in `cpp`/`gcc-13`. |

Together: **64 packages, about 90 MiB**, taking `systemd`, `udev`, `man-db`,
and the apport chain out of an agent container as a side benefit.

`xauth`, `xkb-data`, `x11-xkb-utils`, and `xfonts-base` are now listed
explicitly in the Dockerfile. The first three are `kasmvncserver` dependencies
and the fourth supplies the core font path Xvnc is started with; naming them
means no future autoremove can take them out.

Verified after the change: Xvnc, Openbox, and tint2 start; 967 core fonts
resolve; `scrot`, `xdotool`, and `wmctrl` work; Chrome launches and maps a
window; KasmVNC serves on 6901; and `make check` and the `make smoke`
assertions pass.

## What is deliberately kept

| Kept                       |     Size | Reason                                                                 |
| -------------------------- | -------: | ---------------------------------------------------------------------- |
| Chrome                     | 414 MiB | Login flows today, computer-use target tomorrow.                        |
| Mesa and LLVM software GL  | 186 MiB | Hard dependency of `kasmvncserver`, `picom`, and `libgbm1`. Removing it means dropping the compositor and GL entirely. |
| Fonts and icon themes      | 144 MiB | Screenshot legibility for vision models; emoji and CJK coverage.        |
| Ghostscript chain          |  26 MiB | Structural: `openbox`'s `libobrender32v5` and `tint2` need imlib2, which needs `libspectre1`, which needs `libgs10`. Dropping `feh` alone frees only 10 MiB. |
| kitty                      |  19 MiB | The desktop's terminal, launched from Openbox autostart.               |

## Compression

All figures are uncompressed on-disk size. Registry transfer is roughly 40–50%
of these, and Chrome compresses worse than the library and font bytes, so its
share of a `docker pull` is higher than its share here.
