#!/usr/bin/env bash

set -euo pipefail

MUSIC_DIR="/home/ekco/Music/music"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cd "$MUSIC_DIR"

echo "[*] Scanning MP3 files in $MUSIC_DIR..."

shopt -s nullglob
mp3_files=(*.mp3)

if [ ${#mp3_files[@]} -eq 0 ]; then
    echo "[!] No MP3 files found in $MUSIC_DIR."
    exit 0
fi

for file in "${mp3_files[@]}"; do
    # Check if MP3 already has an attached image stream
    has_art=$(ffprobe -v error -select_streams v -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || true)

    if [ -n "$has_art" ]; then
        echo "[=] Art already present: $file"
        continue
    fi

    # Strip extension to use filename as search query
    track_name="${file%.mp3}"
    echo "[+] Fetching art for: '$track_name'"

    # Clean temporary folder for current track
    rm -f "$TMP_DIR"/*

    # Download top search result thumbnail as PNG
    if ! yt-dlp "ytsearch1:${track_name}" \
        --write-thumbnail \
        --skip-download \
        --convert-thumbnails png \
        -o "$TMP_DIR/thumb.%(ext)s" \
        --no-warnings >/dev/null 2>&1; then
        echo "[!] Search failed for: $track_name"
        continue
    fi

    # Locate downloaded PNG thumbnail
    thumb_file=$(find "$TMP_DIR" -type f -name "thumb*.png" | head -n 1)

    if [ -z "$thumb_file" ]; then
        echo "[!] No thumbnail extracted for: $track_name"
        continue
    fi

    # Embed thumbnail into MP3 without re-encoding audio
    out_file="$TMP_DIR/temp_tagged.mp3"
    if ffmpeg -y -v quiet -i "$file" -i "$thumb_file" \
        -map 0:a -map 1:v \
        -c copy \
        -disposition:v:0 attached_pic \
        -id3v2_version 3 \
        "$out_file"; then
        mv "$out_file" "$file"
        echo "[✓] Successfully embedded art: $file"
    else
        echo "[!] Failed to embed art into: $file"
    fi
done

echo "[*] Completed album art processing."
