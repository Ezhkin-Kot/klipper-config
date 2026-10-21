#!/usr/bin/env bash
# Builds the Klipper MCU firmware for the MKS Robin Nano v1.3 from the Klipper sources
# of the installed package. The firmware must be built from the same version as the host.
#
# Usage: ./build.sh [klipper-source-dir]     (default: /opt/klipper)
# The result is copied next to this script as Robin_nano35.bin, the name the board's
# bootloader looks for on the SD card.
set -euo pipefail

SRC="${1:-/opt/klipper}"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$SRC/Makefile" ] || { echo "$SRC does not look like a Klipper source tree"; exit 1; }

# /opt/klipper is read-only for regular users, so build in a copy
cp -r "$SRC"/. "$WORK/klipper"
cd "$WORK/klipper"
cp "$HERE/mks-robin-nano-v1.3.config" .config
make olddefconfig
make clean
make -j"$(nproc)"

cp out/klipper.bin "$HERE/Robin_nano35.bin"
echo "Done: $HERE/Robin_nano35.bin"
echo "Copy it to a FAT32 microSD card, power-cycle the printer with the card inserted,"
echo "wait for the flashing to finish, power-cycle again."
