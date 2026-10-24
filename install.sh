#!/usr/bin/env bash
# Links the configs from this repository into the system with GNU Stow.
# Run as a regular user with sudo.
#
#   ./install.sh           configs only (safe to re-run)
#   ./install.sh --setup   also set up a fresh Arch Linux install: packages, klipper user,
#                          Moonraker, Fluidd, Mainsail and Caddy
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
SETUP=0
case "${1:-}" in
    "") ;;
    --setup) SETUP=1 ;;
    *) echo "usage: $0 [--setup]"; exit 1 ;;
esac
PACKAGES=(klipper ustreamer moonraker)   # Stow packages: top-level directories with paths relative to /
CONFIG_DIR=/var/lib/klipper/printer_data/config
CONFIG_SRC="$REPO/klipper$CONFIG_DIR"

if [ "$SETUP" = 1 ]; then
    echo "== Packages"
    grep -vE '^\s*(#|$)' "$REPO/packages/pacman.txt" | sudo pacman -S --needed -
    if ! command -v yay >/dev/null && ! command -v paru >/dev/null; then
        echo "== AUR helper (yay-bin)"
        BUILD="$(mktemp -d)"
        git clone https://aur.archlinux.org/yay-bin.git "$BUILD/yay-bin"
        (cd "$BUILD/yay-bin" && makepkg -si --noconfirm)
        rm -rf "$BUILD"
    fi
    AUR_HELPER="$(command -v yay || command -v paru)"
    grep -vE '^\s*(#|$)' "$REPO/packages/aur.txt" | xargs "$AUR_HELPER" -S --needed

    echo "== klipper user"
    # The klipper user needs access to the serial port (uucp, tty) and the camera (video)
    id klipper >/dev/null 2>&1 || sudo useradd --system --create-home --home-dir /var/lib/klipper --shell /usr/bin/nologin klipper
    sudo usermod -aG network,tty,uucp,video klipper

    echo "== Pin the klipper package (host and MCU firmware must match)"
    if ! grep -qE '^IgnorePkg.*\bklipper\b' /etc/pacman.conf; then
        if grep -q '^IgnorePkg' /etc/pacman.conf; then
            sudo sed -i '/^IgnorePkg/ s/$/ klipper/' /etc/pacman.conf
        else
            sudo sed -i '/^\[options\]/a IgnorePkg = klipper' /etc/pacman.conf
        fi
    fi

    echo "== Moonraker"
    "$REPO/scripts/install-moonraker.sh"
fi

command -v stow >/dev/null || { echo "stow is required: sudo pacman -S stow"; exit 1; }

# The klipper user reads the repository through the symlinks, so it needs to pass through
# the home directory (execute permission only, no listing)
case "$REPO" in
    /home/*)
        command -v setfacl >/dev/null || { echo "setfacl is required: sudo pacman -S acl"; exit 1; }
        sudo setfacl -m u:klipper:x "$(echo "$REPO" | cut -d/ -f1-3)"
        ;;
esac

# The config directory must become a single symlink to the repository directory, not a set
# of per-file symlinks. On SAVE_CONFIG Klipper recreates printer.cfg via rename, which
# would turn a file symlink into a regular file.
if [ -e "$CONFIG_DIR" ] && [ ! -L "$CONFIG_DIR" ]; then
    BACKUP="$CONFIG_DIR.bak-$(date +%Y%m%d-%H%M%S)"
    echo "Moving existing $CONFIG_DIR to $BACKUP"
    sudo mv "$CONFIG_DIR" "$BACKUP"
fi

# Stow does not overwrite regular files: move existing ones aside
for pkg in "${PACKAGES[@]}"; do
    while IFS= read -r -d '' file; do
        target="/${file#"$REPO/$pkg/"}"
        if sudo test -f "$target" && ! sudo test -L "$target"; then
            echo "Moving existing $target to $target.bak"
            sudo mv "$target" "$target.bak"
        fi
    done < <(find "$REPO/$pkg" -type f -print0)
done

sudo stow --dir="$REPO" --target=/ --restow "${PACKAGES[@]}"

# Host-specific Moonraker settings are not tracked, start from the example
if [ ! -e /etc/klipper/moonraker-local.conf ]; then
    sudo install -m 644 "$REPO/examples/moonraker-local.conf.example" /etc/klipper/moonraker-local.conf
    echo "Created /etc/klipper/moonraker-local.conf: add your CORS domains to it"
fi

# Klipper (user klipper) writes into the config directory: SAVE_CONFIG and its backups
sudo chgrp -R klipper "$CONFIG_SRC"
sudo chmod -R g+rwX "$CONFIG_SRC"
sudo find "$CONFIG_SRC" -type d -exec chmod g+s {} +

# Copied, not linked: the rule grants system privileges and must be owned by root
sudo install -m 644 -o root -g root "$REPO/polkit/49-moonraker.rules" /etc/polkit-1/rules.d/49-moonraker.rules

sudo systemctl daemon-reload
# ustreamer is deliberately not enabled at boot (the camera warms up while it runs):
# it is started from Fluidd. If it is already running, restart it to pick up unit changes.
sudo systemctl try-restart ustreamer.service
sudo systemctl enable moonraker.service

if [ "$SETUP" = 1 ]; then
    echo "== Web interfaces"
    "$REPO/fluidd/install-fluidd.sh"
    "$REPO/scripts/install-mainsail.sh"

    echo "== Caddy"
    sudo systemctl enable --now docker
    (cd "$REPO/caddy" && sudo docker compose up -d)

    sudo systemctl enable --now klipper moonraker
    echo "Done. If the board has no Klipper firmware yet, build and flash it with firmware/build.sh."
    exit 0
fi

echo "Done. Restart Klipper and Moonraker: sudo systemctl restart klipper moonraker"
