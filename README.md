<div align="center">

```
▓█████  ██ ▄█▀ ▄████▄   ▒█████
▓█   ▀  ██▄█▒ ▒██▀ ▀█  ▒██▒  ██▒
▒███   ▓███▄░ ▒▓█    ▄ ▒██░  ██▒
▒▓█  ▄ ▓██ █▄ ▒▓▓▄ ▄██▒▒██   ██░
░▒████▒▒██▒ █▄▒ ▓███▀ ░░ ████▓▒░
░░ ▒░ ░▒ ▒▒ ▓▒░ ░▒ ▒  ░░ ▒░▒░▒░
 ░ ░  ░░ ░▒ ▒░  ░  ▒     ░ ▒ ▒
   ░   ░ ░░ ░ ░        ░ ░ ░ ▒
   ░  ░░  ░   ░ ░          ░ ░
              ░
```

# arch-config

**Dotfiles, scripts and system configuration for a KDE Plasma / Wayland Arch Linux desktop.**

![Arch](https://img.shields.io/badge/Arch_Linux-1793D1?style=flat&logo=arch-linux&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
![KDE](https://img.shields.io/badge/KDE_Plasma-1D99F3?style=flat&logo=kde&logoColor=white)
![ShellCheck](https://img.shields.io/badge/shellcheck-clean-brightgreen?style=flat)

</div>

---

## What this is

A restore point. If this machine dies, this repo plus a fresh Arch install gets
the environment back: the shell, the terminal, the maintenance scripts, the
system tuning, and the exact package set.

It is deliberately **not** a full backup — no personal data, no credentials, no
machine-specific identifiers. See [What is deliberately absent](#what-is-deliberately-absent).

## Layout

```
scripts/          maintenance and utility scripts (live in ~)
dotfiles/         shell, terminal and GTK config (live in ~ and ~/.config)
systemd-user/     user-level systemd units
system/           /etc configuration — review before applying, machine-specific
docs/             package manifests and the restore procedure
```

## Scripts

| Script | What it does |
|---|---|
| `aur-guard.sh` | Audits installed AUR packages against the [aur-malware-check](https://github.com/lenucksi/aur-malware-check) IOC feed, the AUR RPC, and local PKGBUILDs. Runs weekly via timer. |
| `drive-health.sh` | Reads the SMART attributes that actually predict failure. `smartctl -H` alone reports PASSED on drives with pending sectors. |
| `backup-status.sh` | How stale is the backup? Reads a local stamp, so it works whether or not the backup drive is mounted. |
| `backup_home.sh` | rsync the OS to a labelled backup drive. |
| `update-snapshot.sh` | Records exact package versions before an upgrade; can generate the `pacman -U` rollback command afterwards. |
| `update-manifest.sh` | Regenerates `docs/pkglist-*.txt` and `docs/PACKAGES.md` from the live system. Run after installing or removing packages. |
| `update-system.sh` | System upgrade. Takes a snapshot first, trims the package cache with `paccache -rk2` rather than wiping it. |
| `clean_system.sh` | Scoped cleanup — prunes caches and old files, with confirmation, never a blind recursive delete. |
| `generate_audit.sh` | Generates a full system diagnostics report as Markdown. |
| `epub-to-md.sh` | EPUB/PDF/TXT/HTML → Markdown. |
| `mp4-to-gif.sh` | Video → GIF, auto-scaling to stay under a size limit. |
| `download_music.sh` | Downloads a YouTube playlist to tagged MP3s with embedded cover art (yt-dlp, archive file so reruns only fetch new tracks). |
| `fetch_album_art.sh` | Embeds cover art into MP3s that have none, from the top YouTube search result for the filename. |
| `enhance_metadata.py` | DJ library tagger: AcoustID fingerprint, Last.fm genre, Essentia BPM and Camelot key, written to ID3 and a JSON catalogue. Needs `ACOUSTID_API_KEY` and `LASTFM_API_KEY` in the environment. |
| `find-file.sh`, `music.sh`, `bpytop.sh`, `fastfetch-lolcat.sh` | Small conveniences. |
| `start_dashboard.sh` / `stop_dashboard.sh` | Launch/close a four-pane kitty monitoring grid. |
| `run_kaia.sh`, `restart_speech_dispatcher.sh` | Project-specific helpers. |

All scripts pass `shellcheck` clean.

## Restore

See **[docs/INSTALL.md](docs/INSTALL.md)** for the full procedure. The short version:

```bash
git clone https://github.com/Ekco-S64QTN6/arch-config.git
cd arch-config

# packages
sudo pacman -S --needed - < docs/pkglist-repo-explicit.txt
paru      -S --needed - < docs/pkglist-aur-explicit.txt
cut -f1 docs/pkglist-flatpak.txt | xargs flatpak install -y flathub

# dotfiles
cp -a dotfiles/.[!.]* ~/
cp -a dotfiles/config/. ~/.config/

# scripts
cp -a scripts/*.sh ~/ && chmod 755 ~/*.sh

# user timers
cp -a systemd-user/* ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now aur-guard.timer
```

`system/` is **not** copied by that. Review each file and apply by hand —
those are tuned for specific hardware.

## What is deliberately absent

This repo is public. The following are excluded on purpose:

- **Credentials.** Database and API secrets live in `~/.config/kaia/env` (mode
  `0600`), which `.bashrc` sources only if present. A fresh checkout works
  without it. Nothing here contains a password.
- **SSH and GPG keys**, `~/.ssh`, `~/.gnupg`. The SSH key's passphrase lives in
  KDE Wallet (`ksshaskpass` folder); `dotfiles/config/environment.d/ssh-agent.conf`
  wires the systemd `ssh-agent.socket` + ksshaskpass so it unlocks at login.
- **Disk UUIDs and serials.** No `fstab`, no disk-specific udev rules. Scripts
  discover drives by filesystem *label* so they survive a disk replacement.
- **MAC addresses.** No `systemd/network/*.link` files.
- **`machine-id`, git email, Wi-Fi SSIDs.**
- **Personal data** — documents, media, browser profiles, game saves.

## Notes

- Shell is bash with [starship](https://starship.rs/); terminal is
  [kitty](https://sw.kovidgoyal.net/kitty/) with
  [Maple Mono NF](https://github.com/subframe7536/maple-font).
  The `kitty.conf` here uses the **NF** (Nerd Font, AutoHint) build —
  hinted is the right choice at ≤1080p; unhinted is for HiDPI.
- `system/sysctl.d/60-oom-hardening.conf` sets `vm.panic_on_oom = 0`
  deliberately. `0` is the kernel default; an earlier version of this file set
  it to `1`, which turns a recoverable OOM into a kernel panic and reboot.
- The icon theme is candy-icons with Sweet cursors. Sweet-Rainbow (the previous
  theme) is still in `~/.local/share/icons`; several AUR icon packages in the
  manifest are its inheritance fallbacks, needed only if switching back.

---

<div align="center"><sub>Arch Linux · KDE Plasma · Wayland</sub></div>
