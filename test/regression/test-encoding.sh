#!/usr/bin/env bash
# Self-test for the encoding layer (lib-encoding.sh).
#
# Verifies that detect_encoding and transcode_to_utf8 handle the encodings
# MetaEditor produces: UTF-16LE with BOM, UTF-16LE without BOM, UTF-8 with
# BOM, and plain UTF-8. Ends with an end-to-end parse check of the
# transcoded output when the tree-sitter CLI is available.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-encoding.sh
source "$SCRIPT_DIR/lib-encoding.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Canonical UTF-8 source (no BOM).
src="$tmp/sample.mq5"
cat >"$src" <<'EOF'
input group "G";
int OnInit() { return(INIT_SUCCEEDED); }
EOF

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

assert_eq() { # assert_eq <description> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    pass "$1"
  else
    fail "$1 (expected: $2, got: $3)"
  fi
}

# --- Build encoded variants -------------------------------------------------

# UTF-16LE with BOM (iconv adds the BOM for UTF-16).
src_utf16le_bom="$tmp/utf16le_bom.mq5"
iconv -f UTF-8 -t UTF-16 "$src" >"$src_utf16le_bom"

# UTF-16LE without BOM: strip the 2-byte BOM from the UTF-16 output.
src_utf16le_nobom="$tmp/utf16le_nobom.mq5"
tail -c +3 "$src_utf16le_bom" >"$src_utf16le_nobom"

# UTF-8 with BOM.
src_utf8bom="$tmp/utf8bom.mq5"
printf '\xef\xbb\xbf' >"$src_utf8bom"
cat "$src" >>"$src_utf8bom"

# --- a) detect_encoding -----------------------------------------------------

assert_eq "detect_encoding: UTF-16LE with BOM" "utf16le" "$(detect_encoding "$src_utf16le_bom")"
assert_eq "detect_encoding: UTF-16LE without BOM" "utf16le_nobom" "$(detect_encoding "$src_utf16le_nobom")"
assert_eq "detect_encoding: UTF-8 with BOM" "utf8bom" "$(detect_encoding "$src_utf8bom")"
assert_eq "detect_encoding: plain UTF-8" "utf8" "$(detect_encoding "$src")"

# --- b) transcode_to_utf8 is byte-identical to the original ------------------

assert_bytes_eq() { # assert_bytes_eq <description> <expected-file> <command...>
  local desc="$1" expected="$2"
  shift 2
  if cmp -s "$expected" <("$@"); then
    pass "$desc"
  else
    fail "$desc (byte mismatch)"
  fi
}

assert_bytes_eq "transcode_to_utf8: UTF-16LE with BOM" "$src" transcode_to_utf8 "$src_utf16le_bom"
assert_bytes_eq "transcode_to_utf8: UTF-16LE without BOM" "$src" transcode_to_utf8 "$src_utf16le_nobom"
assert_bytes_eq "transcode_to_utf8: UTF-8 with BOM passthrough" "$src_utf8bom" transcode_to_utf8 "$src_utf8bom"
assert_bytes_eq "transcode_to_utf8: plain UTF-8 passthrough" "$src" transcode_to_utf8 "$src"

# --- c) end-to-end parse of transcoded output --------------------------------

if ! command -v tree-sitter >/dev/null 2>&1; then
  if [[ -x "$HOME/.npm-global/bin/tree-sitter" ]]; then
    export PATH="$PATH:$HOME/.npm-global/bin"
  fi
fi

if command -v tree-sitter >/dev/null 2>&1; then
  transcode_to_utf8 "$src_utf16le_bom" >"$tmp/parsed_bom.mq5"
  transcode_to_utf8 "$src_utf16le_nobom" >"$tmp/parsed_nobom.mq5"
  for parsed in "$tmp/parsed_bom.mq5" "$tmp/parsed_nobom.mq5"; do
    errors="$(tree-sitter parse "$parsed" 2>/dev/null | grep -c -E '\((ERROR|MISSING)' || true)"
    assert_eq "end-to-end parse: $parsed has 0 ERROR/MISSING nodes" "0" "$errors"
  done
else
  echo "SKIP: end-to-end parse check (tree-sitter CLI not on PATH or at ~/.npm-global/bin)"
fi

if [[ "$failures" -gt 0 ]]; then
  echo "test-encoding: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-encoding: all assertions passed"
