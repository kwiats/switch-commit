#!/usr/bin/env node
/**
 * Upload a Switch Commit DMG to Polar and attach it to a downloadables benefit.
 *
 * Required env:
 *   POLAR_ACCESS_TOKEN
 *   POLAR_ORGANIZATION_ID
 *   POLAR_BENEFIT_ID
 *
 * Usage:
 *   node Scripts/polar-sync-dmg.mjs --dmg path/to/SwitchCommit-vX.Y.Z-macOS.dmg
 */

import { createHash } from "node:crypto";
import { readFileSync, statSync } from "node:fs";
import { basename, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const API_BASE = "https://api.polar.sh/v1";

/**
 * @param {object} opts
 * @param {string} opts.token
 * @param {string} opts.organizationId
 * @param {string} opts.benefitId
 * @param {string} opts.dmgPath
 * @param {typeof fetch} [opts.fetchImpl]
 * @param {string} [opts.apiBase]
 * @param {string} [opts.version]
 */
export async function syncDmgToPolar({
  token,
  organizationId,
  benefitId,
  dmgPath,
  fetchImpl = fetch,
  apiBase = API_BASE,
  version = null,
}) {
  if (!token) throw new Error("POLAR_ACCESS_TOKEN is required");
  if (!organizationId) throw new Error("POLAR_ORGANIZATION_ID is required");
  if (!benefitId) throw new Error("POLAR_BENEFIT_ID is required");
  if (!dmgPath) throw new Error("--dmg path is required");

  const name = basename(dmgPath);
  const size = statSync(dmgPath).size;
  const bytes = readFileSync(dmgPath);
  const checksumSha256Base64 = createHash("sha256").update(bytes).digest("base64");
  const mimeType = "application/x-apple-diskimage";

  const authHeaders = {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
    Accept: "application/json",
  };

  const createBody = {
    organization_id: organizationId,
    name,
    mime_type: mimeType,
    size,
    checksum_sha256_base64: checksumSha256Base64,
    service: "downloadable",
    version: version,
    upload: {
      parts: [
        {
          number: 1,
          chunk_start: 0,
          chunk_end: size - 1,
          checksum_sha256_base64: checksumSha256Base64,
        },
      ],
    },
  };

  const createRes = await fetchImpl(`${apiBase}/files/`, {
    method: "POST",
    headers: authHeaders,
    body: JSON.stringify(createBody),
  });
  if (!createRes.ok) {
    throw new Error(
      `Polar create file failed (${createRes.status}): ${await createRes.text()}`
    );
  }
  const created = await createRes.json();
  const part = created?.upload?.parts?.[0];
  if (!part?.url) {
    throw new Error("Polar create file response missing upload.parts[0].url");
  }

  const putHeaders = { ...(part.headers || {}) };
  const putRes = await fetchImpl(part.url, {
    method: "PUT",
    headers: putHeaders,
    body: bytes,
  });
  if (!putRes.ok) {
    throw new Error(
      `Polar S3 upload failed (${putRes.status}): ${await putRes.text()}`
    );
  }
  const etag = (putRes.headers.get("etag") || putRes.headers.get("ETag") || "")
    .replaceAll('"', "");
  if (!etag) {
    throw new Error("Polar S3 upload response missing ETag");
  }

  const completeRes = await fetchImpl(`${apiBase}/files/${created.id}/uploaded`, {
    method: "POST",
    headers: authHeaders,
    body: JSON.stringify({
      id: created.upload.id,
      path: created.upload.path,
      parts: [
        {
          number: 1,
          checksum_etag: etag,
          checksum_sha256_base64: checksumSha256Base64,
        },
      ],
    }),
  });
  if (!completeRes.ok) {
    throw new Error(
      `Polar complete upload failed (${completeRes.status}): ${await completeRes.text()}`
    );
  }

  const benefitRes = await fetchImpl(`${apiBase}/benefits/${benefitId}`, {
    method: "GET",
    headers: authHeaders,
  });
  if (!benefitRes.ok) {
    throw new Error(
      `Polar get benefit failed (${benefitRes.status}): ${await benefitRes.text()}`
    );
  }
  const benefit = await benefitRes.json();
  if (benefit.type !== "downloadables") {
    throw new Error(`Benefit ${benefitId} is type=${benefit.type}, expected downloadables`);
  }

  const previousFiles = Array.isArray(benefit.properties?.files)
    ? benefit.properties.files
    : [];
  const archived = { ...(benefit.properties?.archived || {}) };
  for (const oldId of previousFiles) {
    if (oldId !== created.id) archived[oldId] = true;
  }

  const nextFiles = [created.id, ...previousFiles.filter((id) => id !== created.id)];

  const patchRes = await fetchImpl(`${apiBase}/benefits/${benefitId}`, {
    method: "PATCH",
    headers: authHeaders,
    body: JSON.stringify({
      type: "downloadables",
      properties: {
        files: nextFiles,
        archived,
      },
    }),
  });
  if (!patchRes.ok) {
    throw new Error(
      `Polar update benefit failed (${patchRes.status}): ${await patchRes.text()}`
    );
  }

  return {
    fileId: created.id,
    name,
    benefitId,
    files: nextFiles,
  };
}

function parseArgs(argv) {
  let dmgPath = null;
  let version = null;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--dmg") {
      dmgPath = argv[++i];
    } else if (argv[i] === "--version") {
      version = argv[++i];
    }
  }
  return { dmgPath, version };
}

async function main() {
  const { dmgPath, version } = parseArgs(process.argv.slice(2));
  const result = await syncDmgToPolar({
    token: process.env.POLAR_ACCESS_TOKEN,
    organizationId: process.env.POLAR_ORGANIZATION_ID,
    benefitId: process.env.POLAR_BENEFIT_ID,
    dmgPath,
    version,
  });
  console.log(
    `Synced ${result.name} → Polar file ${result.fileId} on benefit ${result.benefitId}`
  );
}

const isMain =
  Boolean(process.argv[1]) &&
  import.meta.url === pathToFileURL(resolve(process.argv[1])).href;

if (isMain) {
  main().catch((err) => {
    console.error(err.message || err);
    process.exit(1);
  });
}
