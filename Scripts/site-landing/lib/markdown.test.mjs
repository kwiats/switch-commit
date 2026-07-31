// scripts/lib/markdown.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { markdownToHtml } from "./markdown.mjs";

test("renders headings, lists, links, code, emphasis", () => {
  const html = markdownToHtml(
    "## Highlights\n\n- One **bold** and `code`\n- [link](https://example.com)\n\n*italic*"
  );
  assert.match(html, /<h2>Highlights<\/h2>/);
  assert.match(html, /<ul>/);
  assert.match(html, /<strong>bold<\/strong>/);
  assert.match(html, /<code>code<\/code>/);
  assert.match(html, /<a href="https:\/\/example.com">link<\/a>/);
  assert.match(html, /<em>italic<\/em>/);
});

test("escapes raw HTML / script from notes", () => {
  const html = markdownToHtml('Hello <script>alert(1)</script> <b>x</b>');
  assert.equal(html.includes("<script>"), false);
  assert.equal(html.includes("<b>"), false);
  assert.match(html, /&lt;script&gt;/);
});

test("empty input yields empty string", () => {
  assert.equal(markdownToHtml(""), "");
  assert.equal(markdownToHtml("   "), "");
});
