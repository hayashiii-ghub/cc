import { siteCopy, type SiteLanguage } from "./copy";

export type PreviewState = {
  light: boolean;
  empty: boolean;
  selected?: boolean;
};

type ItemKind = "text" | "file" | "folder";
type PreviewItem = { title: string; source: string; note: string; kind: ItemKind };

const defaultPreviewState: PreviewState = { light: false, empty: false };
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

function renderHeadline(lines: readonly (readonly string[])[]): string {
  return lines.map((line) =>
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

const shelfGlyphs = {
  grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  select: '<circle cx="6" cy="6" r="2.5"/><circle cx="6" cy="17" r="2.5"/><path d="M13 6h8M13 17h8"/>',
  done: '<path d="m4 12 5 5L20 6"/>',
  trash: '<path d="M3 6h18M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7m4-7v7"/>',
  settings: '<path d="m10 2-.8 2.5-2.2 1.3-2.6-.6-2 3.5 1.9 1.9v2.8l-1.9 1.9 2 3.5 2.6-.6 2.2 1.3L10 22h4l.8-2.6 2.2-1.3 2.6.6 2-3.5-1.9-1.9v-2.8l1.9-1.9-2-3.5-2.6.6-2.2-1.3L14 2Z"/><circle cx="12" cy="12" r="3.6"/>',
};

function shelfControl(icon: keyof typeof shelfGlyphs, dimmed = false): string {
  return `<span class="windowControl${dimmed ? " dimmed" : ""}"><svg viewBox="0 0 24 24" fill="none">${shelfGlyphs[icon]}</svg></span>`;
}

function renderShelfWindow(
  language: SiteLanguage,
  {
    empty = false,
    selected = false,
    emphasizeSource = false,
    items,
  }: {
    empty?: boolean;
    selected?: boolean;
    emphasizeSource?: boolean;
    items?: readonly PreviewItem[];
  } = {},
): string {
  const copy = siteCopy[language].preview;
  const shelfItems = items ?? copy.sampleItems;
  const hasItems = !empty && shelfItems.length > 0;
  const selectedCount = selected && hasItems ? Math.min(2, shelfItems.length) : 0;
  const content = empty
    ? `<div class="emptyShelf"><p>${escapeHtml(copy.emptyMessage)}</p></div>`
    : `<ul class="itemList" role="list">${shelfItems.map((item, index) => [
      `<li class="itemRow${index < selectedCount ? " isSelected" : ""}">`,
      selected ? `<span class="selectionMark" aria-hidden="true">${index < selectedCount ? "✓" : ""}</span>` : "",
      '<div class="itemCopy">',
      `<p class="itemTitle">${escapeHtml(item.title)}</p>`,
      `<p class="itemDetail"><span${emphasizeSource ? ' class="sourceEmphasis"' : ""}>${escapeHtml(item.source)}</span><span class="detailSeparator"> · </span>${escapeHtml(item.note)}</p>`,
      '</div>',
      selected ? "" : '<span class="itemMenu" aria-hidden="true">…</span>',
      '</li>',
    ].join("")).join("")}</ul>`;

  return [
    `<div class="shelf" data-shelf-state="${empty ? "empty" : "items"}" lang="${escapeHtml(language)}">`,
    '<div class="shelfHeader">',
    renderMark(30, 26, "cc:", "mark"),
    `<span class="itemCount" aria-live="polite">${empty ? 0 : selected ? selectedCount : shelfItems.length}</span>`,
    '<div class="shelfTools" aria-hidden="true">',
    shelfControl("grid"),
    shelfControl(selected ? "done" : "select", !hasItems),
    shelfControl("trash", !hasItems),
    shelfControl("settings"),
    '</div>',
    '</div>',
    content,
    `<div class="shelfFooter"><span class="footerPrimary"><span><b aria-hidden="true">＋</b> ${escapeHtml(copy.addFiles)}</span></span>`,
    hasItems ? `<span class="footerActions"><span class="dragLabel"><b aria-hidden="true">⠿</b> ${selected ? escapeHtml(copy.dragSelected) + ` (${selectedCount})` : escapeHtml(copy.dragFiles)}</span></span>` : "",
    '</div></div>',
  ].join("");
}

function renderWorkflow(language: SiteLanguage): string {
  const { flow, preview } = siteCopy[language];
  const arrow = '<span class="journeyArrow" aria-hidden="true">→</span>';
  const agent = (prompt: string) => `<div class="agentScene"><div class="miniWindowBar"><i></i><i></i><i></i><span>AI</span></div><div class="requestBubble">${escapeHtml(prompt)}<span aria-hidden="true">↵</span></div><div class="agentNames">Codex · Claude Code<br>Antigravity</div></div>`;
  const shelf = (received: boolean) => `<div class="journeyShelf">${renderShelfWindow(language, { emphasizeSource: true, items: received ? preview.receivedItems : preview.referenceItems })}</div>`;
  return `<section class="section workflow" id="how" aria-label="${escapeHtml(siteCopy[language].howLabel)}">
    <article class="journey">
      <h2><span>01</span>${escapeHtml(flow.share)}</h2>
      <div class="journeyTrack">
        <div class="journeyStop"><div class="materialScene"><div class="fileTile">${renderItemIcon("file")}<span>${escapeHtml(preview.referenceItems[2].title)}</span></div><div class="fileTile imageTile"><div class="imageThumbnail" aria-hidden="true"></div><span>${escapeHtml(preview.referenceItems[1].title)}</span></div><div class="noteTile">${renderItemIcon("text")}<span>${escapeHtml(preview.referenceItems[0].title)}</span></div></div><p class="stopLabel">${escapeHtml(flow.materials)}</p></div>
        ${arrow}<div class="journeyStop">${shelf(false)}<p class="stopLabel">cc:</p></div>
        ${arrow}<div class="journeyStop">${agent(flow.readRequest)}<p class="stopLabel">${escapeHtml(flow.ask)}</p></div>
      </div>
    </article>
    <article class="journey">
      <h2><span>02</span>${escapeHtml(flow.receive)}</h2>
      <div class="journeyTrack">
        <div class="journeyStop">${agent(flow.returnRequest)}<p class="stopLabel">${escapeHtml(flow.ask)}</p></div>
        ${arrow}<div class="journeyStop">${shelf(true)}<p class="stopLabel">${escapeHtml(flow.sameShelf)}</p></div>
        ${arrow}<div class="journeyStop"><div class="resultScene"><div class="miniWindowBar"><i></i><i></i><i></i><span>${escapeHtml(preview.receivedItems[0].title)}</span></div><div class="documentPreview" aria-hidden="true"><div class="documentHeading"></div><div></div><div></div><div class="documentShort"></div><div class="documentHeading"></div><div></div><div></div></div><div class="floatingFile">${renderItemIcon("file")}<svg viewBox="0 0 24 28" aria-hidden="true"><path d="M4 2v21l5-5 4 8 4-2-4-8h8Z"/></svg></div></div><p class="stopLabel">${escapeHtml(flow.openDrag)}</p></div>
      </div>
    </article>
    <p class="workflowNote">${escapeHtml(flow.sample)}</p>
    <ul class="storageFacts">${flow.storage.map((label) => `<li><span aria-hidden="true">✓</span>${escapeHtml(label)}</li>`).join("")}</ul>
  </section>`;
}

export function renderInteractivePreview(language: SiteLanguage, state: PreviewState): string {
  const copy = siteCopy[language].preview;
  return [
    `<div class="preview" data-preview-variant="interactive" lang="${escapeHtml(language)}">`,
    `<div class="stage macDesktop${state.light ? " light" : ""}">`,
    '<div class="desktopScreen">',
    '<img class="desktopBackdrop" src="/cc/mac-desktop-scene.jpg" width="1643" height="957" alt="" fetchpriority="high">',
    `<span class="desktopMenuMark" aria-hidden="true">${renderMark(25, 20, "")}</span>`,
    `<div class="desktopShelf">${renderShelfWindow(language, state)}</div>`,
    '</div></div>',
    '<div class="previewControls">',
    `<div class="segmented" role="group" aria-label="${escapeHtml(copy.contents)}">`,
    `<button type="button" aria-pressed="${state.empty || state.selected ? "false" : "true"}" data-action="preview-content" data-empty="false">${escapeHtml(copy.items)}</button>`,
    `<button type="button" aria-pressed="${state.selected && !state.empty ? "true" : "false"}" data-action="preview-selection">${escapeHtml(copy.selected)}</button>`,
    `<button type="button" aria-pressed="${state.empty ? "true" : "false"}" data-action="preview-content" data-empty="true">${escapeHtml(copy.empty)}</button>`,
    '</div>',
    `<button class="quietButton" type="button" aria-pressed="${state.light ? "true" : "false"}" data-action="preview-theme">${escapeHtml(state.light ? copy.dark : copy.light)}</button>`,
    '</div>',
    `<p class="demoNote">${escapeHtml(copy.demoNote)}</p>`,
    '</div>',
  ].join("");
}

function renderAgentSetup(language: SiteLanguage): string {
  const copy = siteCopy[language];
  return [
    '<div class="setupActions">',
    `<button class="setupCopyButton" type="button" data-action="copy-setup">${escapeHtml(copy.copySetupPrompt)} <span aria-hidden="true">↗</span></button>`,
    '<p class="copyStatus" role="status" data-copy-status></p>',
    '</div>',
  ].join("");
}

export function renderPage(language: SiteLanguage, state: PreviewState = defaultPreviewState): string {
  const copy = siteCopy[language];
  const headline = renderHeadline(copy.heroTitle);
  return [
    `<div class="page" lang="${escapeHtml(language)}" data-page>`,
    `<a class="skipLink" href="#content">${escapeHtml(copy.skip)}</a>`,
    `<nav class="navPill" aria-label="${escapeHtml(copy.primary)}">`,
    `<a class="brand" href="#top">${renderMark(64, 44, copy.home)}</a>`,
    `<a class="navHow" href="#how">${escapeHtml(copy.navHow)}</a>`,
    `<a href="${escapeHtml(repositoryUrl)}">GitHub</a>`,
    `<div class="languageSwitch" role="group" aria-label="${escapeHtml(copy.languageLabel)}">`,
    `<button class="languageButton" type="button" lang="ja" aria-label="日本語" aria-pressed="${language === "ja" ? "true" : "false"}" data-action="language" data-language="ja">JA</button>`,
    `<button class="languageButton" type="button" lang="en" aria-label="English" aria-pressed="${language === "en" ? "true" : "false"}" data-action="language" data-language="en">EN</button>`,
    '</div></nav>',
    '<main id="content"><section class="hero" id="top" aria-labelledby="cc-title">',
    `<div class="heroCopy"><h1 id="cc-title">${headline}</h1>`,
    `<p class="heroSubtitle">${copy.heroSubtitle.map((line) => `<span>${escapeHtml(line)}</span>`).join("")}</p>`,
    '</div><div class="heroDownload">',
    `<div class="heroActions"><a class="button buttonPrimary" href="#install">${escapeHtml(copy.downloadForMac)}</a></div>`,
    `<p class="heroMeta">${escapeHtml(copy.heroMeta)}</p></div>`,
    '</section>',
    `<section class="showcaseSection" aria-label="${escapeHtml(copy.showcaseLabel)}"><div class="showcaseFrame">${renderInteractivePreview(language, state)}</div><p class="shelfTypes">${escapeHtml(copy.shelfTypes.join(" · "))}</p></section>`,
    renderWorkflow(language),
    '<section class="section installSection" id="install" aria-labelledby="install-title"><div class="sectionNarrow">',
    `<p class="eyebrow">${escapeHtml(copy.installEyebrow)}</p><h2 id="install-title">${escapeHtml(copy.installTitle)}</h2>`,
    `<ol class="visualSetup"><li><div class="installDiagram">${renderMark(64, 64, "cc:")}<span class="installArrow" aria-hidden="true">→</span><div class="applicationsFolder">${renderItemIcon("folder")}<span>Applications</span></div></div><h3><span>01</span>${escapeHtml(copy.flow.installApp)}</h3></li><li><div class="settingsDiagram"><div class="miniWindowBar"><i></i><i></i><i></i><span>Settings</span></div><div class="settingsContent"><span>AI Tools</span><span class="setUpLabel">Set Up</span></div><div class="setupAgents">Codex · Claude Code · Antigravity</div></div><h3><span>02</span>${escapeHtml(copy.flow.installAgent)}</h3></li></ol>`,
    `<div class="installBar"><div class="installName">${renderMark(40, 40, copy.markAlt)}<span>${escapeHtml(copy.installName)}</span></div><a class="button buttonPrimary" href="${escapeHtml(downloadUrl)}">${escapeHtml(copy.downloadDmg)}</a></div>`,
    `<p class="installMeta">${escapeHtml(copy.installMeta)}</p><p class="installNote">${escapeHtml(copy.installNote)}</p>`,
    renderAgentSetup(language),
    `<a class="guideLink" href="${escapeHtml(repositoryUrl + '#使い方')}">${escapeHtml(copy.guideLabel)}</a>`,
    '</div></section>',
    '</main>',
    `<footer class="footer"><div class="footerMeta">${renderMark(30, 24, "cc:")}<span class="dot"></span><span>${escapeHtml(copy.openSource)}</span></div>`,
    `<div class="footerLinks"><a href="${escapeHtml(repositoryUrl)}">GitHub</a><a href="${escapeHtml(releasesUrl)}">${escapeHtml(copy.releases)}</a><a href="${escapeHtml(`${repositoryUrl}/issues`)}">${escapeHtml(copy.issues)}</a></div></footer>`,
    '</div>',
  ].join("");
}
