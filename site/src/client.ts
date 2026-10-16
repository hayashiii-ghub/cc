import { siteCopy, siteLanguageStorageKey, type SiteLanguage } from "./copy";
import { renderInteractivePreview, renderPage, type PreviewState } from "./render";
import "./styles/global.css";
import "./styles/cc.css";
import "./styles/shelf.css";

let language: SiteLanguage = "en";
let temporaryLanguage: SiteLanguage | undefined;
let copyRevision = 0;
let preview: PreviewState = { mode: "menuBar", light: false, empty: false };

function preferredLanguage(): SiteLanguage {
  if (temporaryLanguage) return temporaryLanguage;
  try {
    const stored = localStorage.getItem(siteLanguageStorageKey);
    if (stored === "en" || stored === "ja") return stored;
  } catch {
    // Browser language remains available when storage is blocked.
  }
  return (navigator.languages[0] || navigator.language || "en").toLowerCase().startsWith("ja") ? "ja" : "en";
}

function updateMetadata() {
  const meta = siteCopy[language].meta;
  document.documentElement.lang = language;
  document.title = meta.title;
  const values = [
    ['meta[name="description"]', meta.description],
    ['meta[property="og:title"]', meta.title],
    ['meta[property="og:description"]', meta.description],
    ['meta[property="og:image:alt"]', meta.imageAlt],
    ['meta[name="twitter:title"]', meta.title],
    ['meta[name="twitter:description"]', meta.description],
    ['meta[name="twitter:image:alt"]', meta.imageAlt],
  ] as const;
  for (const [selector, value] of values) {
    document.querySelector(selector)?.setAttribute("content", value);
  }
}

type FocusTarget =
  | { kind: "control"; action: string; language?: string; mode?: string; empty?: string }
  | { kind: "faq"; id: string }
  | { kind: "link"; href: string; index: number }
  | { kind: "setup" };

// Keep focus when translated markup is replaced, including keyboard-only use.
function focusedControl(): FocusTarget | undefined {
  const active = document.activeElement;
  if (active instanceof HTMLButtonElement && active.dataset.action) {
    return {
      kind: "control",
      action: active.dataset.action,
      language: active.dataset.language,
      mode: active.dataset.mode,
      empty: active.dataset.empty,
    };
  }
  if (active instanceof HTMLElement && active.tagName === "SUMMARY") {
    const id = active.closest<HTMLElement>("details[data-faq-id]")?.dataset.faqId;
    if (id) return { kind: "faq", id };
  }
  if (active instanceof HTMLAnchorElement) {
    const href = active.getAttribute("href") ?? "";
    const links = Array.from(document.querySelectorAll<HTMLAnchorElement>("[data-page] a"));
    return { kind: "link", href, index: links.filter(link => link.getAttribute("href") === href).indexOf(active) };
  }
  if (active instanceof HTMLElement && active.matches("[data-page] pre[tabindex]")) {
    return { kind: "setup" };
  }
}

function restoreFocus(target: FocusTarget | undefined) {
  if (!target) return;
  let element: HTMLElement | undefined | null;
  if (target.kind === "control") {
    element = Array.from(document.querySelectorAll<HTMLButtonElement>("button[data-action]")).find(button =>
      button.dataset.action === target.action
      && button.dataset.language === target.language
      && button.dataset.mode === target.mode
      && button.dataset.empty === target.empty);
  } else if (target.kind === "faq") {
    element = Array.from(document.querySelectorAll<HTMLDetailsElement>("details[data-faq-id]"))
      .find(item => item.dataset.faqId === target.id)?.querySelector<HTMLElement>("summary");
  } else if (target.kind === "link") {
    element = Array.from(document.querySelectorAll<HTMLAnchorElement>("[data-page] a"))
      .filter(link => link.getAttribute("href") === target.href)[target.index];
  } else {
    element = document.querySelector<HTMLElement>("[data-page] pre[tabindex]");
  }
  element?.focus({ preventScroll: true });
}

function updateLanguage(next: SiteLanguage) {
  if (next !== language) {
    const focus = focusedControl();
    const openFAQs = new Set(Array.from(document.querySelectorAll<HTMLDetailsElement>("details[data-faq-id][open]"), item => item.dataset.faqId));
    const page = document.querySelector<HTMLElement>("[data-page]");
    language = next;
    copyRevision++;
    if (page) page.outerHTML = renderPage(language, preview);
    for (const item of document.querySelectorAll<HTMLDetailsElement>("details[data-faq-id]")) {
      item.open = openFAQs.has(item.dataset.faqId);
    }
    restoreFocus(focus);
  }
  updateMetadata();
}

function updatePreview(next: PreviewState) {
  const focus = focusedControl();
  preview = next;
  const element = document.querySelector<HTMLElement>('[data-preview-variant="interactive"]');
  if (element) element.outerHTML = renderInteractivePreview(language, preview);
  restoreFocus(focus);
}

async function copySetupRequest() {
  const revision = ++copyRevision;
  const copy = siteCopy[language];
  let message: string;
  try {
    await navigator.clipboard.writeText(copy.agentSetupPrompt);
    message = copy.setupPromptCopied;
  } catch {
    message = copy.setupPromptCopyFailed;
  }
  if (revision === copyRevision) {
    const status = document.querySelector<HTMLElement>("[data-copy-status]");
    if (status) status.textContent = message;
  }
}

document.addEventListener("click", event => {
  const target = event.target;
  const button = target instanceof Element ? target.closest<HTMLButtonElement>("button[data-action]") : null;
  if (!button) return;
  switch (button.dataset.action) {
    case "language": {
      const next = button.dataset.language;
      if (next !== "en" && next !== "ja") return;
      try {
        localStorage.setItem(siteLanguageStorageKey, next);
        temporaryLanguage = undefined;
      } catch {
        temporaryLanguage = next;
      }
      window.dispatchEvent(new Event("cc-language-change"));
      break;
    }
    case "preview-mode": {
      const mode = button.dataset.mode;
      if (mode === "menuBar" || mode === "notch") updatePreview({ ...preview, mode });
      break;
    }
    case "preview-theme":
      updatePreview({ ...preview, light: !preview.light });
      break;
    case "preview-content":
      updatePreview({ ...preview, empty: button.dataset.empty === "true" });
      break;
    case "copy-setup":
      void copySetupRequest();
      break;
  }
});

window.addEventListener("cc-language-change", () => updateLanguage(preferredLanguage()));
window.addEventListener("storage", event => {
  if (event.key === null || event.key === siteLanguageStorageKey) updateLanguage(preferredLanguage());
});
updateLanguage(preferredLanguage());
