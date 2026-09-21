#!/usr/bin/env bash
# Real-code regression harness.
#
# Parses every file under test/real-corpus/ with `tree-sitter parse` and
# compares the number of `(ERROR` nodes per file against the recorded baseline
# (test/real-corpus/baseline.txt).
#
# Usage:
#   bash test/regression/run-regression.sh            # check mode (default)
#   bash test/regression/run-regression.sh --update   # rewrite the baseline
#
# Check mode exits 1 if any file has MORE errors than its baseline entry
# (regression), or if a corpus file is missing from the baseline (new corpus
# files must be baselined deliberately). Files with FEWER errors than the
# baseline are reported as IMPROVED; re-baseline with --update after review.
#
# NOTE: after refreshing the corpus with download-corpus.sh, re-baseline
# deliberately with `--update` after manual review of the new fixture set.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

CORPUS_DIR="test/real-corpus"
BASELINE="$CORPUS_DIR/baseline.txt"
UPDATE_MODE=0
if [[ "${1:-}" == "--update" ]]; then
  UPDATE_MODE=1
elif [[ -n "${1:-}" ]]; then
  echo "usage: $0 [--update]" >&2
  exit 2
fi

if ! command -v tree-sitter >/dev/null 2>&1; then
  echo "error: tree-sitter CLI not found on PATH" >&2
  exit 2
fi

results_file="$(mktemp)"
trap 'rm -f "$results_file"' EXIT

total_errors=0
files_with_errors=0
total_files=0

# Parse every corpus file (sorted for deterministic output) and count ERROR nodes.
while IFS= read -r -d '' f; do
  count="$(tree-sitter parse "$f" 2>/dev/null | grep -c '(ERROR' || true)"
  total_files=$((total_files + 1))
  total_errors=$((total_errors + count))
  if [[ "$count" -gt 0 ]]; then
    files_with_errors=$((files_with_errors + 1))
  fi
  printf '%s %s\n' "$count" "$f" >>"$results_file"
done < <(find "$CORPUS_DIR" -type f -name '*.mq*' -print0 | sort -z)

if [[ "$UPDATE_MODE" -eq 1 ]]; then
  cp "$results_file" "$BASELINE"
  echo "Baseline updated: $BASELINE"
  echo "Summary: $total_files files, $files_with_errors with errors, $total_errors total ERROR nodes"
  exit 0
fi

if [[ ! -f "$BASELINE" ]]; then
  echo "error: baseline missing at $BASELINE (run with --update to create it)" >&2
  exit 1
fi

regressions=()
improvements=()
missing_from_baseline=0

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  count="${line%% *}"
  path="${line#* }"
  base_count="$(grep -F " $path" "$BASELINE" | head -n1 | awk '{print $1}')"
  if [[ -z "$base_count" ]]; then
    missing_from_baseline=$((missing_from_baseline + 1))
    regressions+=("$path (missing from baseline: has $count errors)")
  elif [[ "$count" -gt "$base_count" ]]; then
    regressions+=("$path (baseline: $base_count, now: $count)")
  elif [[ "$count" -lt "$base_count" ]]; then
    improvements+=("$path (baseline: $base_count, now: $count)")
  fi
done <"$results_file"

echo "Summary: $total_files files, $files_with_errors with errors, $total_errors total ERROR nodes"

status=0
if [[ "${#regressions[@]}" -gt 0 || "$missing_from_baseline" -gt 0 ]]; then
  echo "REGRESSIONS (${#regressions[@]}):"
  printf '  %s\n' "${regressions[@]:-}"
  status=1
fi
if [[ "${#improvements[@]}" -gt 0 ]]; then
  echo "IMPROVED (${#improvements[@]}) - fewer errors than baseline; re-baseline with --update after review:"
  printf '  %s\n' "${improvements[@]:-}"
fi
if [[ "$status" -eq 0 ]]; then
  echo "OK: no regressions against baseline"
fi
exit "$status"
