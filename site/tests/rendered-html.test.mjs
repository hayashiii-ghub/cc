import assert from "node:assert/strict";
import test from "node:test";

async function render(pathname = "/") {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request(new URL(pathname, "http://localhost/"), {
      headers: { accept: "text/html" },
    }),
    { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } },
    { waitUntil() {}, passThroughOnException() {} },
  );
}

function withoutBreakHints(html) {
  return html
    .replace(/<wbr\s*\/?\s*>/g, "")
    .replace(/<\/?span\b[^>]*>/g, "");
}

test("renders the standalone cc: site at the root", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  const text = withoutBreakHints(html);

  assert.match(html, /<html lang="en">/);
  assert.match(html, /<title>cc:<\/title>/);
  assert.match(text, /You and your agent/);
  assert.match(text, /Gather files, links, and long notes/);
  assert.match(text, /Give your agent the materials it needs/);
  assert.match(text, /Receive the work on your shelf/);
  assert.match(text, /Right where you reach for it/);
  assert.match(text, /Menu Bar stays the default/);
  assert.match(text, /optional Notch shelf/);
  assert.match(text, /Your shelf, stored on this Mac/);
  assert.match(text, /A few things to know/);
  assert.doesNotMatch(text, /Questions, answered honestly/);
  assert.match(html, /Light preview/);
  assert.match(text, /Can I change the shortcuts/);
  assert.match(text, /Use Details to choose/);
  assert.match(text, /Settings → Open Items/);
  assert.match(text, /macOS defaults stay unchanged/);
  assert.match(text, /Option \+ Shift \+ Tab/);
  assert.doesNotMatch(html, /<video\b|-poster\.webp/);
  assert.doesNotMatch(html, /aria-label="(?:Pause|Play) /);
  assert.match(html, /cc-mark\.svg/);
  assert.match(html, /property="og:type" content="website"/);
  assert.match(html, /property="og:url" content="https:\/\/cc\.hayashiii-gpt\.chatgpt\.site\/"/);
  assert.match(html, /property="og:image" content="https:\/\/cc\.hayashiii-gpt\.chatgpt\.site\/cc\/cc-og\.png\?v=0\.4\.4"/);
  assert.match(html, /property="og:image:width" content="1200"/);
  assert.match(html, /property="og:image:height" content="630"/);
  assert.match(html, /name="twitter:image" content="https:\/\/cc\.hayashiii-gpt\.chatgpt\.site\/cc\/cc-og\.png\?v=0\.4\.4"/);
  assert.match(html, /name="twitter:image:alt" content="cc:"/);
  assert.match(html, /rel="icon" href="https:\/\/cc\.hayashiii-gpt\.chatgpt\.site\/cc\/cc-favicon\.svg" type="image\/svg\+xml"/);
  assert.match(html, /github\.com\/hayashiii-ghub\/cc/);
  assert.match(html, /github\.com\/hayashiii-ghub\/cc\/releases/);
  assert.match(html, /releases\/latest\/download\/cc-macos\.dmg/);
  assert.match(text, /Open source/);
  assert.match(text, /v0\.4\.4 · macOS 26\+ · Apple Silicon &amp; Intel/);
  assert.match(text, /cc: is not yet notarized by Apple/);
  assert.match(text, /Privacy &amp; Security/);
  assert.doesNotMatch(html, /v1\.1\.4|Chrome Web Store|CodexIsland/);
  assert.match(text, /managed copies of files and folders in its local storage/);
  assert.match(text, /kept until you remove them/);
  assert.match(text, /ask Codex or Claude Code to read the items you need/);
  assert.doesNotMatch(text, /On Screen|remain references|in memory|temporary copies are cleared/);
});
