"use strict";

// Check the size of a pull request.
//
// Only the diff that actually requires judgement counts against the limit.
// Paths whose line count says nothing about review effort (research notes,
// images, generated files) are excluded through .github/pr-size-ignore,
// using .gitignore syntax.

const fs = require("fs");
const path = require("path");

const MAX_CHANGED_LINES = 300;
const RATIONALE =
  "https://smartbear.com/learn/code-review/best-practices-for-peer-code-review/";

const CONFIG_DIR = path.resolve(__dirname, "..");
const IGNORE_FILE = "pr-size-ignore";

// --- .gitignore style pattern matching ------------------------------------

// Convert one segment of a pattern (a single / delimited level) to a regexp.
function segmentToRegExp(segment) {
  let out = "";
  for (let i = 0; i < segment.length; i++) {
    const char = segment[i];
    if (char === "*") {
      out += "[^/]*";
    } else if (char === "?") {
      out += "[^/]";
    } else if (char === "[") {
      const end = segment.indexOf("]", i + 1);
      if (end === -1) {
        out += "\\[";
      } else {
        out += "[" + segment.slice(i + 1, end).replace(/^!/, "^") + "]";
        i = end;
      }
    } else {
      out += char.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
  }
  return out;
}

function compilePattern(rawPattern) {
  let pattern = rawPattern;

  const negated = pattern.startsWith("!");
  if (negated) pattern = pattern.slice(1);
  if (pattern.startsWith("\\#") || pattern.startsWith("\\!")) {
    pattern = pattern.slice(1);
  }

  // A trailing / means the pattern matches directories only
  const dirOnly = pattern.endsWith("/");
  if (dirOnly) pattern = pattern.slice(0, -1);

  // A pattern with a / at the start or in the middle is relative to the
  // repository root. A pattern without any / matches at any level.
  let anchored = false;
  if (pattern.startsWith("/")) {
    anchored = true;
    pattern = pattern.slice(1);
  } else if (pattern.includes("/")) {
    anchored = true;
  }

  const segments = pattern.split("/");
  let body = "";
  segments.forEach((segment, index) => {
    const isLast = index === segments.length - 1;
    if (segment === "**") {
      body += isLast ? ".*" : "(?:[^/]+/)*";
    } else {
      body += segmentToRegExp(segment) + (isLast ? "" : "/");
    }
  });

  const prefix = anchored ? "^" : "^(?:.*/)?";
  // A pattern that matched a directory also matches everything under it
  const suffix = dirOnly ? "/.*$" : "(?:/.*)?$";

  return { negated, regexp: new RegExp(prefix + body + suffix) };
}

function parsePatternFile(filename) {
  const filePath = path.join(CONFIG_DIR, filename);
  if (!fs.existsSync(filePath)) return [];

  return fs
    .readFileSync(filePath, "utf8")
    .split(/\r?\n/)
    .map(line => line.trimEnd())
    .filter(line => line.length > 0 && !line.startsWith("#"))
    .map(compilePattern);
}

// As in .gitignore, the last matching pattern decides the outcome.
function isMatch(rules, filename) {
  let matched = false;
  for (const rule of rules) {
    if (rule.regexp.test(filename)) matched = !rule.negated;
  }
  return matched;
}

// --- main -----------------------------------------------------------------

function summarize(bucket) {
  const additions = bucket.reduce((total, file) => total + file.additions, 0);
  const deletions = bucket.reduce((total, file) => total + file.deletions, 0);
  return { files: bucket.length, additions, deletions, total: additions + deletions };
}

async function run({ github, context, core }) {
  const pr = context.payload.pull_request;
  if (!pr) {
    core.setFailed("Missing pull_request payload.");
    return;
  }

  const ignoreRules = parsePatternFile(IGNORE_FILE);

  const files = await github.paginate(github.rest.pulls.listFiles, {
    owner: context.repo.owner,
    repo: context.repo.repo,
    pull_number: pr.number,
    per_page: 100
  });

  const counted = summarize(files.filter(file => !isMatch(ignoreRules, file.filename)));
  const excluded = summarize(files.filter(file => isMatch(ignoreRules, file.filename)));

  core.info(`counted: +${counted.additions} -${counted.deletions} (${counted.files} files)`);
  core.info(`excluded: +${excluded.additions} -${excluded.deletions} (${excluded.files} files)`);

  const row = (label, stat, limit) => [
    label,
    stat.files.toString(),
    stat.additions.toString(),
    stat.deletions.toString(),
    stat.total.toString(),
    limit
  ];

  await core.summary
    .addHeading("PR size check")
    .addTable([
      [
        { data: "Category", header: true },
        { data: "Files", header: true },
        { data: "Additions", header: true },
        { data: "Deletions", header: true },
        { data: "Total", header: true },
        { data: "Limit", header: true }
      ],
      row("Counted", counted, MAX_CHANGED_LINES.toString()),
      row("Excluded", excluded, "-")
    ])
    .addRaw(`\nExclusions are configured in .github/${IGNORE_FILE}\n`)
    .addRaw(`\nRationale for the ${MAX_CHANGED_LINES}-line limit: ${RATIONALE}\n`)
    .write();

  if (counted.total > MAX_CHANGED_LINES) {
    core.setFailed(
      `PR size ${counted.total} > ${MAX_CHANGED_LINES} changed lines. ` +
        `Split the PR into smaller, reviewable chunks. Rationale: ${RATIONALE}`
    );
  }
}

module.exports = run;
module.exports.compilePattern = compilePattern;
module.exports.isMatch = isMatch;
module.exports.parsePatternFile = parsePatternFile;
