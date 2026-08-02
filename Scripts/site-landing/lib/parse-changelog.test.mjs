import { test } from "node:test";
import assert from "node:assert/strict";
import {
  findChangelogEntry,
  formatReleaseNotes,
  parseChangelog,
} from "./parse-changelog.mjs";

const SAMPLE = `# Changelog

## [Unreleased]

### Added

- Pending work

## [0.3.8] - 2026-08-02

### Highlights

- First item
- Second item

### Fixes

- A fix

## [0.2.0]

### Planned

- Rename
`;

test("parses Keep a Changelog entries newest first", () => {
  const entries = parseChangelog(SAMPLE);
  assert.equal(entries.length, 3);
  assert.deepEqual(
    entries.map((e) => ({ version: e.version, date: e.date })),
    [
      { version: "Unreleased", date: null },
      { version: "0.3.8", date: "2026-08-02" },
      { version: "0.2.0", date: null },
    ]
  );
  assert.match(entries[1].body, /### Highlights/);
  assert.match(entries[1].body, /First item/);
  assert.match(entries[2].body, /### Planned/);
});

test("findChangelogEntry skips Unreleased and matches version", () => {
  const entry = findChangelogEntry(SAMPLE, "0.3.8");
  assert.ok(entry);
  assert.equal(entry.version, "0.3.8");
  assert.equal(findChangelogEntry(SAMPLE, "v0.3.8")?.version, "0.3.8");
  assert.equal(findChangelogEntry(SAMPLE, "9.9.9"), null);
  assert.equal(findChangelogEntry(SAMPLE, "Unreleased"), null);
});

test("formatReleaseNotes builds Sparkle/GitHub markdown", () => {
  const md = formatReleaseNotes({
    version: "0.3.8",
    body: "### Highlights\n\n- Item\n",
  });
  assert.equal(md, "# Switch Commit v0.3.8\n\n### Highlights\n\n- Item\n");
});

test("returns empty array for empty input", () => {
  assert.deepEqual(parseChangelog(""), []);
  assert.deepEqual(parseChangelog("   "), []);
});
