# Restore Procedure

Getting from a fresh Arch install back to this environment. Work top to bottom;
each section is independent enough to skip.

---

## 0. Before you start

You need a working Arch install with networking, `git`, and a user account.
Nothing here assumes a specific hostname or username, but the scripts default to
paths under `$HOME`.

```bash
sudo pacman -S --needed base-devel git
git clone https://github.com/Ekco-S64QTN6/arch-config.git
cd arch-config
```

---

## 1. Packages

**Repository packages** — these resolve their own dependencies, so this is the
minimal explicit set, not the full 1400-package closure.

```bash
sudo pacman -S --needed - < docs/pkglist-repo-explicit.txt
```

**AUR** — bootstrap a helper first:

```bash
git clone https://aur.archlinux.org/paru.git /tmp/paru
cd /tmp/paru && makepkg -si && cd -
paru -S --needed - < docs/pkglist-aur-explicit.txt
```

**Flatpak:**

```bash
sudo pacman -S --needed flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
xargs -a docs/pkglist-flatpak.txt flatpak install -y flathub
```

---

## 2. Dotfiles

```bash
cp -a dotfiles/.[!.]*     ~/
cp -a dotfiles/config/.   ~/.config/
```

Then open a new shell. `.bashrc` sources `~/.config/kaia/env` **only if it
exists**, so a fresh checkout works without it. If you need those variables,
recreate that file yourself with mode `0600`:

```bash
mkdir -p ~/.config/kaia
printf 'export EXAMPLE_VAR="value"\n' > ~/.config/kaia/env
chmod 600 ~/.config/kaia/env
```

---

## 3. Scripts

```bash
cp -a scripts/*.sh ~/
chmod 755 ~/*.sh
```

Several have dependencies beyond base: `jq` and `curl` (aur-guard),
`smartmontools` and `jq` (drive-health), `rsync` (backup_home), `pandoc` and
`poppler` (epub-to-md), `ffmpeg` (mp4-to-gif), `pacman-contrib` (update-system,
clean_system). All are in the repo package list.

---

## 4. User timers

```bash
mkdir -p ~/.config/systemd/user
cp -a systemd-user/* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now aur-guard.timer
```

Verify: `systemctl --user list-timers aur-guard.timer`

---

## 5. System configuration — review each file first

**Nothing in `system/` should be copied blindly.** These are tuned for specific
hardware. Read them, then apply what applies.

| File | What it does | Safe to copy as-is? |
|---|---|---|
| `sysctl.d/60-oom-hardening.conf` | `vm.panic_on_oom = 0` — let the OOM killer work instead of panicking the kernel | Yes, sane on any desktop |
| `sysctl.d/99-max-files.conf` | Raises `fs.file-max` / `fs.nr_open` | Yes |
| `sysctl.d/50-kaia-network.conf` | Larger socket buffers, `tcp_rfc1337`, drops source routing | Yes |
| `sysctl.d/99-kaia-memory.conf` | `vm.max_map_count` — needed by some games and Proton | Yes |
| `udev-rules.d/60-ioschedulers.rules` | `none` for NVMe, `bfq` for SATA SSDs | Yes — it is subsystem-scoped, so it will not spam your journal |
| `modprobe.d/nct6775.conf` | Forces the hwmon chip ID | **No** — ASUS B650 specific |
| `modprobe.d/nvidia-gsp.conf` | Disables GSP firmware | **No** — review; unsupported with `nvidia-open-dkms` |
| `systemd/nvidia-performance.service` | Pins GPU clocks | **No** — GPU specific |
| `systemd/journald.conf.d/00-size-cap.conf` | Caps the journal at 500M | Yes |
| `systemd/resolved.conf.d/10-no-llmnr.conf` | Disables LLMNR, keeps mDNS | Yes |
| `mkinitcpio.conf`, `grub.default` | Boot configuration | **No** — read carefully, regenerate rather than copy |

Applying the safe ones:

```bash
sudo cp system/sysctl.d/*.conf         /etc/sysctl.d/
sudo cp system/udev-rules.d/*.rules    /etc/udev/rules.d/
sudo cp -r system/systemd/journald.conf.d system/systemd/resolved.conf.d /etc/systemd/
sudo sysctl --system
sudo udevadm control --reload-rules
sudo systemctl restart systemd-journald systemd-resolved
```

---

## 6. Things this repo cannot restore

- **Credentials** — recreate `~/.config/kaia/env` by hand.
- **SSH / GPG keys** — restore from your own secure backup, never from git.
- **`/etc/fstab`** — regenerate for the new disks (`genfstab -U /mnt`).
- **Network interface naming** — if you relied on `.link` files to pin names,
  recreate them with the new hardware's MACs.
- **Bootloader** — install and configure GRUB for the new machine.
- **Personal data** — documents, media, game saves, browser profiles.

---

## 7. Sanity check afterwards

```bash
~/aur-guard.sh            # AUR supply-chain audit
sudo ~/drive-health.sh    # SMART attributes on every disk
~/backup-status.sh        # backup freshness
systemctl --failed        # should be empty
systemd-analyze           # boot time
```
