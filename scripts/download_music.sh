#!/usr/bin/env bash

set -euo pipefail

PLAYLIST_URL="https://www.youtube.com/playlist?list=PLmmemn85rlKWxoTD47ShRVONJZQRihzAN"
DEST_DIR="/home/ekco/Music/music"
URL_LIST_FILE="${DEST_DIR}/playlist_urls.txt"
ARCHIVE_FILE="${DEST_DIR}/downloaded.txt"

mkdir -p "$DEST_DIR"

echo "[1/3] Extracting URLs from YouTube playlist..."
yt-dlp --flat-playlist \
       --print "%(url)s" \
       "$PLAYLIST_URL" > "$URL_LIST_FILE"

TOTAL_URLS=$(wc -l < "$URL_LIST_FILE")
echo "[+] Extracted $TOTAL_URLS track URLs to $URL_LIST_FILE"

echo "[2/3] Downloading audio, converting cover art, and tagging MP3s..."
yt-dlp \
  --batch-file="$URL_LIST_FILE" \
  --download-archive "$ARCHIVE_FILE" \
  -o "${DEST_DIR}/%(title)s.%(ext)s" \
  -x \
  --audio-format mp3 \
  --audio-quality 0 \
  --convert-thumbnails jpg \
  --embed-thumbnail \
  --embed-metadata \
  --postprocessor-args "EmbedThumbnail+ffmpeg:-disposition:v attached_pic" \
  --extractor-args "youtube:player_client=android,web" \
  --ignore-errors \
  --no-overwrites

echo "[3/3] Cleaning up loose thumbnail images..."
find "$DEST_DIR" -maxdepth 1 -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.webp" \) -delete

echo "[+] Execution completed successfully."
