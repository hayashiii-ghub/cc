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
  assert.match(html, /<title>cc: — A copy for what’s next.<\/title>/);
  assert.match(text, /A copy for/);
  assert.match(text, /Ready for your next app or agent/);
  assert.match(text, /From Finder to your next step/);
  assert.match(text, /A little shared space for the work/);
  assert.match(text, /Right where you reach for it/);
  assert.match(text, /Menu Bar stays the default/);
  assert.match(text, /optional Notch shelf/);
  assert.match(text, /Your shelf. On your Mac/);
  assert.match(text, /A few things to know/);
  assert.doesNotMatch(text, /Questions, answered honestly/);
  assert.doesNotMatch(html, /context-workflow\.webp/);
  assert.doesNotMatch(html, /context-(?:hero|capture|hold|place)\.webp/);
  assert.match(html, /Light preview/);
  assert.match(text, /Can I change the shortcuts/);
  assert.match(text, /Option \+ Shift \+ Tab/);
  assert.doesNotMatch(html, /<video\b|context-(?:hero|capture|hold|place)\.(?:webm|mp4)|-poster\.webp/);
  assert.doesNotMatch(html, /aria-label="(?:Pause|Play) /);
  assert.match(html, /context-mark\.svg/);
  assert.match(html, /property="og:type" content="website"/);
  assert.match(html, /property="og:url" content="https:\/\/context\.hayashiii-gpt\.chatgpt\.site\/"/);
  assert.match(html, /property="og:image" content="https:\/\/context\.hayashiii-gpt\.chatgpt\.site\/context\/context-og\.png"/);
  assert.match(html, /property="og:image:width" content="1200"/);
  assert.match(html, /property="og:image:height" content="630"/);
  assert.match(html, /name="twitter:image" content="https:\/\/context\.hayashiii-gpt\.chatgpt\.site\/context\/context-og\.png"/);
  assert.match(html, /name="twitter:image:alt" content="cc: — A copy for what’s next."/);
  assert.match(html, /rel="icon" href="https:\/\/context\.hayashiii-gpt\.chatgpt\.site\/context\/context-favicon\.svg" type="image\/svg\+xml"/);
  assert.doesNotMatch(html, /context-current-icon\.png/);
  assert.match(html, /github\.com\/hayashiii-ghub\/context/);
  assert.match(html, /github\.com\/hayashiii-ghub\/context\/releases/);
  assert.match(html, /releases\/latest\/download\/context-macos\.dmg/);
  assert.match(text, /Open source/);
  assert.match(text, /v0\.3\.0 · macOS 26\+ · Apple Silicon &amp; Intel/);
  assert.match(text, /cc: is not yet notarized by Apple/);
  assert.match(text, /Privacy &amp; Security/);
  assert.doesNotMatch(html, /v1\.1\.4|Now becoming Context|Chrome Web Store|CodexIsland/);
  assert.match(text, /managed copies of files and folders in its local storage/);
  assert.match(text, /kept until you remove them/);
  assert.match(text, /local shelf can be shared with Codex or Claude/);
  assert.doesNotMatch(text, /On Screen|remain references|in memory|temporary copies are cleared/);
  assert.doesNotMatch(text, /\bContext\b/);
});
