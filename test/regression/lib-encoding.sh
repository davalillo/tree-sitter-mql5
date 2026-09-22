#!/usr/bin/env bash
# Encoding detection and transcoding helpers for the regression harness.
#
# MetaEditor commonly saves MQL sources as UTF-16LE (with or without BOM),
# which `tree-sitter parse` cannot read directly. These helpers detect the
# encoding of a file and transcode UTF-16 variants to UTF-8 on stdout.
#
# Sourcing this file has no side effects; it only defines two functions:
#   detect_encoding <file>    -> echoes: utf16le | utf16be | utf8bom |
#                                utf16le_nobom | utf8
#   transcode_to_utf8 <file>  -> writes UTF-8 bytes to stdout

# Guard against double-sourcing.
if [[ -n "${_LIB_ENCODING_SH_SOURCED:-}" ]]; then
  return 0
fi
_LIB_ENCODING_SH_SOURCED=1

# detect_encoding <file>
# Echoes one of: utf16le (BOM FF FE), utf16be (BOM FE FF), utf8bom
# (BOM EF BB BF), utf16le_nobom (no BOM but NUL bytes in the first 4 KB,
# the MetaEditor-without-BOM case), or utf8 (everything else).
detect_encoding() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "detect_encoding: not a file: $file" >&2
    return 1
  fi

  # BOM detection: inspect the first 3 bytes.
  local bom
  bom="$(head -c 3 "$file" | od -An -tx1 | tr -d ' \n')"
  case "$bom" in
    fffe*) echo "utf16le"; return 0 ;;
    feff*) echo "utf16be"; return 0 ;;
    efbbbf*) echo "utf8bom"; return 0 ;;
  esac

  # Heuristic: no BOM, but NUL bytes in the first 4 KB imply UTF-16LE
  # (ASCII-range MQL sources interleave NUL bytes when encoded as UTF-16).
  # grep cannot match NUL bytes in a pattern argument, so look for "00" hex
  # tokens in an od dump instead.
  if head -c 4096 "$file" | od -An -tx1 | grep -q ' 00'; then
    echo "utf16le_nobom"
    return 0
  fi

  echo "utf8"
}

# _transcode_via_iconv <from-encoding> <file>
# Transcodes <file> to UTF-8 on stdout and strips a leading UTF-8 BOM if the
# transcoded output starts with one (a UTF-16 BOM becomes EF BB BF).
_transcode_via_iconv() {
  local from="$1" file="$2"
  if ! command -v iconv >/dev/null 2>&1; then
    echo "transcode_to_utf8: iconv is required but was not found on PATH" >&2
    return 1
  fi

  local tmp
  tmp="$(mktemp)" || return 1
  if ! iconv -f "$from" -t UTF-8 "$file" >"$tmp"; then
    rm -f "$tmp"
    echo "transcode_to_utf8: iconv -f $from failed for $file" >&2
    return 1
  fi

  # Strip a leading U+FEFF (EF BB BF) if present.
  if [[ "$(head -c 3 "$tmp" | od -An -tx1 | tr -d ' \n')" == "efbbbf" ]]; then
    tail -c +4 "$tmp"
  else
    cat "$tmp"
  fi
  rm -f "$tmp"
}

# transcode_to_utf8 <file>
# Writes the file's content as UTF-8 to stdout. UTF-8 variants (with or
# without BOM) are passed through unchanged; UTF-16 variants are transcoded
# with iconv and any leading BOM is stripped. Fails loudly (non-zero exit,
# set -e compatible) if iconv is missing or transcoding fails.
transcode_to_utf8() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "transcode_to_utf8: not a file: $file" >&2
    return 1
  fi

  local enc
  enc="$(detect_encoding "$file")"
  case "$enc" in
    utf8 | utf8bom)
      # Already UTF-8: pass bytes through unchanged.
      cat "$file"
      ;;
    utf16le)
      _transcode_via_iconv UTF-16LE "$file"
      ;;
    utf16be)
      _transcode_via_iconv UTF-16BE "$file"
      ;;
    utf16le_nobom)
      _transcode_via_iconv UTF-16LE "$file"
      ;;
    *)
      echo "transcode_to_utf8: unknown encoding '$enc' for $file" >&2
      return 1
      ;;
  esac
}
