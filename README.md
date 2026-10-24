# klipper-config

Configuration for the klipper VM (Arch Linux): Klipper, camera, Caddy.

## Layout

The `klipper/`, `ustreamer/` and `moonraker/` directories are [GNU Stow](https://www.gnu.org/software/stow/)
packages: inside them the path mirrors the path from `/`, and `install.sh` lays them out with symlinks.

```
klipper/var/lib/klipper/printer_data/config/   -> /var/lib/klipper/printer_data/config (symlink to the directory)
klipper/etc/systemd/system/klipper.service.d/override.conf -> /etc/systemd/system/klipper.service.d/ (config path and log)
ustreamer/etc/systemd/system/ustreamer.service -> /etc/systemd/system/ustreamer.service
moonraker/etc/klipper/moonraker.conf           -> /etc/klipper/moonraker.conf
moonraker/etc/systemd/system/moonraker.service -> /etc/systemd/system/moonraker.service
polkit/49-moonraker.rules                      -> /etc/polkit-1/rules.d/ (copied by install.sh, not a symlink)
moonraker/var/lib/klipper/printer_data/moonraker.asvc  -> services Fluidd may start/stop (ustreamer)
examples/moonraker-local.conf.example          -> copied to /etc/klipper/moonraker-local.conf (not tracked)
caddy/                                         -> not Stow, run straight from the repository
fluidd/                                        -> not Stow, Fluidd patch + build/install script
firmware/                                      -> MCU firmware config and build script
packages/                                      -> pacman / AUR package lists
scripts/                                       -> Moonraker and Mainsail installers
install.sh                                     -> Stow packages; with --setup, everything above on a fresh system
```

Calibration results (`SAVE_CONFIG`) are stored in `printer.cfg` in the repository. The
`printer-*.cfg` backups that Klipper creates on `SAVE_CONFIG` sit next to it but are
ignored (`.gitignore`).

## Installation on the VM

```bash
sudo pacman -S stow
git clone git@github.com:Ezhkin-Kot/klipper-config ~/klipper-config
cd ~/klipper-config && ./install.sh
```

Existing regular files that Stow would replace (for example a hand-written
`moonraker.conf`) are moved aside to `<name>.bak`; Stow itself never overwrites anything.

`/etc/klipper/moonraker-local.conf` holds the host-specific `[authorization]` section
(trusted clients, CORS domains). It is created from `examples/moonraker-local.conf.example`
and is not tracked: add the addresses you open Fluidd/Mainsail from.

## From scratch

On a fresh Arch Linux install:

```bash
git clone git@github.com:Ezhkin-Kot/klipper-config ~/klipper-config
cd ~/klipper-config && ./install.sh --setup
```

`install.sh` without arguments only lays out the configs and is safe to re-run. `--setup` additionally installs `packages/`, creates the `klipper` user, pins the `klipper` package with
`IgnorePkg` (host and MCU firmware must be the same version), installs Moonraker, then lays
out the configs, installs Fluidd, Mainsail and starts Caddy. Installers in `scripts/` and `fluidd/` can also be run alone.

## MCU firmware

`firmware/mks-robin-nano-v1.3.config` is the Klipper `.config` for the MKS Robin Nano v1.3
(STM32F407, 32 KiB bootloader offset, 8 MHz crystal, USART3 PB11/PB10). It replaces `make menuconfig`:

```bash
cd ~/klipper-config/firmware && ./build.sh        # sources from /opt/klipper
```

Copy the resulting `Robin_nano35.bin` to a FAT32 microSD card, power-cycle the printer with the
card inserted, then power-cycle again after flashing. Rebuild and reflash after every `klipper` package update.

## Switching the camera on and off

The camera sensor streams 24/7 while `ustreamer` runs and gets warm. Moonraker (`[machine]`,
`moonraker.asvc`) lets Fluidd control the service: three-dots menu in the top right corner,
the `ustreamer` entry has Start / Stop. While it is stopped the camera, snapshots and timelapse
do not work, so start it before a print.

`ustreamer` is not enabled at boot, so after a reboot the camera is off until it is started
from Fluidd. To start it at boot again: `sudo systemctl enable ustreamer`. Do not turn the
autostart off with `systemctl disable`: the unit is a Stow symlink, and `disable` deletes the
symlink itself (the service then cannot be started). Remove the boot link instead:
`sudo rm /etc/systemd/system/multi-user.target.wants/ustreamer.service`.

## Caddy

```bash
sudo systemctl disable --now nginx
cd ~/klipper-config/caddy && docker compose up -d
docker compose logs --tail 20
```

Rollback: `docker compose down && sudo systemctl enable --now nginx`.
Caddy listens on `:80` (Fluidd) and `:81` (Mainsail) and serves static files from `/var/www`.

## Fluidd with a WebKit patch

Fluidd's `MJPEG Stream` camera mode does not work in WebKit (Safari, OrcaSlicer) out of the box.
`fluidd/` contains a small patch for `src/workers/mjpegStream.ts` and a script that builds Fluidd
from source and installs it into `/var/www/fluidd`:

```bash
sudo pacman -S --needed git nodejs npm
cd ~/klipper-config/fluidd && ./install-fluidd.sh        # build and install
```

The build needs about 1 GB of RAM and several minutes of CPU. On a weak board (SBC), build on a
desktop instead and only install the archive on the board (needs just `unzip`):

```bash
./install-fluidd.sh --zip [tag]                 # on the desktop: writes fluidd-<tag>-patched.zip
scp fluidd-*-patched.zip user@board:            # copy it over
./install-fluidd.sh --install-zip fluidd-<tag>-patched.zip   # on the board
```

The camera stream URL in Fluidd must be `/webcam/fluidd-stream`: Caddy serves the same stream
there as `multipart/mixed`, because WebKit also aborts `fetch` on `multipart/x-mixed-replace`.
The previous version is kept in `/var/www/fluidd.bak`.

## Not in this repository

- The Moonraker data (history database).
- Slicer profiles.
