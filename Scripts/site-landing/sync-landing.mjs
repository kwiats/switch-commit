#!/usr/bin/env node
import { readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { buildChangelogSection } from "./lib/changelog-html.mjs";
import { parseChangelog } from "./lib/parse-changelog.mjs";
import { patchChangelog, patchDownloadCta } from "./lib/patch-index.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, "../..");
const INDEX = join(REPO_ROOT, "site/index.html");
const TEMPLATE = join(__dirname, "index.template.html");
const CHANGELOG = join(REPO_ROOT, "CHANGELOG.md");
const LIMIT = 5;
const dryRun = process.argv.includes("--dry-run");

function die(msg, code = 1) {
  console.error(msg);
  process.exit(code);
}

function ghJson(args) {
  const r = spawnSync("gh", args, { encoding: "utf8" });
  if (r.status !== 0) {
    die(`gh ${args.join(" ")} failed:\n${r.stderr || r.stdout}`);
  }
  try {
    return JSON.parse(r.stdout);
  } catch (e) {
    die(`gh ${args.join(" ")} returned invalid JSON: ${e.message}`);
  }
}

function resolveRepo() {
  if (process.env.GITHUB_REPOSITORY) return process.env.GITHUB_REPOSITORY;
  const data = ghJson(["repo", "view", "--json", "nameWithOwner"]);
  return data.nameWithOwner;
}

function fetchReleases(repo) {
  const all = ghJson(["api", `repos/${repo}/releases?per_page=15`]);
  if (!Array.isArray(all)) {
    die(
      `Unexpected API response from repos/${repo}/releases: expected array, got ${typeof all}`
    );
  }
  return all
    .filter((r) => !r.draft && !r.prerelease)
    .filter((r) =>
      (r.assets || []).some((a) => /^SwitchCommit-v.+-macOS\.dmg$/.test(a.name || ""))
    );
}

function resolveLatestDownloadCta(latest) {
  if (!latest) {
    throw new Error("No usable latest release to build download CTA");
  }
  const assets = Array.isArray(latest.assets) ? latest.assets : [];
  const dmg = assets.find((a) => /^SwitchCommit-v.+-macOS\.dmg$/.test(a.name || ""));
  const sha = assets.find((a) =>
    /^SwitchCommit-v.+-macOS\.dmg\.sha256$/.test(a.name || "")
  );
  if (!dmg?.browser_download_url) {
    throw new Error(`Latest release ${latest.tag_name} is missing SwitchCommit DMG asset`);
  }
  if (!sha?.browser_download_url) {
    throw new Error(
      `Latest release ${latest.tag_name} is missing SwitchCommit DMG checksum asset`
    );
  }
  const tag = latest.tag_name.startsWith("v")
    ? latest.tag_name
    : `v${latest.tag_name}`;
  return {
    versionTag: tag,
    dmgUrl: dmg.browser_download_url,
    sha256Url: sha.browser_download_url,
  };
}

function loadChangelogReleases() {
  let markdown;
  try {
    markdown = readFileSync(CHANGELOG, "utf8");
  } catch (e) {
    die(`Cannot read ${CHANGELOG}: ${e.message}`);
  }
  return parseChangelog(markdown)
    .filter((entry) => entry.version !== "Unreleased")
    .slice(0, LIMIT)
    .map((entry) => ({
      tagName: `v${entry.version}`,
      publishedAt: entry.date ? `${entry.date}T12:00:00Z` : undefined,
      body: entry.body || "",
    }));
}

const repo = resolveRepo();
const releases = fetchReleases(repo);
const changelogReleases = loadChangelogReleases();
const section = buildChangelogSection(changelogReleases);
const cta = resolveLatestDownloadCta(releases[0]);

if (dryRun) {
  process.stdout.write(section + "\n");
  console.error(JSON.stringify(cta, null, 2));
  process.exit(0);
}

let html;
try {
  html = readFileSync(TEMPLATE, "utf8");
} catch (e) {
  die(`Cannot read ${TEMPLATE}: ${e.message}`);
}

let next;
try {
  next = patchChangelog(html, section);
  next = patchDownloadCta(next, cta);
} catch (e) {
  die(e.message);
}

const tempPath = `${INDEX}.tmp`;
try {
  writeFileSync(tempPath, next);
  renameSync(tempPath, INDEX);
} catch (e) {
  die(`Cannot write ${INDEX}: ${e.message}`);
}

console.log(
  `Updated site/index.html changelog (${changelogReleases.length}) from CHANGELOG.md and CTA ${cta.versionTag} from ${repo}.`
);
