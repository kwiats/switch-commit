#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  findChangelogEntry,
  formatReleaseNotes,
} from "./lib/parse-changelog.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, "../..");
const CHANGELOG = join(REPO_ROOT, "CHANGELOG.md");

const version = process.argv[2];
if (!version || !/^[0-9]+\.[0-9]+\.[0-9]+$/.test(version)) {
  console.error(
    "usage: node Scripts/site-landing/extract-release-notes.mjs <X.Y.Z>"
  );
  process.exit(1);
}

let markdown;
try {
  markdown = readFileSync(CHANGELOG, "utf8");
} catch (e) {
  console.error(`error: missing changelog ${CHANGELOG}: ${e.message}`);
  process.exit(1);
}

const entry = findChangelogEntry(markdown, version);
if (!entry) {
  console.error(`error: CHANGELOG.md has no section for ${version}`);
  console.error(
    `error: add ## [${version}] - YYYY-MM-DD to CHANGELOG.md before tagging v${version}`
  );
  process.exit(1);
}

process.stdout.write(formatReleaseNotes(entry));
