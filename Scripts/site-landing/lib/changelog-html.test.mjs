// scripts/lib/changelog-html.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { buildChangelogSection } from "./changelog-html.mjs";

test("builds install-like section for releases", () => {
  const html = buildChangelogSection([
    {
      tagName: "v0.2.5",
      publishedAt: "2026-07-30T16:37:09Z",
      body: "## Highlights\n\n- DMG installer\n",
    },
    {
      tagName: "v0.2.4",
      publishedAt: "2026-07-30T16:17:15Z",
      body: "",
    },
  ]);
  assert.match(html, /class="changelog"/);
  assert.match(html, /<h2>Changelog<\/h2>/);
  assert.match(html, /\/\/ v0\.2\.5/);
  assert.match(html, /DMG installer/);
  assert.match(html, /\/\/ v0\.2\.4/);
  assert.match(html, /No release notes\./);
});

test("returns empty section shell when no releases", () => {
  const html = buildChangelogSection([]);
  assert.match(html, /class="changelog"/);
  assert.match(html, /No releases yet\./);
});

test("adds v prefix to tag without v", () => {
  const html = buildChangelogSection([
    { tagName: "0.2.5", publishedAt: "2026-07-30T16:37:09Z", body: "" },
  ]);
  assert.match(html, /\/\/ v0\.2\.5/);
});

test("omits date from meta when publishedAt is missing", () => {
  const html = buildChangelogSection([{ tagName: "v1.0.0", body: "" }]);
  assert.match(html, /\/\/ v1\.0\.0/);
  assert.doesNotMatch(html, /\/\/ v1\.0\.0 ·/);
});

test("escapes malicious tagName in meta line", () => {
  const html = buildChangelogSection([
    { tagName: 'v1"><script>', publishedAt: "2026-07-30T16:37:09Z", body: "" },
  ]);
  assert.equal(html.includes("<script>"), false);
  assert.match(html, /&lt;script&gt;/);
});

test("includes structural classes for a normal release", () => {
  const html = buildChangelogSection([
    {
      tagName: "v0.2.5",
      publishedAt: "2026-07-30T16:37:09Z",
      body: "Notes",
    },
  ]);
  assert.match(html, /class="changelog-entry"/);
  assert.match(html, /class="changelog-meta"/);
  assert.match(html, /class="changelog-body"/);
});
