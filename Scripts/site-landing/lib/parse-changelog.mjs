/**
 * Parse a Keep a Changelog / semver-friendly CHANGELOG.md.
 *
 * Expects version headings like:
 *   ## [1.2.3] - 2026-08-02
 *   ## [1.2.3]
 *   ## [Unreleased]
 *
 * @param {string} markdown
 * @returns {{ version: string, date: string | null, body: string }[]}
 */
export function parseChangelog(markdown) {
  if (!markdown || !markdown.trim()) return [];

  const text = markdown.replace(/\r\n/g, "\n");
  const headingRe = /^## \[([^\]]+)\](?:\s+-\s+(\d{4}-\d{2}-\d{2}))?\s*$/gm;
  const matches = [...text.matchAll(headingRe)];
  if (matches.length === 0) return [];

  const entries = [];
  for (let i = 0; i < matches.length; i++) {
    const match = matches[i];
    const version = match[1].trim();
    const date = match[2] || null;
    const start = match.index + match[0].length;
    const end = i + 1 < matches.length ? matches[i + 1].index : text.length;
    const body = text.slice(start, end).replace(/^\n+/, "").replace(/\s+$/, "");
    entries.push({ version, date, body });
  }
  return entries;
}

/**
 * @param {{ version: string, body: string }} entry
 * @returns {string}
 */
export function formatReleaseNotes(entry) {
  const body = (entry.body || "").trim();
  return body
    ? `# Switch Commit v${entry.version}\n\n${body}\n`
    : `# Switch Commit v${entry.version}\n`;
}

/**
 * @param {string} markdown
 * @param {string} version  Semver without leading v
 * @returns {{ version: string, date: string | null, body: string } | null}
 */
export function findChangelogEntry(markdown, version) {
  const normalized = version.startsWith("v") ? version.slice(1) : version;
  return (
    parseChangelog(markdown).find(
      (entry) =>
        entry.version !== "Unreleased" && entry.version === normalized
    ) || null
  );
}
