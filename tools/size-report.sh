#!/usr/bin/env bash
#
# Report how much of an image is the graphical (desktop) substrate.
#
# The graphical stack is measured as the dependency closure of the desktop
# top-level packages: whatever apt would take out if they were purged. That
# accounts for shared libraries pulled in transitively, which a naive per-
# package sum misses. Packages absent from the image are skipped, so the same
# script reports on Buzzbox and Buzznode.
#
# Usage: tools/size-report.sh [IMAGE]
set -euo pipefail

IMAGE="${1:-${IMAGE:-pdparchitect/buzznode:local}}"
DOCKER="${DOCKER:-docker}"

if ! "$DOCKER" image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Image $IMAGE not found. Run 'make build' first." >&2
    exit 1
fi

total_bytes="$("$DOCKER" image inspect "$IMAGE" --format '{{.Size}}')"

echo "Image: $IMAGE"
awk -v b="$total_bytes" 'BEGIN {printf "Total size: %.2f GB (%.0f MiB)\n", b/1e9, b/1048576}'
echo
echo "Largest layers"
echo "--------------"
"$DOCKER" history --no-trunc --format '{{.Size}}\t{{.CreatedBy}}' "$IMAGE" \
    | sort -rh | head -10 \
    | sed -E 's/\|[0-9]+ ([A-Za-z0-9_]+=[^ ]* )+//; s|/bin/(ba)?sh -o pipefail -c ||;
               s|/bin/(ba)?sh -c ||; s/#\(nop\) //; s/[[:space:]]+/ /g' \
    | cut -c1-104
echo

# The desktop top-levels. WebKit/GTK are Buzz Desktop's runtime in Buzzbox and
# absent from Buzznode; the closure handles either case.
GRAPHICAL_TOPLEVEL="
google-chrome-stable chromium chromium-common kasmvncserver
xterm dbus-x11 x11-utils x11-xserver-utils xorg
scrot openbox obconf tint2 kitty feh picom xdotool wmctrl xclip
fonts-noto fonts-noto-color-emoji xfonts-base
libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 libdrm2
libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 libgbm1
libpango-1.0-0 libasound2t64 libxshmfence1
libwebkit2gtk-4.1-0 libgtk-3-0 libgtk-3-0t64 libayatana-appindicator3-1 librsvg2-2
"

"$DOCKER" run --rm --interactive --entrypoint bash \
    --env "GRAPHICAL_TOPLEVEL=$GRAPHICAL_TOPLEVEL" \
    --env "TOTAL_BYTES=$total_bytes" \
    "$IMAGE" -s <<'INNER'
set -uo pipefail

dpkg-query -Wf '${Package}\t${Installed-Size}\n' > /tmp/sizes.txt
dpkg-query -Wf '${db:Status-Abbrev} ${Package}\n' | awk '/^ii/{print $2}' > /tmp/installed.txt

present=""
for pkg in $GRAPHICAL_TOPLEVEL; do
    grep -qx "$pkg" /tmp/installed.txt && present="$present $pkg"
done

apt-get remove --purge --autoremove --dry-run $present 2>/dev/null \
    | awk '/^(Purg|Remv) /{print $2}' | sort -u > /tmp/graphical.txt

echo "Graphical package closure"
echo "-------------------------"
awk 'NR==FNR {want[$1]=1; next}
     want[$1] {
       p=$1; s=$2
       if (p ~ /^google-chrome/ || p ~ /^chromium/)    c="Chromium-family browser"
       else if (p ~ /^libwebkit|javascriptcore/)       c="WebKitGTK (Buzz Desktop runtime)"
       # Buzzbox installs the Buzz .deb whole, so the GUI binary drags the
       # package (headless tools included) into the graphical closure.
       else if (p == "buzz")                           c="Buzz .deb (GUI binary + headless tools)"
       else if (p == "kasmvncserver" || p ~ /perl/)    c="KasmVNC and its perl deps"
       else if (p ~ /^(fonts-|xfonts-|.*-icon-theme|ubuntu-mono|yudit|poppler-data)/) c="Fonts and icon themes"
       else if (p ~ /llvm|mesa|^libgl|^libegl|^libvulkan|drm|gallium/) c="Mesa and LLVM software GL"
       else if (p ~ /^(libgs10|libspectre|ghostscript)/) c="Ghostscript (via openbox/tint2 imlib2)"
       else if (p ~ /^(cpp|gcc)/)                      c="cpp/gcc (via x11-xserver-utils)"
       else if (p ~ /^(systemd|udev|libsystemd|dbus-user-session|libpam-systemd)/) c="systemd/udev/dbus session"
       else if (p ~ /^(xserver|xorg|x11|xauth|xinit|xkb|libx|libxcb|xterm|xdotool|wmctrl|xclip|scrot|libxcvt)/) c="X11 server and utilities"
       else if (p ~ /^(openbox|obconf|tint2|picom|feh|libimlib)/) c="Window manager, panel, compositor"
       else if (p ~ /^kitty/)                          c="kitty terminal"
       else if (p ~ /gtk|gdk|pango|cairo|atk|adwaita|rsvg|gstreamer|glib/) c="GTK, Pango, GStreamer"
       else                                            c="Other shared libraries"
       kb[c] += s; n[c]++; total += s; count++
     }
     END {
       for (k in kb) printf "%9.1f MiB  %4d pkgs  %s\n", kb[k]/1024, n[k], k
       printf "%9.1f MiB  %4d pkgs  TOTAL\n", total/1024, count
       printf "%d\n", total > "/tmp/total_kb"
     }' /tmp/graphical.txt /tmp/sizes.txt | sort -rn

echo
echo "Share of image"
echo "--------------"
graphical_kb="$(cat /tmp/total_kb)"
awk -v g="$graphical_kb" -v t="$TOTAL_BYTES" 'BEGIN {
    gb = g * 1024
    printf "Graphical stack: %.0f MiB of %.0f MiB (%.1f%%)\n", gb/1048576, t/1048576, 100*gb/t
    printf "Everything else: %.0f MiB (%.1f%%)\n", (t-gb)/1048576, 100*(t-gb)/t
}'

echo
echo "Non-package graphical assets"
echo "----------------------------"
du -sh --total /usr/share/kasmvnc /usr/local/bin/cortile /usr/share/themes \
    /usr/share/backgrounds /opt/browser 2>/dev/null | sed 's/^/  /'
INNER
