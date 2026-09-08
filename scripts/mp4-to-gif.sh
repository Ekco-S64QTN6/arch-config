#!/bin/bash

MAX_SIZE_MB=200
MAX_SIZE_BYTES=$((MAX_SIZE_MB * 1024 * 1024))
MIN_FPS=20
INITIAL_WIDTH=720

show_welcome_message() {
  clear
  if command -v lolcat &>/dev/null; then
    cat << "EOF" | lolcat
▓█████  ██ ▄█▀ ▄████▄   ▒█████
▓█  ▀  ██▄█▒ ▒██▀ ▀█  ▒██▒  ██▒
▒███   ▓███▄░ ▒▓█   ▄ ▒██░  ██▒
▒▓█  ▄ ▓██ █▄ ▒▓▓▄ ▄██▒▒██   ██░
░▒████▒▒██▒ █▄▒ ▓███▀ ░░ ████▓▒░
░░ ▒░ ░▒ ▒▒ ▓▒░ ░▒ ▒   ░ ▒░▒░▒░
  ░ ░  ░ ░▒ ▒░  ░ ▒     ░ ▒ ▒░
    ░  ░ ░░ ░ ░       ░ ░ ░ ▒
    ░  ░  ░   ░ ░       ░   ░
              ░
EOF
  else
    echo -e "\033[1;36mMp4/WebM to High-Quality GIF Converter\033[0m"
    echo -e "\n\033[1;34mAutomatically matches source FPS and stays under Imgur limit.\033[0m\n"
  fi
  sleep 1
}

show_welcome_message

# --- Dependency check ---------------------------------------------------------
# This used to rely on `bc`, which is not installed here and failed *silently*:
# the FPS cap quietly took the else branch, and the retry loop's width reduction
# evaluated to 0, which tripped the "minimum quality" guard and broke out of the
# loop after one pass. Both are now awk, which ships with base.
for _dep in ffmpeg ffprobe awk; do
  if ! command -v "$_dep" &>/dev/null; then
    echo -e "\033[91mError: '$_dep' is required but not installed.\033[0m"
    exit 1
  fi
done

DOWNLOADS_DIR="/home/ekco/Downloads"

mapfile -t video_files < <(find "$DOWNLOADS_DIR" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.webm" \))

if [ ${#video_files[@]} -eq 0 ]; then
  echo "No .mp4 or .webm files found in $DOWNLOADS_DIR"
  exit 1
fi

echo "Please select a file to convert:"
for i in "${!video_files[@]}"; do
  echo "$((i+1))) $(basename "${video_files[$i]}")"
done

read -rp "Enter the number of the file: " choice

if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#video_files[@]} ]; then
  echo "Invalid selection."
  exit 1
fi

INPUT_FILE="${video_files[$((choice-1))]}"
OUTPUT_FILE="${INPUT_FILE%.*}.gif"

echo "Detecting source FPS..."

RAW_FPS=$(ffprobe -v 0 -select_streams v:0 \
  -show_entries stream=r_frame_rate \
  -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")

SOURCE_FPS=$(awk -v r="$RAW_FPS" 'BEGIN { split(r,a,"/"); print a[1]/a[2] }')

# Cap absurd FPS
if awk -v f="$SOURCE_FPS" 'BEGIN { exit !(f > 50) }'; then
  FPS=50
else
  FPS=$(printf "%.0f" "$SOURCE_FPS")
fi

WIDTH=$INITIAL_WIDTH

echo "Initial FPS: $FPS"
echo "Initial Width: $WIDTH"

while true; do
  echo "Rendering GIF (width=$WIDTH, fps=$FPS)..."

  ffmpeg -y -i "$INPUT_FILE" \
    -vf "fps=$FPS,scale=$WIDTH:-1:flags=lanczos,split[s0][s1]; \
[s0]palettegen=max_colors=256:stats_mode=full[p]; \
[s1][p]paletteuse=dither=sierra2_4a" \
    -loop 0 "$OUTPUT_FILE"

  if [ ! -s "$OUTPUT_FILE" ]; then
    echo "Error: ffmpeg produced no output. Aborting."
    exit 1
  fi

  FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")

  if [ "$FILE_SIZE" -le "$MAX_SIZE_BYTES" ]; then
    echo "Final size: $((FILE_SIZE / 1024 / 1024))MB"
    echo "Success: Under Imgur limit."
    break
  fi

  echo "Too large: $((FILE_SIZE / 1024 / 1024))MB. Reducing quality..."

  # Reduce width by 15%
  WIDTH=$(awk -v w="$WIDTH" 'BEGIN { printf "%.0f", w * 0.85 }')

  # If width drops significantly, start lowering FPS gradually
  if [ "$WIDTH" -lt 480 ] && [ "$FPS" -gt "$MIN_FPS" ]; then
    FPS=$((FPS - 5))
    if [ "$FPS" -lt "$MIN_FPS" ]; then
      FPS=$MIN_FPS
    fi
  fi

  # Absolute floor safeguard
  if [ "$WIDTH" -lt 320 ]; then
    echo "Warning: Hit minimum quality thresholds."
    break
  fi
done

echo "Conversion complete:"
echo "$OUTPUT_FILE"
