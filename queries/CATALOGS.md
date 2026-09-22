# Vendored MQL5 builtin catalogs

The JSON catalogs consumed by `scripts/build-highlights.js` are vendored
verbatim (plain, sorted JSON arrays of strings — do not add headers, keys or
any other element to them):

| File | Source | Entries |
| --- | --- | --- |
| `queries/mql5-constants.json` | `queries/mql5/mql5_constants.json` in m0n99/tree-sitter-mql5 | 1084 |
| `queries/mql5-functions.json` | `queries/mql5/mql5_functions.json` in m0n99/tree-sitter-mql5 | 507 |

## Source and license

- Source repository: [m0n99/tree-sitter-mql5](https://github.com/m0n99/tree-sitter-mql5)
  (`main` branch, 2026-01), licensed under **ISC** — reuse with attribution is
  permitted (see ACKNOWLEDGMENTS.md).
- The catalog contents were originally scraped by that repository's
  `build-highlights.js` from the **official MQL5 documentation**
  ([docs.mql5.com](https://www.mql5.com/en/docs) / constants reference).

## Regeneration

To refresh the catalogs from upstream (or re-download them if lost):

```sh
curl -sSf -o queries/mql5-constants.json \
  https://raw.githubusercontent.com/m0n99/tree-sitter-mql5/main/queries/mql5/mql5_constants.json
curl -sSf -o queries/mql5-functions.json \
  https://raw.githubusercontent.com/m0n99/tree-sitter-mql5/main/queries/mql5/mql5_functions.json
```

Then regenerate the query blocks and re-verify:

```sh
npm run build:highlights   # twice: the second run must be a no-op
~/.npm-global/bin/tree-sitter query queries/highlights.scm <sample .mq5 file>
```

## Invariants

- Both files must remain **plain JSON arrays of strings**, sorted and
  duplicate-free (the generator re-sorts and de-duplicates defensively, but
  diffs stay readable only if the vendored files are normalized).
- `scripts/build-highlights.js` only rewrites the content between the
  `; BEGIN BUILTIN CONSTANTS` / `; END BUILTIN CONSTANTS` and
  `; BEGIN BUILTIN FUNCTIONS` / `; END BUILTIN FUNCTIONS` marker pairs in
  `queries/highlights.scm`; hand-written rules above the markers must not be
  edited by the generator.
