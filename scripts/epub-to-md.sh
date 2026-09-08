#!/bin/bash
# epub-to-md.sh — convert EPUB / PDF / TXT / HTML into Kaia knowledge-base Markdown.
#
# This is a thin picker around tools/maintenance/ebook_to_kb_md.py, which does the actual
# conversion and cleanup. It used to call `pandoc -s` directly and drop the result in
# knowledge_base/ root; that produced files full of pandoc/calibre artifacts (fenced divs,
# empty anchors, inline style spans, dead image links) with calibre's own YAML frontmatter
# instead of Kaia's schema, and no chapter headings — all of which degrade RAG retrieval.

set -uo pipefail

# This script used to live inside the Kaiacord repo and derived PROJECT_ROOT from
# its own location ("$SCRIPT_DIR/.."). It now lives in $HOME, where that would
# resolve to /home -- so point it at the repo explicitly instead. Override with
# KAIA_PROJECT_ROOT=/path/to/repo if the repo ever moves.
PROJECT_ROOT="${KAIA_PROJECT_ROOT:-$HOME/github/Kaiacord}"
CONVERTER="$PROJECT_ROOT/tools/maintenance/ebook_to_kb_md.py"

# --- Configuration ---------------------------------------------------------------
SOURCE_DIR="${SOURCE_DIR:-$HOME/Downloads}"
BOOKS_DIR="$PROJECT_ROOT/knowledge_base/books"
DOCS_DIR="$PROJECT_ROOT/knowledge_base/documents"
# ---------------------------------------------------------------------------------

PYTHON="$PROJECT_ROOT/venv/bin/python3"
[[ -x "$PYTHON" ]] || PYTHON="python3"

RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'; GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'

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
    echo -e "${CYAN}${BOLD}EPUB / PDF / TXT → Kaia Knowledge Base${NC}"
  fi
  echo -e "\n${CYAN}Source:${NC} $SOURCE_DIR"
  echo -e "${CYAN}Output:${NC} books → knowledge_base/books   ·   articles → knowledge_base/documents\n"
}

# --- Dependency checks -----------------------------------------------------------
missing=0
command -v pandoc    &>/dev/null || { echo -e "${RED}pandoc not found${NC}      (EPUB/HTML input) — sudo pacman -S pandoc"; missing=1; }
command -v pdftotext &>/dev/null || { echo -e "${YELLOW}pdftotext not found${NC}   (PDF input)       — sudo pacman -S poppler"; }
[[ -f "$CONVERTER" ]] || { echo -e "${RED}Converter not found: $CONVERTER${NC}"; exit 1; }
[[ $missing -eq 1 ]] && exit 1

show_welcome_message

mapfile -t input_files < <(find "$SOURCE_DIR" -maxdepth 1 -type f \
  \( -iname "*.epub" -o -iname "*.pdf" -o -iname "*.txt" -o -iname "*.html" -o -iname "*.htm" \) | sort)

if [ ${#input_files[@]} -eq 0 ]; then
  echo "No .epub / .pdf / .txt / .html files found in $SOURCE_DIR"
  exit 1
fi

echo "Select a file to convert:"
echo "  0) ALL FILES"
for i in "${!input_files[@]}"; do
  printf "  %d) %s\n" "$((i+1))" "$(basename "${input_files[$i]}")"
done
echo
read -rp "Number (0 for all): " choice

if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 0 || choice > ${#input_files[@]} )); then
  echo -e "${RED}Invalid selection.${NC}"; exit 1
fi

# Ask once for the destination and metadata that the converter cannot infer reliably.
echo
read -rp "Destination — [b]ooks or [d]ocuments? [b]: " dest
if [[ "${dest,,}" == d* ]]; then
  OUTDIR="$DOCS_DIR"
  read -rp "Filename topic prefix (e.g. AI, Security, Essay): " PREFIX
  PREFIX="${PREFIX:-Reference}"
else
  OUTDIR="$BOOKS_DIR"
  PREFIX="Book"
fi
read -rp "Category for frontmatter [Reference]: " CATEGORY
CATEGORY="${CATEGORY:-Reference}"

# A hand-written summary is worth far more to retrieval than an auto-extracted paragraph,
# so offer it — but leave it optional, the converter falls back to first real prose.
echo
echo -e "${CYAN}Optional:${NC} a one-paragraph summary improves RAG matching a lot."
read -rp "Summary (blank = auto): " SUMMARY

convert_one() {
  local file="$1"
  echo -e "\n${CYAN}→ $(basename "$file")${NC}"
  local args=( "$CONVERTER" "$file" --outdir "$OUTDIR" --category "$CATEGORY" --prefix "$PREFIX" --force )
  [[ -n "${SUMMARY:-}" ]] && args+=( --summary "$SUMMARY" )
  if "$PYTHON" "${args[@]}"; then
    echo -e "${GREEN}✔ done${NC}"
  else
    echo -e "${RED}✘ failed${NC}"
    return 1
  fi
}

if (( choice == 0 )); then
  echo -e "\nProcessing all files..."
  for f in "${input_files[@]}"; do convert_one "$f" || true; done
else
  convert_one "${input_files[$((choice-1))]}"
fi

echo
echo -e "${YELLOW}Reminder:${NC} run an incremental RAG refresh so Kaia indexes the new file(s)."
