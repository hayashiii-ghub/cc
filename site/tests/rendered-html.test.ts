import assert from "node:assert/strict";
import { test } from "bun:test";
import { join } from "node:path";
import { siteCopy } from "../src/copy.ts";
import { escapeHtml, renderInteractivePreview, renderPage, type PreviewState } from "../src/render.ts";
import { distRoot, renderDocument } from "../scripts/build.ts";

function withoutBreakHints(html: string) {
  return html
    .replace(/<wbr\s*\/?\s*>/g, "")
    .replace(/<\/?span\b[^>]*>/g, "");
}

test("renders the standalone cc: site at the root", async () => {
  const html = await Bun.file(join(distRoot, "index.html")).text();
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
  assert.match(text, /After updating cc: and Agent Tools/);
  assert.match(text, /ask your agent to open or remove selected items/);
  assert.match(text, /Settings → Open Items/);
  assert.match(text, /stored text is copied to the clipboard/);
  assert.match(text, /only its shelf entry and managed copy are removed/);
  assert.match(text, /The original file stays in place/);
  assert.match(text, /macOS defaults stay unchanged/);
  assert.match(text, /Option \+ Shift \+ Tab/);
  assert.doesNotMatch(html, /<video\b|-poster\.webp/);
  assert.doesNotMatch(html, /aria-label="(?:Pause|Play) /);
  assert.match(html, /cc-mark\.svg/);
  assert.match(html, /property="og:type" content="website"/);
  assert.match(html, /property="og:url" content="https:\/\/cc\.shigoto\.dev\/"/);
  assert.match(html, /property="og:image" content="https:\/\/cc\.shigoto\.dev\/cc\/cc-og\.png\?v=0\.4\.4"/);
  assert.match(html, /property="og:image:width" content="1200"/);
  assert.match(html, /property="og:image:height" content="630"/);
  assert.match(html, /name="twitter:image" content="https:\/\/cc\.shigoto\.dev\/cc\/cc-og\.png\?v=0\.4\.4"/);
  assert.match(html, /name="twitter:image:alt" content="cc:"/);
  assert.match(html, /rel="icon" href="\/cc\/cc-favicon\.svg" type="image\/svg\+xml"/);
  assert.match(html, /github\.com\/hayashiii-ghub\/cc/);
  assert.match(html, /github\.com\/hayashiii-ghub\/cc\/releases/);
  assert.match(html, /releases\/latest\/download\/cc-macos\.dmg/);
  assert.match(text, /Open source/);
  assert.match(text, /v0\.4\.8 · macOS 26\+ · Apple Silicon &amp; Intel/);
  assert.match(text, /cc: is not yet notarized by Apple/);
  assert.match(text, /Privacy &amp; Security/);
  assert.doesNotMatch(html, /v1\.1\.4|Chrome Web Store|CodexIsland/);
  assert.match(text, /managed copies of files and folders in its local storage/);
  assert.match(text, /kept until you remove them/);
  assert.match(text, /ask Codex or Claude Code to read the items you need/);
  assert.doesNotMatch(text, /On Screen|remain references|in memory|temporary copies are cleared/);
});


for (const language of ["en", "ja"] as const) {
  test(`renders complete ${language} copy without a framework runtime`, () => {
    const html = renderPage(language);
    const copy = siteCopy[language];
    assert.match(html, new RegExp(`class="page" lang="${language}" data-page`));
    assert.equal((html.match(/<h1\b/g) ?? []).length, 1);
    assert.equal((html.match(/<main\b/g) ?? []).length, 1);
    for (const phrase of copy.heroTitle.flat()) assert.ok(html.includes(escapeHtml(phrase)));
    for (const faq of copy.faqs) {
      assert.ok(html.includes(escapeHtml(faq.question)));
      assert.ok(html.includes(escapeHtml(faq.answer)));
    }
    assert.match(html, new RegExp(`aria-pressed="true" data-action="language" data-language="${language}"`));
    assert.doesNotMatch(html, /_next\/|vinext|data-rsc|<video\b/);
    const document = renderDocument(html, { styles: [], scripts: [] }, language);
    assert.ok(document.startsWith(`<!DOCTYPE html>\n<html lang="${language}">`));
    assert.ok(document.includes(`<meta name="description" content="${escapeHtml(copy.meta.description)}">`));
  });

  for (const mode of ["menuBar", "notch"] as const) {
    for (const light of [false, true]) {
      for (const empty of [false, true]) {
        test(`renders ${language} ${mode} light=${light} empty=${empty}`, () => {
          const state: PreviewState = { mode, light, empty };
          const html = renderInteractivePreview(language, state);
          const copy = siteCopy[language].preview;
          assert.match(html, new RegExp(`data-shelf-mode="${mode}" data-shelf-state="${empty ? "empty" : "items"}"`));
          assert.ok(html.includes(escapeHtml(empty ? copy.emptyCount : copy.count)));
          assert.equal((html.match(/class="itemTitle"/g) ?? []).length, empty ? 0 : 3);
          assert.equal(html.includes('class="stage light"'), mode === "menuBar" && light);
          assert.equal(html.includes('class="notchCutout"'), mode === "notch");
          assert.equal(html.includes('data-action="preview-theme"'), mode === "menuBar");
          assert.equal(html.includes(escapeHtml(copy.emptyMessage)), empty);
          assert.match(html, new RegExp(`aria-pressed="true" data-action="preview-mode" data-mode="${mode}"`));
          assert.match(html, new RegExp(`aria-pressed="true" data-action="preview-content" data-empty="${empty}"`));
        });
      }
    }
  }
}

test("escapes translated text, HTML attributes, and generated asset URLs", () => {
  assert.equal(escapeHtml('&<>"\''), "&amp;&lt;&gt;&quot;&#x27;");
  const payload = '<img src=x onerror="alert(1)"> & "quoted"';
  const mutable = siteCopy.en as unknown as { home: string; heroSubtitle: string[] };
  const previous = { home: mutable.home, heroSubtitle: mutable.heroSubtitle };
  try {
    mutable.home = payload;
    mutable.heroSubtitle = [payload];
    const html = renderPage("en");
    assert.ok(html.includes(`alt="${escapeHtml(payload)}"`));
    assert.ok(html.includes(`<span>${escapeHtml(payload)}</span>`));
    assert.ok(!html.includes(payload));
    assert.doesNotMatch(html, /<img src=x/);
  } finally {
    mutable.home = previous.home;
    mutable.heroSubtitle = previous.heroSubtitle;
  }
  const document = renderDocument("<main></main>", { scripts: ['/assets/a"><img>.js'], styles: ['/assets/a" onload="x.css'] });
  assert.ok(document.includes('src="/assets/a&quot;&gt;&lt;img&gt;.js"'));
  assert.ok(document.includes('href="/assets/a&quot; onload=&quot;x.css"'));
  assert.doesNotMatch(document, /<img>|href="[^"\n]*" onload=/);
});

test("build emits hashed browser assets and preserves local image, font, and OGP links", async () => {
  const html = await Bun.file(join(distRoot, "index.html")).text();
  assert.ok(html.startsWith("<!DOCTYPE html>"));
  assert.match(html, /<meta charset="utf-8">/);
  assert.match(html, /<meta name="viewport" content="width=device-width, initial-scale=1">/);
  const scripts = [...html.matchAll(/<script type="module" src="([^"]+)"/g)].map((match) => match[1]!);
  const styles = [...html.matchAll(/<link rel="stylesheet" href="([^"]+)"/g)].map((match) => match[1]!);
  assert.equal(scripts.length, 1);
  assert.ok(styles.length > 0);
  for (const url of [...scripts, ...styles]) assert.match(url, /^\/assets\/[^/]+-[a-zA-Z0-9_-]+\.(?:js|css)$/);
  for (const match of html.matchAll(/(?:src|href|content)="([^"]+)"/g)) {
    const value = match[1]!;
    if (!value.startsWith("/") && !value.startsWith("https://cc.shigoto.dev/")) continue;
    const pathname = new URL(value, "https://cc.shigoto.dev").pathname;
    if (pathname === "/") continue;
    assert.ok(await Bun.file(join(distRoot, pathname.slice(1))).exists(), `Missing built asset: ${pathname}`);
  }
  for (const style of styles) {
    const css = await Bun.file(join(distRoot, style.slice(1))).text();
    for (const match of css.matchAll(/url\(["']?(\/cc\/[^"')]+)["']?\)/g)) {
      assert.ok(await Bun.file(join(distRoot, match[1]!.slice(1))).exists(), `Missing font/image: ${match[1]}`);
    }
  }
  assert.doesNotMatch(html, /_next\/|vinext|data-rsc/);
});
