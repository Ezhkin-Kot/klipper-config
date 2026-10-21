#!/usr/bin/env bash
# Lays out the configs from this repository across the system with GNU Stow (symlinks).
# Run on the klipper VM as a regular user with sudo.
#
#   ./install.sh           configs only: Stow packages, permissions, services (safe to re-run)
#   ./install.sh --setup   first-time setup of a fresh Arch Linux install: packages, klipper
#                          user, Moonraker, then the same as above, then Fluidd, Mainsail, Caddy
#
# The repository must be somewhere the klipper user can read
# (not under /home/*, e.g. /opt/klipper-config).
# The Moonraker data (history database) is not restored.
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

# The config directory must become a single symlink to the repository directory, not a set
# of per-file symlinks. On SAVE_CONFIG Klipper recreates printer.cfg via rename, which
# would turn a file symlink into a regular file.
if [ -e "$CONFIG_DIR" ] && [ ! -L "$CONFIG_DIR" ]; then
    BACKUP="$CONFIG_DIR.bak-$(date +%Y%m%d-%H%M%S)"
    echo "Moving existing $CONFIG_DIR to $BACKUP"
    sudo mv "$CONFIG_DIR" "$BACKUP"
fi

# Stow does not overwrite conflicting regular files (e.g. a hand-written ustreamer.service
# or moonraker.conf): move them aside, the repository version takes over
for pkg in "${PACKAGES[@]}"; do
    while IFS= read -r -d '' file; do
        target="/${file#"$REPO/$pkg/"}"
        if [ -f "$target" ] && [ ! -L "$target" ]; then
            echo "Moving existing $target to $target.bak"
            sudo mv "$target" "$target.bak"
        fi
    done < <(find "$REPO/$pkg" -type f -print0)
done

sudo stow --dir="$REPO" --target=/ --restow "${PACKAGES[@]}"

# Host-specific Moonraker settings are not tracked: start from the example
if [ ! -e /etc/klipper/moonraker-local.conf ]; then
    sudo install -m 644 "$REPO/examples/moonraker-local.conf.example" /etc/klipper/moonraker-local.conf
    echo "Created /etc/klipper/moonraker-local.conf: add your CORS domains to it"
fi

# Klipper (user klipper) writes into the config directory: SAVE_CONFIG and its backups
sudo chgrp -R klipper "$CONFIG_SRC"
sudo chmod -R g+rwX "$CONFIG_SRC"
sudo find "$CONFIG_SRC" -type d -exec chmod g+s {} +

sudo systemctl daemon-reload
sudo systemctl enable ustreamer.service
sudo systemctl restart ustreamer.service
sudo systemctl enable moonraker.service

if [ "$SETUP" = 1 ]; then
    echo "== Web interfaces"
    "$REPO/fluidd/install-fluidd.sh"
    "$REPO/scripts/install-mainsail.sh"

    echo "== Caddy"
    sudo systemctl enable --now docker
    (cd "$REPO/caddy" && sudo docker compose up -d)

    sudo systemctl enable --now klipper moonraker
    echo "Done. Flash the MCU with firmware/build.sh if the board is new."
    exit 0
fi

echo "Done. Restart Klipper and Moonraker: sudo systemctl restart klipper moonraker"
echo "Caddy (separate step): cd $REPO/caddy && docker compose up -d  (stop nginx first)"
