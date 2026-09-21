# Feature: grammar-hardening

Goal: make the MQL4/MQL5/MQH grammar robust against real-world code, verified
recurringly against a real corpus downloaded from mql5.com.

Baseline (111 real files, 46,788 lines): 25 files (22.5%) with ERROR nodes;
61.5% of all lines fall inside ERROR nodes. Dominant causes:
1. `input group "..."` (24 files, MQL5 + modern MQL4) — swallows hundreds of
   lines per occurrence (up to 742 lines in VSA_Glossary.mq5).
2. Parenthesized assignment `(a = b)` (9 files) — legal C++, fails because the
   pinned 2023 tree-sitter-c excludes assignment_expression from _expression.

## Tasks

- [x] T1 Prepare build environment: npm deps over https, `tree-sitter generate`
      baseline working. Evidence: env-only (git insteadOf local config,
      submodule init, tree-sitter-c fcd1230 pinned in node_modules); no commit.
- [x] T2 Grammar extensions: `input_group`, MQL primitive types
      (string/datetime/color/uchar/ushort/uint/ulong), assignment_expression in
      _expression_not_binary (port of upstream fix); regenerate parser;
      `tree-sitter test` green. Evidence: commit 739e847. NOTE: the
      assignment_expression port was REVERTED during review — the isolated
      PREC swap (f3559c6) regresses the digraph corpus and does not fix the
      parse on the pinned base; documented as known limitation with a
      corpus tripwire instead.
- [x] T3 Corpus: new `test/corpus/mql4.txt` plus corpus cases for input_group
      and parenthesized assignment. Evidence: commit 739e847.
- [x] T4 Packaging: `mq4` file-type, queries/highlights.scm. Evidence: commit 1894b45.
- [x] T5 Recurrent regression harness: real corpus included in repo, refresh
      script, run script, checked-in baseline; npm scripts. Evidence: commit 9d34c26.
- [x] T6 CI: regression job comparing against baseline; Go and Rust build jobs.
      Evidence: commit bb2e13a.
- [x] T7 Re-run real corpus, record delta vs baseline, update baseline file.
      Evidence: baseline.txt in commit 9d34c26; delta below.

## Delta (T7, 111 real files, 46,788 lines)

| Metric | Before | After |
|---|---|---|
| Files with ERROR nodes | 25 (22.5%) | 2 (1.8%) |
| Lines inside ERROR nodes | 28,754 (61.5%) | 374 (0.80%) |

Remaining failures (both documented limitations, pinned as baseline):
- VR_Rsi_Robot.mq4 (3 nodes): parenthesized assignment — needs base regen.
- OneClickTradeManager.mq5 (2 nodes): macro-expansion-only string concat
  (`#define PFX "x"` + `PFX "bg"`) — intentional boundary.

## Notes

- Real corpus provenance: front-page listings of https://www.mql5.com/en/code/mt4
  and /mt5 (40 entries each), downloaded 2026-09-21, zips unpacked; only
  .mq4/.mq5/.mqh files retained (111 files, ~2 MB).
- Pre-existing local .gitignore edit (.atl/) is not part of this feature.
