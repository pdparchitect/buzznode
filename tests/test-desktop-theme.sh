#!/bin/bash
# Buzznode's share of the desktop appearance.
#
# The desktop base owns the GTK theme machinery, the Openbox theme, the panel
# layout, the window-control resource overlay, and the Chrome policy - all of
# that is asserted in the base's own tests. What is checked here is only what
# this image still installs over it: the Buzz accent colours, the browser
# landing page, and the KasmVNC brand.

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
overlay_dir="$project_dir/overlay"
gtk_css="$overlay_dir/usr/share/themes/Desktop/gtk-3.0/gtk.css"
landing_page="$overlay_dir/opt/browser/index.html"

# The browser landing page.
grep -Fq 'background: #000;' "$landing_page"
grep -Fq '██████╗ ██╗   ██╗███████╗███████╗' "$landing_page"  # the shared BUZZ wordmark
if grep -Fq '<h1>Buzznode</h1>' "$landing_page"; then
    echo "The obsolete browser welcome card is still present." >&2
    exit 1
fi

# The Buzz accents. These two declarations are the only reason this image ships
# a gtk.css at all - everything else in the file is the base's.
grep -Fq 'caret-color: #d7d72e;' "$gtk_css"
grep -Fq '@define-color theme_selected_bg_color #2b2b0b;' "$gtk_css"

# The brand and the wallpaper drop-in the base resolves at session start.
grep -Fq 'RUN kasm-patch "Buzznode"' "$project_dir/Dockerfile"
test -s "$overlay_dir/usr/share/kasmvnc/www/assets/favicon.svg"
test -s "$overlay_dir/usr/share/backgrounds/desktop-wallpaper.svg"

# The wallpaper must cover a full canvas. The base applies it with
# `feh --bg-fill`, which would scale a bare 37px tile into one enormous dot.
wallpaper="$overlay_dir/usr/share/backgrounds/desktop-wallpaper.svg"
grep -Fq 'patternUnits="userSpaceOnUse"' "$wallpaper"

# ...and it must contain no XML comment. The imlib2 SVG loader feh uses rejects
# any file with one - anywhere, not just before the root element - reporting
# "No Imlib2 loader for that file format". The desktop then comes up with no
# wallpaper at all, which is easy to miss and easy to reintroduce by
# documenting the file in the obvious place.
if grep -Fq '<!--' "$wallpaper"; then
    echo "The wallpaper contains an XML comment; feh will refuse to load it." >&2
    exit 1
fi

# Nothing here may re-implement what the base already provides.
for owned_by_base in \
    'GTK_THEME=' \
    'G_RESOURCE_OVERLAYS=' \
    'generate-resource-overlay.py' \
    'kasmvncserver' \
    'BrowserThemeColor' \
    '--pack-extension='
do
    if grep -Fq -- "$owned_by_base" "$project_dir/Dockerfile"; then
        echo "Dockerfile re-implements '$owned_by_base', which the desktop base owns." >&2
        exit 1
    fi
done

for stale_path in openbox cortile kasm gtk tint2 wallpaper shell init.sh; do
    if [ -e "$project_dir/$stale_path" ]; then
        echo "$stale_path survived the move to the desktop base." >&2
        exit 1
    fi
done

echo "Buzznode desktop branding is valid."
