# Package Manifest

Generated 2026-11-07 on Arch Linux, kernel 6.18.60-1-lts by `scripts/update-manifest.sh`.

Machine-readable lists live alongside this file:
`pkglist-repo-explicit.txt`, `pkglist-aur-explicit.txt`, `pkglist-flatpak.txt`.

## Repository packages (192 explicit)

```bash
sudo pacman -S --needed - < pkglist-repo-explicit.txt
```

<details><summary>Full list</summary>

```
adobe-source-han-sans-jp-fonts adobe-source-han-serif-jp-fonts aircrack-ng 
alsa-plugins alsa-utils amd-ucode arch-install-scripts arch-wiki-docs 
arch-wiki-lite ark base base-devel bash-completion bat bluez-utils bpf bpytop 
btop chromaprint chromium cmake cpupower cuda cudnn dkms dolphin dosfstools 
efibootmgr electron39 elementary-icon-theme ethtool fastfetch flameshot 
fluidsynth fzf gamemode git github-cli goverlay gparted gqrx grub 
gst-plugin-pipewire gst-plugins-good hashcat hcxtools hdparm htop imagemagick 
iotop irssi iw iwd jq kate kitty kiwix-desktop kwalletmanager lib32-alsa-lib 
lib32-alsa-plugins lib32-gamemode lib32-gnutls lib32-gtk3 lib32-libpng 
lib32-libpulse lib32-libva lib32-libxcomposite lib32-libxinerama lib32-mesa 
lib32-ocl-icd lib32-sqlite lib32-vulkan-icd-loader libappimage libpulse 
libva-nvidia-driver linux linux-firmware linux-headers linux-lts 
linux-lts-headers liquidctl lolcat mpv mtr nano net-tools networkmanager 
network-manager-applet nmap noto-fonts-cjk npm ntfs-3g ntfsprogs 
nvidia-open-dkms nvidia-settings nvme-cli ollama ollama-cuda openal 
openbsd-netcat os-prober pacman-contrib pandoc-cli perf pipewire 
pipewire-alsa pipewire-pulse pipewire-session-manager plasma-meta 
plasma-workspace postgresql python-aiohttp python-bcc python-beautifulsoup4 
python-dotenv python-maxminddb python-mutagen python-pip python-pipx 
python-pydantic python-scapy python-sqlalchemy python-virtualenv 
python-watchdog python-yara reflector rkhunter rsync rtl-sdr rust shellcheck 
smartmontools snes9x soundfont-fluid speech-dispatcher sshfs starship steam 
sysstat terminus-font traceroute tree turbostat ufw umu-launcher unzip uv vim 
wget wine wireless-regdb wireless_tools wireplumber wireshark-cli 
wireshark-qt xdg-utils xdotool xorg-bdftopcf xorg-docs xorg-fonts-100dpi 
xorg-fonts-75dpi xorg-fonts-misc xorg-font-util xorg-iceauth xorg-mkfontscale 
xorg-server-devel xorg-server-xvfb xorg-sessreg xorg-smproxy xorg-xbacklight 
xorg-xcmsdb xorg-xcursorgen xorg-xdriinfo xorg-xhost xorg-xinit xorg-xinput 
xorg-xkbevd xorg-xkbutils xorg-xkill xorg-xlsatoms xorg-xlsclients xorg-xpr 
xorg-xrandr xorg-xrefresh xorg-xsetroot xorg-xvinfo xorg-xwd xorg-xwininfo 
xorg-xwud xterm yt-dlp zram-generator 
```
</details>

## AUR packages (20)

Needs an AUR helper. Bootstrap `paru` first:

```bash
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si
paru -S --needed - < pkglist-aur-explicit.txt
```

```
  1oom-git
  chirp-next
  chkrootkit
  dwarffortress-linuxdwarfpack-appimage
  gnome-icon-theme
  gtk2
  k5prog-git
  lib32-giflib
  lib32-gtk2
  lib32-openal
  lib32-sdl2-compat
  lib32-v4l-utils
  maplemono-nf
  maplemono-ttf
  metropolis
  mpv-uosc-git
  paru
  python312
  ubuntu-themes
  ventoy-bin
```

## Flatpak (13)

```bash
cut -f1 pkglist-flatpak.txt | xargs flatpak install -y flathub
```

```
  com.discordapp.Discord	Discord
  com.github.PintaProject.Pinta	Pinta
  com.google.Chrome	Google Chrome
  com.heroicgameslauncher.hgl	Heroic
  com.obsproject.Studio	OBS Studio
  com.vysp3r.ProtonPlus	ProtonPlus
  io.github.seadve.Kooha	Kooha
  net.davidotek.pupgui2	ProtonUp-Qt
  net.lutris.Lutris	Lutris
  org.chromium.Chromium	Chromium Web Browser
  org.garudalinux.firedragon	FireDragon
  org.ghidra_sre.Ghidra	Ghidra
  org.kde.kdenlive	Kdenlive
```

## Notes

- `pacman -Qqen` / `-Qqem` list only **explicitly installed** packages.
  Dependencies are resolved automatically, so this is the minimal set.
- `gnome-icon-theme`, `humanity-icon-theme` and `ubuntu-themes` are
  inheritance fallbacks for the Sweet-Rainbow icon theme. The active theme is
  now candy-icons (inherits breeze-dark, Adwaita, hicolor), so they are only
  needed if switching back.
- `gtk2` and `lib32-gtk2` are in the AUR because Arch dropped GTK2 from the
  repos; Wine and older applications still need them.
- `claude-code` is installed by its native installer (`~/.local/bin/claude`),
  not from the AUR.
