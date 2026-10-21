#!/usr/bin/env bash
# Builds Fluidd from source with a patch that makes the MJPEG Stream camera mode work
# in WebKit (Safari, OrcaSlicer), and installs it into /var/www/fluidd.
#
# Usage:
#   ./install-fluidd.sh [tag]               build and install (default tag: v1.37.7)
#   ./install-fluidd.sh --zip [tag]         only build: write fluidd-<tag>-patched.zip, do not install
#   ./install-fluidd.sh --install-zip FILE  install a prebuilt archive, no build tools needed
#
# The build is heavy (about 1 GB of RAM, minutes of CPU): on a weak board run `--zip` on a
# desktop machine, copy the archive over and run `--install-zip` there.
# Build requires: git, node (Fluidd wants ^22.12 || ^24), npm, and zip for --zip.
# Install from an archive requires: unzip.
# The patch is made against v1.37.7; if `git apply` fails on a newer tag, check whether
# upstream already removed `mode: 'byob'` from src/workers/mjpegStream.ts.
set -euo pipefail

WEB_ROOT=/var/www/fluidd

# Keep the previous version for a quick rollback, then replace the contents in place
install_dir() {
    local src="$1"
    sudo mkdir -p "$WEB_ROOT"
    sudo rm -rf "$WEB_ROOT.bak"
    sudo cp -a "$WEB_ROOT" "$WEB_ROOT.bak"
    sudo find "$WEB_ROOT" -mindepth 1 -delete
    sudo cp -a "$src"/. "$WEB_ROOT"/
}

require() {
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null || { echo "$cmd is required"; exit 1; }
    done
}

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ "${1:-}" = "--install-zip" ]; then
    ARCHIVE="${2:?usage: $0 --install-zip FILE}"
    require unzip
    mkdir "$WORK/dist"
    unzip -q "$ARCHIVE" -d "$WORK/dist"
    [ -f "$WORK/dist/index.html" ] || { echo "$ARCHIVE does not look like a Fluidd build"; exit 1; }
    install_dir "$WORK/dist"
    echo "Done: $ARCHIVE installed to $WEB_ROOT, previous version in $WEB_ROOT.bak"
    exit 0
fi

ZIP_ONLY=0
if [ "${1:-}" = "--zip" ]; then ZIP_ONLY=1; shift; fi
TAG="${1:-v1.37.7}"

require git node npm
[ "$ZIP_ONLY" = 0 ] || require zip

git clone --depth 1 --branch "$TAG" https://github.com/fluidd-core/fluidd.git "$WORK/fluidd"
cd "$WORK/fluidd"
git apply "$HERE"/*.patch

# Install pnpm outside the project directory: npx inside the project trips over devEngines
PNPM_VERSION="$(node -p "require('./package.json').devEngines.packageManager.version")"
npm install --no-audit --no-fund --prefix "$WORK/tools" "pnpm@$PNPM_VERSION"
PNPM="$WORK/tools/node_modules/.bin/pnpm"
"$PNPM" install --frozen-lockfile
"$PNPM" build

if [ "$ZIP_ONLY" = 1 ]; then
    (cd dist && zip -qr "$HERE/fluidd-$TAG-patched.zip" .)
    echo "Done: $HERE/fluidd-$TAG-patched.zip"
    exit 0
fi

install_dir dist
echo "Done: Fluidd $TAG (patched) installed to $WEB_ROOT, previous version in $WEB_ROOT.bak"
