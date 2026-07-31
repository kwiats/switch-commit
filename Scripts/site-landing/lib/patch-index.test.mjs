import { test } from "node:test";
import assert from "node:assert/strict";
import { patchChangelog, patchDownloadCta } from "./patch-index.mjs";

const START = "<!-- changelog:start -->";
const END = "<!-- changelog:end -->";

test("replaces content between markers", () => {
  const input = `<html>${START}\nold\n${END}\n<footer></footer>`;
  const out = patchChangelog(input, "<section>NEW</section>");
  assert.match(out, new RegExp(`${START}\\n<section>NEW</section>\\n${END}`));
  assert.equal(out.includes("old"), false);
  assert.match(out, /<footer>/);
});

test("throws when markers missing", () => {
  assert.throws(() => patchChangelog("<html></html>", "x"), /changelog:start/);
});

test("patches download CTA placeholders", () => {
  const input =
    '<em>__VERSION_TAG__</em><a href="__DMG_URL__">Pobierz __VERSION_TAG__</a><a href="__SHA256_URL__">sha</a>';
  const out = patchDownloadCta(input, {
    versionTag: "v0.3.0",
    dmgUrl: "https://example.test/app.dmg",
    sha256Url: "https://example.test/app.dmg.sha256",
  });
  assert.equal(
    out,
    '<em>v0.3.0</em><a href="https://example.test/app.dmg">Pobierz v0.3.0</a><a href="https://example.test/app.dmg.sha256">sha</a>'
  );
});

test("throws when CTA placeholders missing", () => {
  assert.throws(
    () =>
      patchDownloadCta("<html></html>", {
        versionTag: "v1.0.0",
        dmgUrl: "https://example.test/a.dmg",
        sha256Url: "https://example.test/a.dmg.sha256",
      }),
    /__VERSION_TAG__/
  );
});
