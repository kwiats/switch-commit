const START = "<!-- changelog:start -->";
const END = "<!-- changelog:end -->";

export function patchChangelog(html, sectionHtml) {
  const start = html.indexOf(START);
  const end = html.indexOf(END);
  if (start === -1 || end === -1 || end < start) {
    throw new Error(`Missing ${START} / ${END} markers in index.html`);
  }
  const before = html.slice(0, start + START.length);
  const after = html.slice(end);
  return `${before}\n${sectionHtml.trimEnd()}\n${after}`;
}

/**
 * @param {string} html
 * @param {{ versionTag: string, dmgUrl: string, sha256Url: string }} cta
 */
export function patchDownloadCta(html, cta) {
  const required = ["__VERSION_TAG__", "__DMG_URL__", "__SHA256_URL__"];
  for (const token of required) {
    if (!html.includes(token)) {
      throw new Error(`Missing ${token} placeholder in index.html`);
    }
  }
  return html
    .replaceAll("__VERSION_TAG__", cta.versionTag)
    .replaceAll("__DMG_URL__", cta.dmgUrl)
    .replaceAll("__SHA256_URL__", cta.sha256Url);
}

export { START, END };
