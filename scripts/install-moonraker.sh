#!/usr/bin/env bash
# Installs Moonraker into /var/lib/klipper/moonraker with a virtualenv in
# /var/lib/klipper/moonraker-env, as expected by moonraker.service.
# Usage: ./install-moonraker.sh
# Requires: git, python, python-virtualenv. The klipper user must already exist.
set -euo pipefail

BASE=/var/lib/klipper
REPO=https://github.com/Arksine/moonraker.git

if [ ! -d "$BASE/moonraker/.git" ]; then
    sudo -u klipper git clone "$REPO" "$BASE/moonraker"
else
    echo "$BASE/moonraker already exists, skipping clone"
fi
[ -d "$BASE/moonraker-env" ] || sudo -u klipper python -m venv "$BASE/moonraker-env"
sudo -u klipper "$BASE/moonraker-env/bin/pip" install -r "$BASE/moonraker/scripts/moonraker-requirements.txt"

sudo install -d -o klipper -g klipper /var/log/moonraker
echo "Done. The config and the unit are installed by install.sh."
