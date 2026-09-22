#!/usr/bin/env bash
# Refresh the real-code corpus from the current mql5.com code listings.
#
# Downloads the first-page entries of https://www.mql5.com/en/code/mt4 and
# /mt5, unpacks each zip and copies only .mq4/.mq5/.mqh sources into
# test/real-corpus/mt4 or mt5, preserving the mt5 relative structure and
# normalizing spaces to underscores in file and directory names.
#
# NOTE: a refresh intentionally changes the fixture set (the upstream listing
# changes over time). After refreshing, review the diff, then re-confirm the
# baseline deliberately with:
#   bash test/regression/run-regression.sh --update
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORPUS_DIR="$REPO_ROOT/test/real-corpus"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fetch() {
  local section="$1"   # mt4 | mt5
  local dest="$CORPUS_DIR/$section"
  mkdir -p "$dest" "$tmp/$section"

  # Extract entry ids from the listing page: href="/en/code/<id>"
  curl -fsSL -A "$UA" "https://www.mql5.com/en/code/$section" |
    grep -oE 'href="/en/code/[0-9]+"' |
    grep -oE '[0-9]+' | sort -u >"$tmp/$section/ids.txt"

  echo "$section: $(wc -l <"$tmp/$section/ids.txt") listing entries found"

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    local zip="$tmp/$section/$id.zip"
    local unpack="$tmp/$section/$id"
    if ! curl -fsSL -A "$UA" -o "$zip" "https://www.mql5.com/en/code/download/$id"; then
      echo "warning: download failed for entry $id, skipping" >&2
      continue
    fi
    mkdir -p "$unpack"
    if ! unzip -qo "$zip" -d "$unpack" 2>/dev/null; then
      echo "warning: unzip failed for entry $id, skipping" >&2
      continue
    fi
    # Copy only source files, preserving structure, spaces -> underscores.
    (cd "$unpack" && find . -type f \( -name '*.mq4' -o -name '*.mq5' -o -name '*.mqh' \) -print0) |
      while IFS= read -r -d '' rel; do
        local target="$dest/$(printf '%s' "$rel" | tr ' ' '_')"
        mkdir -p "$(dirname "$target")"
        cp "$unpack/$rel" "$target"
      done
  done <"$tmp/$section/ids.txt"

  echo "$section: $(find "$dest" -type f | wc -l) source files in corpus"
}

fetch mt4
fetch mt5

echo "Corpus refreshed: $(find "$CORPUS_DIR" -type f -name '*.mq*' | wc -l) source files."
echo "Re-baseline deliberately after manual review: bash test/regression/run-regression.sh --update"
