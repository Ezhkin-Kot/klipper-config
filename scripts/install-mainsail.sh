#!/usr/bin/env bash
# Installs the latest Mainsail release into /var/www/mainsail (a plain release, no patches).
# Usage: ./install-mainsail.sh
# Requires: curl, unzip
set -euo pipefail

WEB_ROOT=/var/www/mainsail
URL=https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip

for cmd in curl unzip; do
    command -v "$cmd" >/dev/null || { echo "$cmd is required"; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -fsSL "$URL" -o "$WORK/mainsail.zip"
unzip -q "$WORK/mainsail.zip" -d "$WORK/dist"
[ -f "$WORK/dist/index.html" ] || { echo "downloaded archive does not look like Mainsail"; exit 1; }

sudo mkdir -p "$WEB_ROOT"
sudo find "$WEB_ROOT" -mindepth 1 -delete
sudo cp -a "$WORK/dist"/. "$WEB_ROOT"/
echo "Done: Mainsail installed to $WEB_ROOT"
