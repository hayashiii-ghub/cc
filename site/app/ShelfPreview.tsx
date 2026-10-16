"use client";

import Image from "next/image";
import { useState } from "react";

import styles from "./shelf-preview.module.css";
import { siteCopy, type SiteLanguage } from "./copy";

export type ShelfPreviewVariant = "interactive" | "files" | "handoff" | "notch";
type ShelfMode = "menuBar" | "notch";
type ItemKind = "text" | "file" | "folder";
type PreviewItem = { title: string; source: string; note: string; kind: ItemKind };

function ItemIcon({ kind }: { kind: ItemKind }) {
  return (
    <svg className={styles.itemIcon} viewBox="0 0 28 28" fill="none" aria-hidden="true">
      {kind === "text" ? (
        <path d="M4 7h19M4 12h13M4 17h19M4 22h9" />
      ) : kind === "folder" ? (
        <path d="M3 8a2 2 0 0 1 2-2h6l3 3h9a2 2 0 0 1 2 2v11H3V8Z" />
      ) : (
        <>
          <path d="M7 3h10l6 6v16H7V3Z" />
          <path d="M17 3v6h6M11 14h8M11 18h8M11 22h5" />
        </>
      )}
    </svg>
  );
}

function ShelfWindow({
  mode = "menuBar",
  empty = false,
  emphasizeSource = false,
  language = "en",
  items,
}: {
  mode?: ShelfMode;
  empty?: boolean;
  emphasizeSource?: boolean;
  language?: SiteLanguage;
  items?: readonly PreviewItem[];
}) {
  const copy = siteCopy[language].preview;
  const shelfItems = items ?? copy.sampleItems;
  const hasItems = !empty && shelfItems.length > 0;
  return (
    <div className={`${styles.shelf} ${mode === "notch" ? styles.notchShelf : ""}`} data-shelf-mode={mode} data-shelf-state={empty ? "empty" : "items"} lang={language}>
      {mode === "notch" ? <div className={styles.notchCutout} aria-hidden="true" /> : null}
      <div className={styles.shelfHeader}>
        <Image src="/cc/cc-mark.svg" width={30} height={26} alt="cc:" unoptimized className={styles.mark} />
        <span className={styles.itemCount} aria-live="polite">{empty ? copy.emptyCount : copy.count}</span>
        <span className={`${styles.windowControl} ${styles.windowSettings}`} aria-hidden="true">
          <svg viewBox="0 0 24 24" fill="none">
            <path d="M10 2h4l1 3 2 1 3-1 2 3-2 2v4l2 2-2 3-3-1-2 1-1 3h-4l-1-3-2-1-3 1-2-3 2-2v-4L2 8l2-3 3 1 2-1 1-3Z" />
            <circle cx="12" cy="12" r="3.5" />
          </svg>
        </span>
      </div>
      {empty ? (
        <div className={styles.emptyShelf}><p>{copy.emptyMessage}</p></div>
      ) : (
        <ul className={styles.itemList} role="list">
          {shelfItems.map((item) => (
            <li className={styles.itemRow} key={item.title}>
              <ItemIcon kind={item.kind} />
              <div className={styles.itemCopy}>
                <p className={styles.itemTitle}>{item.title}</p>
                <p className={styles.itemDetail}>
                  <span className={emphasizeSource ? styles.sourceEmphasis : undefined}>{item.source}</span>
                  <span className={styles.detailSeparator}> · </span>{item.note}
                </p>
              </div>
              <span className={styles.itemMenu} aria-hidden="true">{copy.details}</span>
            </li>
          ))}
        </ul>
      )}
      <div className={styles.shelfFooter}>
        <span className={styles.footerPrimary}>
          <span>{copy.addFiles}</span><span>{copy.paste}</span>
        </span>
        {hasItems ? (
          <span className={styles.footerActions}>
            <span className={styles.dragLabel}>{copy.dragFiles}</span>
            <span className={styles.clearAllLabel}>{copy.clearAll}</span>
          </span>
        ) : null}
      </div>
    </div>
  );
}

function PreviewScene({ variant, language }: { variant: Exclude<ShelfPreviewVariant, "interactive">; language: SiteLanguage }) {
  const copy = siteCopy[language].preview;
  return (
    <div className={`${styles.featureScene} ${variant === "notch" ? styles.notchScene : ""}`} data-preview-variant={variant} lang={language}>
      {variant === "files" ? (
        <>
          <div className={styles.finderSelection}>
            <p className={styles.sceneLabel}>{copy.finderSelection}</p>
            <div className={styles.selectedFiles}>
              <span><ItemIcon kind="file" />{copy.referenceItems[2].title}</span>
              <span><ItemIcon kind="file" />{copy.referenceItems[1].title}</span>
            </div>
          </div>
          <div className={styles.flowCue}><span aria-hidden="true">↓</span><kbd>⌥ Tab</kbd></div>
        </>
      ) : variant === "handoff" ? (
        <div className={styles.sources} aria-label={copy.sourceLabel}>
          {copy.sources.map((source) => <span key={source}>{source}</span>)}
        </div>
      ) : null}
      <ShelfWindow mode={variant === "notch" ? "notch" : "menuBar"} emphasizeSource={variant === "handoff"} language={language} items={variant === "files" ? copy.referenceItems : variant === "handoff" ? copy.receivedItems : undefined} />
      <p className={styles.sceneNote}>{variant === "files" ? copy.filesNote : variant === "handoff" ? copy.handoffNote : copy.notchNote}</p>
    </div>
  );
}

export default function ShelfPreview({ variant = "interactive", language = "en" }: { variant?: ShelfPreviewVariant; language?: SiteLanguage }) {
  const copy = siteCopy[language].preview;
  const [mode, setMode] = useState<ShelfMode>("menuBar");
  const [light, setLight] = useState(false);
  const [empty, setEmpty] = useState(false);

  if (variant !== "interactive") return <PreviewScene variant={variant} language={language} />;

  return (
    <div className={styles.preview} data-preview-variant="interactive" lang={language}>
      <div className={styles.previewTop}>
        <div className={styles.segmented} role="group" aria-label={copy.location}>
          <button type="button" aria-pressed={mode === "menuBar"} onClick={() => setMode("menuBar")}>{copy.menuBar}</button>
          <button type="button" aria-pressed={mode === "notch"} onClick={() => setMode("notch")}>{copy.notch}</button>
        </div>
        {mode === "menuBar" ? (
          <button className={styles.quietButton} type="button" aria-pressed={light} onClick={() => setLight((value) => !value)}>{light ? copy.dark : copy.light}</button>
        ) : null}
      </div>
      <div className={`${styles.stage} ${mode === "menuBar" && light ? styles.light : ""}`}>
        <ShelfWindow mode={mode} empty={empty} language={language} />
      </div>
      <div className={styles.previewBottom}>
        <div className={styles.segmented} role="group" aria-label={copy.contents}>
          <button type="button" aria-pressed={!empty} onClick={() => setEmpty(false)}>{copy.items}</button>
          <button type="button" aria-pressed={empty} onClick={() => setEmpty(true)}>{copy.empty}</button>
        </div>
        <p className={styles.demoNote}>{copy.demoNote}</p>
      </div>
    </div>
  );
}
