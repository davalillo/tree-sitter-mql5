# Real-code corpus

Parser regression fixtures built from real-world MQL4/MQL5/MQH code.

## Provenance

Collected from the first-page listings of https://www.mql5.com/en/code/mt4 and
https://www.mql5.com/en/code/mt5 (40 entries each), downloaded 2026-09-21. The
downloaded zips were unpacked and only source files with the `.mq4`, `.mq5` or
`.mqh` extensions were retained: **111 files** total (41 in `mt4/`, 70 in
`mt5/`). Filenames and directory names are normalized by replacing spaces with
underscores (e.g. `EMTOrdersUtility v2.3.mq5` -> `EMTOrdersUtility_v2.3.mq5`).

## Purpose

These files exercise the grammar against real code, not synthetic cases. They
are run by `test/regression/run-regression.sh`, which parses every file with
`tree-sitter parse` and compares the number of `(ERROR` nodes per file against
`baseline.txt`. It is also run by the CI `regression` job: a commit that
increases the error count on any corpus file fails the build.

## Layout

- `mt4/` — flat MQL4 `.mq4` sources.
- `mt5/` — MQL5 sources, preserving the unpacked relative structure (e.g.
  `mql5/Include/...`, `mql5/Experts/...`), with `.mq5` and `.mqh` files.
- `baseline.txt` — known per-file `(ERROR` counts (`N path` per line), sorted.

## Refresh

`bash test/regression/download-corpus.sh` re-downloads the current front-page
entries and replaces the corpus. Because the upstream listing changes over
time, a refresh intentionally changes the fixture set: after refreshing, review
the diff, then re-baseline deliberately with
`bash test/regression/run-regression.sh --update`.
