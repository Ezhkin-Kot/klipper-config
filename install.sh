#!/usr/bin/env bash
# Lays out the configs from this repository across the system with GNU Stow (symlinks).
# Run on the klipper VM as a regular user with sudo: ./install.sh
# The repository must be somewhere the klipper user can read
# (not under /home/*, e.g. /opt/klipper-config).
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
PACKAGES=(klipper ustreamer)   # Stow packages: top-level directories with paths relative to /
CONFIG_DIR=/var/lib/klipper/printer_data/config
CONFIG_SRC="$REPO/klipper$CONFIG_DIR"

command -v stow >/dev/null || { echo "stow is required: sudo pacman -S stow"; exit 1; }

# The config directory must become a single symlink to the repository directory, not a set
# of per-file symlinks. On SAVE_CONFIG Klipper recreates printer.cfg via rename, which
# would turn a file symlink into a regular file.
if [ -e "$CONFIG_DIR" ] && [ ! -L "$CONFIG_DIR" ]; then
    BACKUP="$CONFIG_DIR.bak-$(date +%Y%m%d-%H%M%S)"
    echo "Moving existing $CONFIG_DIR to $BACKUP"
    sudo mv "$CONFIG_DIR" "$BACKUP"
fi

# Stow does not overwrite conflicting regular files (e.g. a hand-written ustreamer.service)
sudo stow --dir="$REPO" --target=/ --restow "${PACKAGES[@]}"

# Klipper (user klipper) writes into the config directory: SAVE_CONFIG and its backups
sudo chgrp -R klipper "$CONFIG_SRC"
sudo chmod -R g+rwX "$CONFIG_SRC"
sudo find "$CONFIG_SRC" -type d -exec chmod g+s {} +

sudo systemctl daemon-reload
sudo systemctl enable ustreamer.service
sudo systemctl restart ustreamer.service

echo "Done. Restart Klipper: sudo systemctl restart klipper"
echo "Caddy (separate step): cd $REPO/caddy && docker compose up -d  (stop nginx first)"
