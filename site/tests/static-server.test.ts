import assert from "node:assert/strict";
import { afterAll, beforeAll, test } from "bun:test";
import { mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createStaticHandler, parsePort } from "../scripts/serve.ts";
import { distRoot, siteRoot } from "../scripts/build.ts";

let directory: string;
let handle: Awaited<ReturnType<typeof createStaticHandler>>;

beforeAll(async () => {
  directory = await mkdtemp(join(tmpdir(), "cc-static-server-test-"));
  const publicRoot = join(directory, "public");
  await mkdir(publicRoot);
  await writeFile(join(publicRoot, "index.html"), "<!DOCTYPE html><p>cc:</p>");
  await writeFile(join(publicRoot, "client.js"), "console.log('cc:');");
  await writeFile(join(publicRoot, "style.css"), "body{color:white}");
  await writeFile(join(publicRoot, "mark.svg"), '<svg xmlns="http://www.w3.org/2000/svg"></svg>');
  await writeFile(join(publicRoot, "font.woff2"), new Uint8Array([1, 2, 3]));
  await writeFile(join(publicRoot, "space name.txt"), "test");
  await writeFile(join(directory, "private.txt"), "must not be served");
  await symlink(join(directory, "private.txt"), join(publicRoot, "outside.txt"));
  handle = await createStaticHandler(publicRoot);
});

afterAll(async () => { await rm(directory, { recursive: true, force: true }); });

test("serves built files with MIME types, query strings, and HEAD semantics", async () => {
  for (const [path, mime] of [["/", "text/html"], ["/client.js", "text/javascript"], ["/style.css", "text/css"], ["/mark.svg?v=1", "image/svg+xml"], ["/font.woff2", "font/woff2"], ["/space%20name.txt", "text/plain"]]) {
    const response = await handle(new Request(`http://localhost${path}`));
    assert.equal(response.status, 200);
    assert.ok(response.headers.get("content-type")?.startsWith(mime!));
    assert.equal(response.headers.get("x-content-type-options"), "nosniff");
    const length = (await response.arrayBuffer()).byteLength;
    assert.equal(response.headers.get("content-length"), String(length));
    const head = await handle(new Request(`http://localhost${path}`, { method: "HEAD" }));
    assert.equal(head.status, 200);
    assert.equal(head.headers.get("content-length"), String(length));
    assert.equal(await head.text(), "");
  }
});

test("returns 404 for missing files and rejects unsafe paths, symlink escapes, and writes", async () => {
  assert.equal((await handle(new Request("http://localhost/missing"))).status, 404);
  assert.equal((await handle(new Request("http://localhost/%zz"))).status, 400);
  for (const path of ["/%2e%2e%2fprivate.txt", "/%2e%2e%5cprivate.txt", "/%00", "/outside.txt"]) {
    const response = await handle(new Request(`http://localhost${path}`));
    assert.equal(response.status, 403, path);
    assert.ok(!(await response.text()).includes("must not be served"));
  }
  const post = await handle(new Request("http://localhost/", { method: "POST" }));
  assert.equal(post.status, 405);
  assert.equal(post.headers.get("allow"), "GET, HEAD");
});

test("uses a validated explicit port with a localhost default", () => {
  assert.equal(parsePort([]), 3000);
  assert.equal(parsePort(["--port", "4318"]), 4318);
  assert.equal(parsePort(["--port=4318"]), 4318);
  for (const args of [["--port", "0"], ["--port", "65536"], ["--port", "-1"], ["--port", "1.5"], ["--port", "abc"], ["--host", "0.0.0.0"]]) {
    assert.throws(() => parsePort(args));
  }
});

test("copies every public/cc asset byte for byte", async () => {
  const publicRoot = join(siteRoot, "public/cc");
  async function inspect(directory: string): Promise<void> {
    for (const entry of await readdir(join(publicRoot, directory), { withFileTypes: true })) {
      const relative = join(directory, entry.name);
      if (entry.isDirectory()) { await inspect(relative); continue; }
      assert.ok(entry.isFile(), `Unexpected public asset type: ${relative}`);
      const source = await readFile(join(publicRoot, relative));
      const built = await readFile(join(distRoot, "cc", relative));
      assert.equal(createHash("sha256").update(built).digest("hex"), createHash("sha256").update(source).digest("hex"), relative);
    }
  }
  await inspect("");
});
