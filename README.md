# klipper-config

Configuration for the klipper VM (Arch Linux): Klipper, camera, Caddy.

## Layout

The `klipper/` and `ustreamer/` directories are [GNU Stow](https://www.gnu.org/software/stow/) packages:
inside them the path mirrors the path from `/`, and `install.sh` lays them out with symlinks.

```
klipper/var/lib/klipper/printer_data/config/   -> /var/lib/klipper/printer_data/config (symlink to the directory)
ustreamer/etc/systemd/system/ustreamer.service -> /etc/systemd/system/ustreamer.service
caddy/                                         -> not Stow, run straight from the repository
install.sh
```

Calibration results (`SAVE_CONFIG`) are stored in `printer.cfg` in the repository. The
`printer-*.cfg` backups that Klipper creates on `SAVE_CONFIG` sit next to it but are
ignored (`.gitignore`).

## Installation on the VM

```bash
sudo pacman -S stow
sudo git clone git@github.com:Ezhkin-Kot/klipper-config /opt/klipper-config
sudo chown -R "$USER":"$USER" /opt/klipper-config
cd /opt/klipper-config && ./install.sh
```

If `stow` complains about a conflict with an existing file (for example
`/etc/systemd/system/ustreamer.service`), delete that file by hand and run
`install.sh` again: Stow never overwrites anything.

## Caddy

```bash
sudo systemctl disable --now nginx
cd /opt/klipper-config/caddy && docker compose up -d
docker compose logs --tail 20
```

Rollback: `docker compose down && sudo systemctl enable --now nginx`.
Caddy listens on `:80` (Fluidd) and `:81` (Mainsail) and serves static files from `/var/www`.

## Not in this repository

- Fluidd/Mainsail (`/var/www/*`): releases; Fluidd with a patch for WebKit.
- Board firmware, Klipper/Moonraker (package and git repository).
- `moonraker.conf` and the Moonraker polkit rule: not moved here yet (TODO).
