#!/bin/bash
# Patch KasmVNC web assets to remove branding and apply customisations.
# Run once after installing the kasmvnc .deb package.
set -euo pipefail

WWW=/usr/share/kasmvnc/www

# 1. Inject custom assets, rebrand the title, and replace upstream icon links.
find "$WWW" -maxdepth 1 -name '*.html' -exec sed -i \
    -e 's|<title>[^<]*</title>|<title>Buzznode</title>|' \
    -e 's|<link[^>]*rel="icon"[^>]*>||g' \
    -e 's|<link[^>]*rel="apple-touch-icon"[^>]*>||g' \
    -e 's|</head>|<link rel="icon" type="image/svg+xml" href="./assets/favicon.svg"><link rel="stylesheet" href="./assets/custom.css"></head>|' \
    {} +

# 2. Replace the "KasmVNC" brand string and keep the browser title fixed.
# KasmVNC otherwise replaces it after connecting with the VNC desktop name,
# which contains Docker's generated hostname.
find "$WWW/assets" -name 'ui-*.js' -exec sed -i \
    -e 's|"KasmVNC"|"Buzznode"|g' \
    -e 's|document.title=r.detail.name+" - "+ox|document.title=ox|g' \
    {} +

if grep -ERq 'document\.title=[[:alnum:]_$]+\.detail\.name\+" - "\+' \
    "$WWW/assets"/ui-*.js; then
    echo "[kasm-patch] dynamic VNC desktop title was not removed" >&2
    exit 1
fi

echo "[kasm-patch] KasmVNC UI patched successfully"
