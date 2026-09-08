# Package Manifest

Generated 2026-09-08 on Arch Linux, kernel 7.2.3-arch1-2.

Machine-readable lists live alongside this file:
`pkglist-repo-explicit.txt`, `pkglist-aur-explicit.txt`, `pkglist-flatpak.txt`.

## Repository packages (165 explicit)

```bash
sudo pacman -S --needed - < pkglist-repo-explicit.txt
```

<details><summary>Full list</summary>

```
adobe-source-han-sans-jp-fonts adobe-source-han-serif-jp-fonts aircrack-ng 
alsa-plugins alsa-utils amd-ucode arch-install-scripts ark base base-devel 
bash-completion bat bluez-utils bpytop btop cmake cpupower cuda cudnn dkms 
dolphin dosfstools efibootmgr electron39 elementary-icon-theme ethtool 
fastfetch flameshot fluidsynth fzf gamemode git goverlay gparted gqrx grub 
gst-plugin-pipewire hashcat hcxtools htop imagemagick iotop iw iwd jq kate 
kitty kwalletmanager lib32-alsa-lib lib32-alsa-plugins lib32-gamemode 
lib32-gnutls lib32-gtk3 lib32-libpng lib32-libpulse lib32-libva 
lib32-libxcomposite lib32-libxinerama lib32-mesa lib32-ocl-icd lib32-sqlite 
lib32-vulkan-icd-loader libappimage libpulse libva-nvidia-driver linux 
linux-firmware linux-headers liquidctl lolcat mtr nano net-tools 
network-manager-applet networkmanager nmap noto-fonts-cjk npm ntfs-3g 
ntfsprogs nvidia-open-dkms nvidia-settings nvme-cli ollama ollama-cuda openal 
openbsd-netcat os-prober pacman-contrib pandoc-cli pipewire pipewire-alsa 
pipewire-pulse pipewire-session-manager plasma-meta plasma-workspace 
postgresql python-pip python-pipx python-scapy python-virtualenv reflector 
rkhunter rsync rtl-sdr rust shellcheck smartmontools soundfont-fluid 
speech-dispatcher sshfs starship steam sysstat terminus-font traceroute tree 
ufw umu-launcher unzip uv vim wget wine wireless-regdb wireless_tools 
wireplumber wireshark-cli wireshark-qt xdg-utils xdotool xorg-bdftopcf 
xorg-docs xorg-font-util xorg-fonts-100dpi xorg-fonts-75dpi xorg-fonts-misc 
xorg-iceauth xorg-mkfontscale xorg-server-devel xorg-sessreg xorg-smproxy 
xorg-xbacklight xorg-xcmsdb xorg-xcursorgen xorg-xdriinfo xorg-xhost 
xorg-xinit xorg-xinput xorg-xkbevd xorg-xkbutils xorg-xkill xorg-xlsatoms 
xorg-xlsclients xorg-xpr xorg-xrandr xorg-xrefresh xorg-xsetroot xorg-xvinfo 
xorg-xwd xorg-xwininfo xorg-xwud xterm yt-dlp zram-generator 
```
</details>

## AUR packages (19)

Needs an AUR helper. Bootstrap `paru` first:

```bash
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si
paru -S --needed - < pkglist-aur-explicit.txt
```

```
  1oom-git
  chkrootkit
  claude-code
  dwarffortress-linuxdwarfpack-appimage
  gnome-icon-theme
  gtk2
  lib32-giflib
  lib32-gtk2
  lib32-openal
  lib32-sdl2-compat
  lib32-v4l-utils
  maplemono-nf
  maplemono-ttf
  metropolis
  paru
  python312
  ubuntu-themes
  unimatrix-git
  ventoy-bin
```

## Flatpak (13)

```bash
xargs -a pkglist-flatpak.txt flatpak install -y flathub
```

```
  com.discordapp.Discord	Discord
  com.github.PintaProject.Pinta	Pinta
  com.google.Chrome	Google Chrome
  com.heroicgameslauncher.hgl	Heroic
  com.obsproject.Studio	OBS Studio
  com.vysp3r.ProtonPlus	ProtonPlus
  io.github.seadve.Kooha	Kooha
  io.mpv.Mpv	mpv
  net.davidotek.pupgui2	ProtonUp-Qt
  net.lutris.Lutris	Lutris
  org.chromium.Chromium	Chromium Web Browser
  org.garudalinux.firedragon	FireDragon
  org.kde.kdenlive	Kdenlive
```

## Notes

- `pacman -Qqen` / `-Qqem` list only **explicitly installed** packages.
  Dependencies are resolved automatically, so this is the minimal set.
- Several AUR packages here are load-bearing for the icon theme
  (`gnome-icon-theme`, `humanity-icon-theme`, `ubuntu-themes`) — they are
  inheritance fallbacks for Sweet-Rainbow, not leftovers.
- `gtk2` and `lib32-gtk2` are in the AUR because Arch dropped GTK2 from the
  repos; Wine and older applications still need them.
