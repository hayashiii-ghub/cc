import { siteCopy, type SiteLanguage } from "./copy";

export type PreviewState = {
  mode: "menuBar" | "notch";
  light: boolean;
  empty: boolean;
};

type ItemKind = "text" | "file" | "folder";
type PreviewItem = { title: string; source: string; note: string; kind: ItemKind };
type FeaturePreviewVariant = "files" | "handoff" | "notch";

const defaultPreviewState: PreviewState = { mode: "menuBar", light: false, empty: false };
const repositoryUrl = "https://github.com/hayashiii-ghub/cc";
const releasesUrl = `${repositoryUrl}/releases`;
const downloadUrl = `${releasesUrl}/latest/download/cc-macos.dmg`;
const htmlEntities: Record<string, string> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#x27;",
};

// Text and quoted HTML attributes share the same escaping boundary.
export function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (character) => htmlEntities[character]!);
}

function renderMark(width: number, height: number, alt: string, className?: string): string {
  return `<img src="/cc/cc-mark.svg" alt="${escapeHtml(alt)}" width="${width}" height="${height}" loading="lazy" decoding="async" srcset="/cc/cc-mark.svg ${width}w"${className ? ` class="${escapeHtml(className)}"` : ""} data-nimg="1">`;
}

function renderHeadline(language: SiteLanguage): string {
  return siteCopy[language].heroTitle.map((line) =>
    `<span class="heroLine">${line.map((phrase) => `<span class="heroPhrase">${escapeHtml(phrase)}</span>`).join("")}</span>`,
  ).join("");
}

function renderItemIcon(kind: ItemKind): string {
  const paths = kind === "text"
    ? '<path d="M4 7h19M4 12h13M4 17h19M4 22h9"></path>'
    : kind === "folder"
      ? '<path d="M3 8a2 2 0 0 1 2-2h6l3 3h9a2 2 0 0 1 2 2v11H3V8Z"></path>'
      : '<path d="M7 3h10l6 6v16H7V3Z"></path><path d="M17 3v6h6M11 14h8M11 18h8M11 22h5"></path>';
  return `<svg class="itemIcon" viewBox="0 0 28 28" fill="none" aria-hidden="true">${paths}</svg>`;
}

function renderShelfWindow(
  language: SiteLanguage,
  {
    mode = "menuBar",
    empty = false,
    emphasizeSource = false,
    items,
  }: {
    mode?: PreviewState["mode"];
    empty?: boolean;
    emphasizeSource?: boolean;
    items?: readonly PreviewItem[];
  } = {},
): string {
  const copy = siteCopy[language].preview;
  const shelfItems = items ?? copy.sampleItems;
  const hasItems = !empty && shelfItems.length > 0;
  const content = empty
    ? `<div class="emptyShelf"><p>${escapeHtml(copy.emptyMessage)}</p></div>`
    : `<ul class="itemList" role="list">${shelfItems.map((item) => [
      '<li class="itemRow">',
      renderItemIcon(item.kind),
      '<div class="itemCopy">',
      `<p class="itemTitle">${escapeHtml(item.title)}</p>`,
      `<p class="itemDetail"><span${emphasizeSource ? ' class="sourceEmphasis"' : ""}>${escapeHtml(item.source)}</span><span class="detailSeparator"> · </span>${escapeHtml(item.note)}</p>`,
      '</div>',
      `<span class="itemMenu" aria-hidden="true">${escapeHtml(copy.details)}</span>`,
      '</li>',
    ].join("")).join("")}</ul>`;

  return [
    `<div class="shelf${mode === "notch" ? " notchShelf" : ""}" data-shelf-mode="${escapeHtml(mode)}" data-shelf-state="${empty ? "empty" : "items"}" lang="${escapeHtml(language)}">`,
    mode === "notch" ? '<div class="notchCutout" aria-hidden="true"></div>' : "",
    '<div class="shelfHeader">',
    renderMark(30, 26, "cc:", "mark"),
    `<span class="itemCount" aria-live="polite">${escapeHtml(empty ? copy.emptyCount : copy.count)}</span>`,
    '<span class="windowControl windowSettings" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none"><path d="M10 2h4l1 3 2 1 3-1 2 3-2 2v4l2 2-2 3-3-1-2 1-1 3h-4l-1-3-2-1-3 1-2-3 2-2v-4L2 8l2-3 3 1 2-1 1-3Z"></path><circle cx="12" cy="12" r="3.5"></circle></svg></span>',
    '</div>',
    content,
    `<div class="shelfFooter"><span class="footerPrimary"><span>${escapeHtml(copy.addFiles)}</span><span>${escapeHtml(copy.paste)}</span></span>`,
    hasItems ? `<span class="footerActions"><span class="dragLabel">${escapeHtml(copy.dragFiles)}</span><span class="clearAllLabel">${escapeHtml(copy.clearAll)}</span></span>` : "",
    '</div></div>',
  ].join("");
}

function renderFeaturePreview(language: SiteLanguage, variant: FeaturePreviewVariant): string {
  const copy = siteCopy[language].preview;
  const introduction = variant === "files"
    ? [
      '<div class="finderSelection">',
      `<p class="sceneLabel">${escapeHtml(copy.finderSelection)}</p>`,
      `<div class="selectedFiles"><span>${renderItemIcon("file")}${escapeHtml(copy.referenceItems[2].title)}</span><span>${renderItemIcon("file")}${escapeHtml(copy.referenceItems[1].title)}</span></div>`,
      '</div><div class="flowCue"><span aria-hidden="true">↓</span><kbd>⌥ Tab</kbd></div>',
    ].join("")
    : variant === "handoff"
      ? `<div class="sources" aria-label="${escapeHtml(copy.sourceLabel)}">${copy.sources.map((source) => `<span>${escapeHtml(source)}</span>`).join("")}</div>`
      : "";
  return [
    `<div class="featureScene${variant === "notch" ? " notchScene" : ""}" data-preview-variant="${escapeHtml(variant)}" lang="${escapeHtml(language)}">`,
    introduction,
    renderShelfWindow(language, {
      mode: variant === "notch" ? "notch" : "menuBar",
      emphasizeSource: variant === "handoff",
      items: variant === "files" ? copy.referenceItems : variant === "handoff" ? copy.receivedItems : undefined,
    }),
    `<p class="sceneNote">${escapeHtml(variant === "files" ? copy.filesNote : variant === "handoff" ? copy.handoffNote : copy.notchNote)}</p>`,
    '</div>',
  ].join("");
}

export function renderInteractivePreview(language: SiteLanguage, state: PreviewState): string {
  const copy = siteCopy[language].preview;
  return [
    `<div class="preview" data-preview-variant="interactive" lang="${escapeHtml(language)}">`,
    '<div class="previewTop">',
    `<div class="segmented" role="group" aria-label="${escapeHtml(copy.location)}">`,
    `<button type="button" aria-pressed="${state.mode === "menuBar" ? "true" : "false"}" data-action="preview-mode" data-mode="menuBar">${escapeHtml(copy.menuBar)}</button>`,
    `<button type="button" aria-pressed="${state.mode === "notch" ? "true" : "false"}" data-action="preview-mode" data-mode="notch">${escapeHtml(copy.notch)}</button>`,
    '</div>',
    state.mode === "menuBar" ? `<button class="quietButton" type="button" aria-pressed="${state.light ? "true" : "false"}" data-action="preview-theme">${escapeHtml(state.light ? copy.dark : copy.light)}</button>` : "",
    '</div>',
    `<div class="stage${state.mode === "menuBar" && state.light ? " light" : ""}">${renderShelfWindow(language, state)}</div>`,
    '<div class="previewBottom">',
    `<div class="segmented" role="group" aria-label="${escapeHtml(copy.contents)}">`,
    `<button type="button" aria-pressed="${state.empty ? "false" : "true"}" data-action="preview-content" data-empty="false">${escapeHtml(copy.items)}</button>`,
    `<button type="button" aria-pressed="${state.empty ? "true" : "false"}" data-action="preview-content" data-empty="true">${escapeHtml(copy.empty)}</button>`,
    '</div>',
    `<p class="demoNote">${escapeHtml(copy.demoNote)}</p>`,
    '</div></div>',
  ].join("");
}

function renderAgentSetup(language: SiteLanguage): string {
  const copy = siteCopy[language];
  return [
    '<div class="agentSetup">',
    `<h3>${escapeHtml(copy.agentSetupTitle)}</h3>`,
    `<p class="centerCopy">${escapeHtml(copy.agentSetupBody)}</p>`,
    `<pre class="setupPrompt" tabindex="0">${escapeHtml(copy.agentSetupPrompt)}</pre>`,
    `<button class="button buttonSecondary setupCopyButton" type="button" data-action="copy-setup">${escapeHtml(copy.copySetupPrompt)}</button>`,
    '<p class="copyStatus" role="status" data-copy-status></p>',
    '</div>',
  ].join("");
}

export function renderPage(language: SiteLanguage, state: PreviewState = defaultPreviewState): string {
  const copy = siteCopy[language];
  const headline = renderHeadline(language);
  return [
    `<div class="page" lang="${escapeHtml(language)}" data-page>`,
    `<a class="skipLink" href="#content">${escapeHtml(copy.skip)}</a>`,
    `<nav class="navPill" aria-label="${escapeHtml(copy.primary)}">`,
    `<a class="brand" href="#top">${renderMark(30, 24, copy.home)}</a>`,
    `<a class="navHow" href="#how">${escapeHtml(copy.navHow)}</a>`,
    `<a href="#install">${escapeHtml(copy.navInstall)}</a>`,
    `<a href="${escapeHtml(repositoryUrl)}">GitHub</a>`,
    `<div class="languageSwitch" role="group" aria-label="${escapeHtml(copy.languageLabel)}">`,
    `<button class="languageButton" type="button" lang="ja" aria-label="日本語" aria-pressed="${language === "ja" ? "true" : "false"}" data-action="language" data-language="ja">JA</button>`,
    `<button class="languageButton" type="button" lang="en" aria-label="English" aria-pressed="${language === "en" ? "true" : "false"}" data-action="language" data-language="en">EN</button>`,
    '</div></nav>',
    '<main id="content"><section class="hero" id="top" aria-labelledby="cc-title">',
    `<a class="releaseChip" href="${escapeHtml(repositoryUrl)}"><span>${escapeHtml(copy.openSource)}</span><span>${escapeHtml(copy.builtForMac)}</span></a>`,
    `<h1 id="cc-title">${headline}</h1>`,
    `<p class="heroSubtitle">${copy.heroSubtitle.map((line) => `<span>${escapeHtml(line)}</span>`).join("")}</p>`,
    `<div class="heroActions"><a class="button buttonPrimary" href="#install">${escapeHtml(copy.downloadForMac)}</a><a class="button buttonSecondary" href="${escapeHtml(repositoryUrl)}">${escapeHtml(copy.viewOnGitHub)}</a></div>`,
    `<p class="heroMeta">${escapeHtml(copy.heroMeta)}</p>`,
    '</section>',
    `<section class="showcaseSection" aria-label="${escapeHtml(copy.showcaseLabel)}"><div class="showcaseFrame">${renderInteractivePreview(language, state)}</div><p class="shelfTypes">${escapeHtml(copy.shelfTypes.join(" · "))}</p></section>`,
    `<section class="section features" id="how" aria-label="${escapeHtml(copy.howLabel)}">`,
    copy.features.map((feature, index) => [
      `<article class="featureRow${index % 2 ? " flip" : ""}"><div class="featureCopy">`,
      `<p class="eyebrow">— ${escapeHtml(feature.index)}</p>`,
      `<h2>${escapeHtml(feature.title)}</h2><p>${escapeHtml(feature.body)}</p><p class="featureNote">${escapeHtml(feature.note)}</p>`,
      `</div><div class="featureVisual">${renderFeaturePreview(language, feature.preview)}</div></article>`,
    ].join("")).join(""),
    '</section>',
    '<section class="section privacy" aria-labelledby="privacy-title"><div class="sectionNarrow">',
    `<p class="eyebrow">${escapeHtml(copy.privacyEyebrow)}</p><h2 id="privacy-title">${escapeHtml(copy.privacyTitle)}</h2>`,
    `<ul class="privacyMarks" aria-label="${escapeHtml(copy.privacyLabel)}">${copy.privacyMarks.map((mark) => `<li>${escapeHtml(mark)}</li>`).join("")}</ul>`,
    `<p class="centerCopy">${escapeHtml(copy.privacyBody)}</p>`,
    '</div></section>',
    '<section class="section installSection" id="install" aria-labelledby="install-title"><div class="sectionNarrow">',
    `<p class="eyebrow">${escapeHtml(copy.installEyebrow)}</p><h2 id="install-title">${escapeHtml(copy.installTitle)}</h2>`,
    `<h3 class="installStep">${escapeHtml(copy.installAppStep)}</h3><p class="centerCopy">${escapeHtml(copy.installBody)}</p>`,
    `<div class="installBar"><div class="installName">${renderMark(40, 40, copy.markAlt)}<span>${escapeHtml(copy.installName)}</span></div><a class="button buttonPrimary" href="${escapeHtml(downloadUrl)}">${escapeHtml(copy.downloadDmg)}</a></div>`,
    `<p class="installMeta">${escapeHtml(copy.installMeta)}</p><p class="installNote">${escapeHtml(copy.installNote)}</p>`,
    renderAgentSetup(language),
    '</div></section>',
    '<section class="section faq" aria-labelledby="faq-title"><div class="sectionNarrow">',
    `<p class="eyebrow">${escapeHtml(copy.faqEyebrow)}</p><h2 id="faq-title">${escapeHtml(copy.faqTitle)}</h2><div>`,
    copy.faqs.map(({ id, question, answer }) => `<details class="faqItem" data-faq-id="${escapeHtml(id)}"><summary>${escapeHtml(question)}</summary><p>${escapeHtml(answer)}</p></details>`).join(""),
    '</div></div></section>',
    `<section class="finalCta" aria-labelledby="final-title"><h2 id="final-title">${headline}</h2><div class="heroActions"><a class="button buttonPrimary" href="${escapeHtml(downloadUrl)}">${escapeHtml(copy.downloadForMac)}</a><a class="button buttonSecondary" href="${escapeHtml(repositoryUrl)}">${escapeHtml(copy.viewOnGitHub)}</a></div></section>`,
    '</main>',
    `<footer class="footer"><div class="footerMeta">${renderMark(30, 24, "cc:")}<span class="dot"></span><span>${escapeHtml(copy.openSource)}</span></div>`,
    `<div class="footerLinks"><a href="${escapeHtml(repositoryUrl)}">GitHub</a><a href="${escapeHtml(releasesUrl)}">${escapeHtml(copy.releases)}</a><a href="${escapeHtml(`${repositoryUrl}/issues`)}">${escapeHtml(copy.issues)}</a></div></footer>`,
    '</div>',
  ].join("");
}
