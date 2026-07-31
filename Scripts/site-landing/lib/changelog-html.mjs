// scripts/lib/changelog-html.mjs
import { escapeHtml, markdownToHtml } from "./markdown.mjs";

function formatDate(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleDateString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
    timeZone: "UTC",
  });
}

function versionLabel(tagName) {
  return tagName.startsWith("v") ? tagName : `v${tagName}`;
}

/**
 * @param {{ tagName: string, publishedAt?: string, body?: string }[]} releases
 */
export function buildChangelogSection(releases) {
  const entries =
    releases.length === 0
      ? `          <p class="changelog-empty">No releases yet.</p>`
      : releases
          .map((r) => {
            const ver = escapeHtml(versionLabel(r.tagName));
            const date = escapeHtml(formatDate(r.publishedAt));
            const meta = date ? `// ${ver} · ${date}` : `// ${ver}`;
            const bodyHtml = markdownToHtml(r.body || "");
            const body =
              bodyHtml ||
              `<p class="changelog-empty">No release notes.</p>`;
            return `          <article class="changelog-entry">
            <div class="changelog-meta">${meta}</div>
            <div class="changelog-body">${body}</div>
          </article>`;
          })
          .join("\n");

  return `    <section class="changelog" id="changelog">
      <div class="changelog-inner">
        <h2>Changelog</h2>
        <div class="changelog-entries">
${entries}
        </div>
      </div>
    </section>`;
}
