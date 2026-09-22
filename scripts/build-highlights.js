"use strict";

// Generates the "BUILTIN CONSTANTS" and "BUILTIN FUNCTIONS" blocks of
// queries/highlights.scm from the vendored MQL5 catalogs, between explicit
// markers. Adapted from the generator technique of m0n99/tree-sitter-mql5
// (build-highlights.js, ISC), without the network fetch: catalogs are
// vendored (see queries/CATALOGS.md) and ultimately derived from the official
// mql5.com documentation.

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const CONSTANTS_JSON = path.join(ROOT, "queries", "mql5-constants.json");
const FUNCTIONS_JSON = path.join(ROOT, "queries", "mql5-functions.json");
const HIGHLIGHTS_SCM = path.join(ROOT, "queries", "highlights.scm");
const NODE_TYPES_JSON = path.join(ROOT, "src", "node-types.json");

// tree-sitter CLI 0.20.8 parses #any-of? but its query engine silently
// ignores it (matches everything), so the blocks use an anchored #match?
// alternation instead — equivalent for word-only identifier names (verified:
// every catalog name matches /^[A-Za-z_][A-Za-z0-9_]*$/; the generator fails
// fast below if a future catalog entry violates that).
const NAME_RE = /^[A-Za-z_][A-Za-z0-9_]*$/;

const MARKERS = {
  constants: {
    begin: "; BEGIN BUILTIN CONSTANTS",
    end: "; END BUILTIN CONSTANTS",
  },
  functions: {
    begin: "; BEGIN BUILTIN FUNCTIONS",
    end: "; END BUILTIN FUNCTIONS",
  },
};

function readNameList(file) {
  const names = JSON.parse(fs.readFileSync(file, "utf8"));
  if (!Array.isArray(names) || !names.every((n) => typeof n === "string")) {
    throw new Error(`${path.relative(ROOT, file)} must be a JSON array of strings`);
  }
  // Defensive: catalogs must stay sorted and duplicate-free.
  return [...new Set(names)].sort();
}

// A single anchored regex: multiple #match? predicates would be ANDed, but we
// need OR semantics, so the alternation must live inside one pattern.
function formatMatchPattern(names) {
  for (const name of names) {
    if (!NAME_RE.test(name)) {
      throw new Error(
        `catalog entry "${name}" is not a plain word identifier; the #match? fallback requires /^[A-Za-z_][A-Za-z0-9_]*$/ names`
      );
    }
  }
  return `"^(${names.join("|")})$"`;
}

function constantsBlock(names) {
  return [
    "((identifier) @constant.builtin",
    "  (#match? @constant.builtin",
    `    ${formatMatchPattern(names)}`,
    "  )",
    '  (#set! "priority" 110))',
  ].join("\n");
}

function functionsBlock(names) {
  return [
    "(call_expression",
    "  function: (identifier) @function.builtin",
    "  (#match? @function.builtin",
    `    ${formatMatchPattern(names)}`,
    "  ))",
  ].join("\n");
}

function validateNodeTypes(blockName, nodeTypes) {
  const nodeTypesList = JSON.parse(fs.readFileSync(NODE_TYPES_JSON, "utf8"));
  const known = new Set(nodeTypesList.filter((t) => t.named).map((t) => t.type));
  for (const nodeType of nodeTypes) {
    if (!known.has(nodeType)) {
      console.error(
        `error: ${blockName} block captures node type "${nodeType}", which is not present in src/node-types.json. ` +
          `The grammar likely renamed this node; update scripts/build-highlights.js before regenerating.`
      );
      process.exit(1);
    }
  }
}

// Replaces the content between begin/end markers. If the markers are absent,
// they are inserted at the end of the file (same semantics as upstream's
// replaceBlock).
function replaceBlock(scm, markers, block) {
  const beginIdx = scm.indexOf(markers.begin);
  const endIdx = scm.indexOf(markers.end);
  if (beginIdx === -1 && endIdx === -1) {
    const base = scm.endsWith("\n") ? scm : scm + "\n";
    return `${base}${markers.begin}\n${block}\n${markers.end}\n`;
  }
  if (beginIdx === -1 || endIdx === -1) {
    throw new Error(`unmatched markers: ${markers.begin} / ${markers.end}`);
  }
  if (endIdx < beginIdx) {
    throw new Error(`${markers.end} appears before ${markers.begin}`);
  }
  return (
    scm.slice(0, beginIdx + markers.begin.length) +
    "\n" +
    block +
    "\n" +
    scm.slice(endIdx)
  );
}

function main() {
  const constants = readNameList(CONSTANTS_JSON);
  const functions = readNameList(FUNCTIONS_JSON);

  validateNodeTypes("constants", ["identifier"]);
  validateNodeTypes("functions", ["call_expression", "identifier"]);

  let scm = fs.readFileSync(HIGHLIGHTS_SCM, "utf8");
  scm = replaceBlock(scm, MARKERS.constants, constantsBlock(constants));
  scm = replaceBlock(scm, MARKERS.functions, functionsBlock(functions));

  fs.writeFileSync(HIGHLIGHTS_SCM, scm);
  console.log(
    `build-highlights: ${constants.length} constants, ${functions.length} functions -> ${path.relative(ROOT, HIGHLIGHTS_SCM)}`
  );
}

main();
