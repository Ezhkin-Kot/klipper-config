# klipper-config

Configuration and install scripts for a Klipper host on Arch Linux:

- Klipper and Moonraker for a Flying Bear Ghost 5 (MKS Robin Nano v1.3)
- Fluidd and Mainsail served by Caddy
- a USB webcam streamed by ustreamer

## Contents

`klipper/`, `moonraker/` and `ustreamer/` are [GNU Stow](https://www.gnu.org/software/stow/)
packages: the path inside a package mirrors the path from `/`, and `install.sh` links it there.

| Path         | Purpose                                                                                    |
| ------------ | ------------------------------------------------------------------------------------------ |
| `klipper/`   | Printer config (`/var/lib/klipper/printer_data/config`) and the `klipper.service` override |
| `moonraker/` | `moonraker.conf`, `moonraker.service`, list of services Fluidd may control                 |
| `ustreamer/` | `ustreamer.service`, the camera stream                                                     |
| `polkit/`    | Polkit rule that lets Moonraker manage services and reboot the host                        |
| `caddy/`     | Caddy in Docker, serves Fluidd (`:80`) and Mainsail (`:81`)                                |
| `fluidd/`    | Fluidd build with a WebKit camera patch                                                    |
| `firmware/`  | MCU firmware config and build script                                                       |
| `packages/`  | pacman and AUR package lists                                                               |
| `scripts/`   | Moonraker and Mainsail installers                                                          |
| `examples/`  | Template for host-specific Moonraker settings                                              |

## Installation

Requires `stow`, plus `acl` if the repository is under `/home`.

```bash
git clone https://github.com/Ezhkin-Kot/klipper-config ~/klipper-config
cd ~/klipper-config && ./install.sh
```

`install.sh` is safe to re-run. It:

- moves existing files that would be replaced to `<name>.bak` (the old config directory to
  `config.bak-<date>`) and links the repository files into place with Stow;
- makes the config directory writable for the `klipper` user, so `SAVE_CONFIG` writes into the repository;
- copies the polkit rule into `/etc/polkit-1/rules.d/`;
- creates `/etc/klipper/moonraker-local.conf` if it is missing;
- restarts `ustreamer` if it is running and enables `moonraker`.

The config directory is linked as a whole, not file by file: Klipper recreates `printer.cfg` on
`SAVE_CONFIG`, which would replace a file symlink with a regular file. Calibration results end up in
`printer.cfg` in the repository; the `printer-*.cfg` backups Klipper makes next to it are git-ignored.

Edit `/etc/klipper/moonraker-local.conf` after the first run: it holds the `[authorization]`
section (trusted clients, CORS domains). Add the addresses and domains you open Fluidd or Mainsail
from. The file is not tracked; its template is `examples/moonraker-local.conf.example`.

### Fresh system

```bash
git clone https://github.com/Ezhkin-Kot/klipper-config ~/klipper-config
cd ~/klipper-config && ./install.sh --setup
```

On top of the steps above, `--setup` installs the packages from `packages/`, creates the `klipper`
user, adds `klipper` to `IgnorePkg` (see [Firmware](#firmware)), installs Moonraker, builds Fluidd,
installs Mainsail and starts Caddy. The installers in `scripts/` and `fluidd/` can also be run on their own.

## Firmware

The firmware is built from the Klipper sources, which are installed with the `klipper` package
in `/opt/klipper`, and `firmware/build.sh` builds them from there. The firmware and the host must
come from the same Klipper version, so the package is pinned with `IgnorePkg`:
update it by hand (`sudo pacman -S klipper`), then rebuild and flash the board.

```bash
cd ~/klipper-config/firmware && ./build.sh
```

`mks-robin-nano-v1.3.config` is the Klipper `.config` for the board (STM32F407, 32 KiB bootloader
offset, 8 MHz crystal, USART3 on PB11/PB10); the script copies it into a temporary copy of the
sources, so `make menuconfig` is not needed. To flash, copy the resulting `Robin_nano35.bin` to a
FAT32 microSD card, power-cycle the printer with the card inserted and again after flashing finishes.
The MCU version shown in Fluidd (System page) should match the host version after that.

Without the package, or for another Klipper version, clone the upstream sources and pass the directory:

```bash
git clone https://github.com/Klipper3d/klipper ~/klipper && git -C ~/klipper checkout <tag>
./build.sh ~/klipper
```

For another board, run `make menuconfig` in a Klipper checkout (the matching example in its `config/`
directory lists the settings to choose), then replace `mks-robin-nano-v1.3.config` with the resulting `.config`.

## Camera

`ustreamer.service` streams the camera on `127.0.0.1:8080`; Caddy exposes it under `/webcam/`.
Set `--device` in the unit to your camera (`ls /dev/v4l/by-id/`).

Settings in Fluidd (Settings → Cameras):

| Service        | Stream URL              | Snapshot URL       |
| -------------- | ----------------------- | ------------------ |
| MJPEG Stream   | `/webcam/fluidd-stream` |                    |
| MJPEG Adaptive |                         | `/webcam/snapshot` |

The camera sensor runs and warms up for as long as `ustreamer` runs, so the service is not enabled at
boot. Start and stop it from Fluidd (three-dots menu in the top right corner), which works through
Moonraker's `[machine]` section and `moonraker.asvc`. While it is stopped there is no image, no snapshots and no timelapse.

To start `ustreamer` at boot: `sudo systemctl enable ustreamer`. To undo that, remove the link with
`sudo rm /etc/systemd/system/multi-user.target.wants/ustreamer.service` rather than `systemctl disable`,
which would delete the unit's Stow symlink.

## Caddy

```bash
cd ~/klipper-config/caddy && docker compose up -d
```

Caddy listens on `:80` (Fluidd) and `:81` (Mainsail) over plain HTTP (`auto_https` is off), so
nothing else can use these ports. It proxies Moonraker and `/webcam/` and serves the static files from `/var/www`.

## Fluidd with a WebKit patch

Fluidd's `MJPEG Stream` camera mode does not work in WebKit (OrcaSlicer) out of the box:
`fluidd/0001-mjpeg-stream-no-byob.patch` removes the BYOB stream reader WebKit lacks, and WebKit
also aborts `fetch` on `multipart/x-mixed-replace`, so Caddy serves the same stream as
`multipart/mixed` at `/webcam/fluidd-stream`. Use that URL as the Stream URL.

`install-fluidd.sh` builds Fluidd from source with the patch and installs it into `/var/www/fluidd`
(the previous version is kept in `/var/www/fluidd.bak`):

```bash
sudo pacman -S --needed git nodejs npm
cd ~/klipper-config/fluidd && ./install-fluidd.sh [tag]      # default: v1.37.7
```

The build needs about 1 GB of RAM. On a weak board, build the archive on another machine and install it there
(only `unzip` is needed on the board):

```bash
./install-fluidd.sh --zip [tag]                              # writes fluidd-<tag>-patched.zip
./install-fluidd.sh --install-zip fluidd-<tag>-patched.zip   # on the board
```
