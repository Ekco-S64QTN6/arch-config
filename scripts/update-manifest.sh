#!/bin/bash
# ============================================================
# UPDATE PACKAGE MANIFEST
# Regenerates docs/pkglist-*.txt and docs/PACKAGES.md from the
# live system, so the restore point does not drift.
#
# Usage: update-manifest.sh [path/to/arch-config]
#        (defaults to ~/github/arch-config)
# ============================================================
set -euo pipefail

REPO="${1:-$HOME/github/arch-config}"
DOCS="$REPO/docs"
[ -d "$DOCS" ] || { echo "No docs/ under $REPO" >&2; exit 1; }

pacman -Qqen | sort > "$DOCS/pkglist-repo-explicit.txt"
pacman -Qqem | sort > "$DOCS/pkglist-aur-explicit.txt"
flatpak list --app --columns=application,name | sort > "$DOCS/pkglist-flatpak.txt"

n_repo=$(wc -l < "$DOCS/pkglist-repo-explicit.txt")
n_aur=$(wc -l < "$DOCS/pkglist-aur-explicit.txt")
n_flat=$(wc -l < "$DOCS/pkglist-flatpak.txt")

{
  cat <<EOF
# Package Manifest

Generated $(date +%F) on Arch Linux, kernel $(uname -r) by \`scripts/update-manifest.sh\`.

Machine-readable lists live alongside this file:
\`pkglist-repo-explicit.txt\`, \`pkglist-aur-explicit.txt\`, \`pkglist-flatpak.txt\`.

## Repository packages ($n_repo explicit)

\`\`\`bash
sudo pacman -S --needed - < pkglist-repo-explicit.txt
\`\`\`

<details><summary>Full list</summary>

\`\`\`
EOF
  tr '\n' ' ' < "$DOCS/pkglist-repo-explicit.txt" | fold -s -w 78
  cat <<EOF

\`\`\`
</details>

## AUR packages ($n_aur)

Needs an AUR helper. Bootstrap \`paru\` first:

\`\`\`bash
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si
paru -S --needed - < pkglist-aur-explicit.txt
\`\`\`

\`\`\`
EOF
  sed 's/^/  /' "$DOCS/pkglist-aur-explicit.txt"
  cat <<EOF
\`\`\`

## Flatpak ($n_flat)

\`\`\`bash
cut -f1 pkglist-flatpak.txt | xargs flatpak install -y flathub
\`\`\`

\`\`\`
EOF
  sed 's/^/  /' "$DOCS/pkglist-flatpak.txt"
  cat <<'EOF'
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
EOF
} > "$DOCS/PACKAGES.md"

echo "Manifest updated: $n_repo repo, $n_aur AUR, $n_flat flatpak."
