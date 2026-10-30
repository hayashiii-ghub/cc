import { cp, mkdir, mkdtemp, rename, rm } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { dirname, join, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { siteCopy, type SiteLanguage } from "../src/copy.ts";
import { escapeHtml, renderPage } from "../src/render.ts";

export const siteRoot = dirname(dirname(fileURLToPath(import.meta.url)));
export const distRoot = join(siteRoot, "dist");
const siteURL = "https://cc.shigoto.dev";
const imageHash = createHash("sha256").update(readFileSync(join(siteRoot, "public/cc/cc-og.png"))).digest("hex").slice(0, 12);
const imageURL = `${siteURL}/cc/cc-og.png?v=${imageHash}`;

type Assets = { scripts: string[]; styles: string[] };

export function renderDocument(body: string, assets: Assets, language: SiteLanguage = "en"): string {
  const meta = siteCopy[language].meta;
  const title = escapeHtml(meta.title);
  const description = escapeHtml(meta.description);
  const imageAlt = escapeHtml(meta.imageAlt);
  const styles = assets.styles.map((url) => `<link rel="stylesheet" href="${escapeHtml(url)}">`).join("\n");
  const scripts = assets.scripts.map((url) => `<script type="module" src="${escapeHtml(url)}"></script>`).join("\n");
  return `<!DOCTYPE html>
<html lang="${language}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<meta name="description" content="${description}">
<link rel="canonical" href="${siteURL}/">
<link rel="icon" href="/cc/cc-favicon.svg" type="image/svg+xml">
<link rel="shortcut icon" href="/cc/cc-favicon.svg">
<meta property="og:title" content="${title}">
<meta property="og:description" content="${description}">
<meta property="og:type" content="website">
<meta property="og:url" content="${siteURL}/">
<meta property="og:image" content="${imageURL}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="${imageAlt}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${title}">
<meta name="twitter:description" content="${description}">
<meta name="twitter:image" content="${imageURL}">
<meta name="twitter:image:alt" content="${imageAlt}">
${styles}
</head>
<body>
${body}
${scripts}
</body>
</html>
`;
}

export async function buildSite(): Promise<void> {
  const staging = await mkdtemp(join(siteRoot, ".site-build-"));
  try {
    await cp(join(siteRoot, "public"), staging, { recursive: true });
    const result = await Bun.build({
      entrypoints: [join(siteRoot, "src/client.ts")],
      outdir: staging,
      target: "browser",
      format: "esm",
      external: ["/cc/*"],
      naming: { entry: "assets/[name]-[hash].[ext]", chunk: "assets/chunk-[hash].[ext]", asset: "assets/[name]-[hash].[ext]" },
      minify: true,
      sourcemap: "none",
    });
    if (!result.success) throw new AggregateError(result.logs, "Site bundle failed");
    const urls = result.outputs.map((output) => `/${relative(staging, output.path).split(sep).join("/")}`);
    const assets = { scripts: urls.filter((url) => url.endsWith(".js")), styles: urls.filter((url) => url.endsWith(".css")) };
    if (assets.scripts.length !== 1 || assets.styles.length === 0) throw new Error("Expected browser JavaScript and CSS bundles");
    await Bun.write(join(staging, "index.html"), renderDocument(renderPage("en"), assets));
    await rm(distRoot, { recursive: true, force: true });
    await mkdir(dirname(distRoot), { recursive: true });
    await rename(staging, distRoot);
    console.log(`Built ${relative(siteRoot, distRoot)}/index.html and ${assets.scripts.length + assets.styles.length} asset bundles.`);
  } finally {
    await rm(staging, { recursive: true, force: true });
  }
}

if (import.meta.main) await buildSite();
