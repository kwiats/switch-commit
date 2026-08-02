import { test } from "node:test";
import assert from "node:assert/strict";
import { writeFileSync, mkdtempSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { syncDmgToPolar } from "./polar-sync-dmg.mjs";

function makeDmg() {
  const dir = mkdtempSync(join(tmpdir(), "polar-dmg-"));
  const path = join(dir, "SwitchCommit-v9.9.9-macOS.dmg");
  writeFileSync(path, Buffer.from("fake-dmg-bytes"));
  return path;
}

test("requires env and dmg path", async () => {
  await assert.rejects(
    () =>
      syncDmgToPolar({
        token: "",
        organizationId: "org",
        benefitId: "ben",
        dmgPath: makeDmg(),
        fetchImpl: async () => {
          throw new Error("should not fetch");
        },
      }),
    /POLAR_ACCESS_TOKEN/
  );
});

test("uploads DMG and updates downloadables benefit", async () => {
  const dmgPath = makeDmg();
  const calls = [];

  const fetchImpl = async (url, init = {}) => {
    calls.push({ url, method: init.method || "GET", body: init.body });
    const method = init.method || "GET";

    if (url.endsWith("/files/") && method === "POST") {
      return {
        ok: true,
        status: 201,
        async json() {
          return {
            id: "file-new",
            upload: {
              id: "upload-1",
              path: "org/file-new",
              parts: [
                {
                  number: 1,
                  url: "https://s3.example/put",
                  headers: { "Content-Type": "application/x-apple-diskimage" },
                },
              ],
            },
          };
        },
        async text() {
          return "";
        },
        headers: { get() { return null; } },
      };
    }

    if (url === "https://s3.example/put" && method === "PUT") {
      return {
        ok: true,
        status: 200,
        async text() {
          return "";
        },
        headers: {
          get(name) {
            return name.toLowerCase() === "etag" ? '"etag-abc"' : null;
          },
        },
      };
    }

    if (url.endsWith("/files/file-new/uploaded") && method === "POST") {
      return {
        ok: true,
        status: 200,
        async json() {
          return { id: "file-new", is_uploaded: true };
        },
        async text() {
          return "";
        },
        headers: { get() { return null; } },
      };
    }

    if (url.endsWith("/benefits/ben-1") && method === "GET") {
      return {
        ok: true,
        status: 200,
        async json() {
          return {
            id: "ben-1",
            type: "downloadables",
            properties: {
              files: ["file-old"],
              archived: {},
            },
          };
        },
        async text() {
          return "";
        },
        headers: { get() { return null; } },
      };
    }

    if (url.endsWith("/benefits/ben-1") && method === "PATCH") {
      const body = JSON.parse(init.body);
      assert.equal(body.type, "downloadables");
      assert.deepEqual(body.properties.files, ["file-new", "file-old"]);
      assert.equal(body.properties.archived["file-old"], true);
      return {
        ok: true,
        status: 200,
        async json() {
          return body;
        },
        async text() {
          return "";
        },
        headers: { get() { return null; } },
      };
    }

    throw new Error(`Unexpected fetch ${method} ${url}`);
  };

  const result = await syncDmgToPolar({
    token: "tok",
    organizationId: "org-1",
    benefitId: "ben-1",
    dmgPath,
    fetchImpl,
    apiBase: "https://api.polar.test/v1",
    version: "9.9.9",
  });

  assert.equal(result.fileId, "file-new");
  assert.equal(result.name, "SwitchCommit-v9.9.9-macOS.dmg");
  assert.equal(calls.length, 5);
});
