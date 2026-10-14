"use client";

import Image from "next/image";
import { useEffect, useSyncExternalStore } from "react";

import styles from "./cc.module.css";
import ShelfPreview from "./ShelfPreview";
import { siteCopy, siteLanguageStorageKey, type SiteLanguage } from "./copy";

const repositoryUrl = "https://github.com/hayashiii-ghub/cc";
const releasesUrl = `${repositoryUrl}/releases`;
const downloadUrl = `${repositoryUrl}/releases/latest/download/cc-macos.dmg`;

const languageEvent = "cc-language-change";
// Keep the choice for this tab when browser storage is unavailable.
let temporaryLanguage: SiteLanguage | undefined;

function browserLanguage(): SiteLanguage {
  return (navigator.languages[0] || navigator.language).toLowerCase().startsWith("ja") ? "ja" : "en";
}

function currentLanguage(): SiteLanguage {
  if (temporaryLanguage) return temporaryLanguage;
  try {
    const stored = localStorage.getItem(siteLanguageStorageKey);
    if (stored === "en" || stored === "ja") return stored;
  } catch {
    return browserLanguage();
  }
  return browserLanguage();
}

function subscribeLanguage(notify: () => void) {
  const onStorage = (event: StorageEvent) => {
    if (event.key === siteLanguageStorageKey || event.key === null) notify();
  };
  window.addEventListener(languageEvent, notify);
  window.addEventListener("storage", onStorage);
  return () => {
    window.removeEventListener(languageEvent, notify);
    window.removeEventListener("storage", onStorage);
  };
}

function chooseLanguage(language: SiteLanguage) {
  try {
    localStorage.setItem(siteLanguageStorageKey, language);
    temporaryLanguage = undefined;
  } catch {
    temporaryLanguage = language;
  }
  window.dispatchEvent(new Event(languageEvent));
}

export default function CCPage() {
  const language = useSyncExternalStore(subscribeLanguage, currentLanguage, () => "en" as SiteLanguage);
  const copy = siteCopy[language];

  useEffect(() => {
    document.documentElement.lang = language;
    document.title = copy.meta.title;
    const metadata = [
      ['meta[name="description"]', copy.meta.description],
      ['meta[property="og:title"]', copy.meta.title],
      ['meta[property="og:description"]', copy.meta.description],
      ['meta[property="og:image:alt"]', copy.meta.imageAlt],
      ['meta[name="twitter:title"]', copy.meta.title],
      ['meta[name="twitter:description"]', copy.meta.description],
      ['meta[name="twitter:image:alt"]', copy.meta.imageAlt],
    ];
    for (const [selector, value] of metadata) {
      document.querySelector(selector)?.setAttribute("content", value);
    }
  }, [language, copy.meta]);

  return (
    <div className={styles.page} lang={language}>
      <a className={styles.skipLink} href="#content">{copy.skip}</a>

      <nav className={styles.navPill} aria-label={copy.primary}>
        <a className={styles.brand} href="#top">
          <Image src="/cc/cc-mark.svg" width={30} height={24} alt={copy.home} unoptimized />
        </a>
        <a className={styles.navHow} href="#how">{copy.navHow}</a>
        <a href="#install">{copy.navInstall}</a>
        <a href={repositoryUrl}>GitHub</a>
        <div className={styles.languageSwitch} role="group" aria-label={copy.languageLabel}>
          <button className={styles.languageButton} type="button" lang="ja" aria-label="日本語" aria-pressed={language === "ja"} onClick={() => chooseLanguage("ja")}>JA</button>
          <button className={styles.languageButton} type="button" lang="en" aria-label="English" aria-pressed={language === "en"} onClick={() => chooseLanguage("en")}>EN</button>
        </div>
      </nav>

      <main id="content">
        <section className={styles.hero} id="top" aria-labelledby="cc-title">
          <a className={styles.releaseChip} href={repositoryUrl}>
            <span>{copy.openSource}</span>
            <span>{copy.builtForMac}</span>
          </a>
          <h1 id="cc-title">{copy.heroTitle[0]}<br /><span>{copy.heroTitle[1]}</span></h1>
          <p className={styles.heroSubtitle}>
            {copy.heroSubtitle[0]}<br className={styles.desktopBreak} /> {copy.heroSubtitle[1]}
          </p>
          <div className={styles.heroActions}>
            <a className={`${styles.button} ${styles.buttonPrimary}`} href="#install">{copy.downloadForMac}</a>
            <a className={`${styles.button} ${styles.buttonSecondary}`} href={repositoryUrl}>{copy.viewOnGitHub}</a>
          </div>
          <p className={styles.heroMeta}>{copy.heroMeta}</p>
        </section>

        <section className={styles.showcaseSection} aria-label={copy.showcaseLabel}>
          <div className={styles.showcaseFrame}><ShelfPreview language={language} /></div>
          <p className={styles.shelfTypes}>{copy.shelfTypes.join(" · ")}</p>
        </section>

        <section className={`${styles.section} ${styles.features}`} id="how" aria-label={copy.howLabel}>
          {copy.features.map((feature, index) => (
            <article className={`${styles.featureRow} ${index % 2 ? styles.flip : ""}`} key={feature.id}>
              <div className={styles.featureCopy}>
                <p className={styles.eyebrow}>— {feature.index}</p>
                <h2>{feature.title}</h2>
                <p>{feature.body}</p>
                <p className={styles.featureNote}>{feature.note}</p>
              </div>
              <div className={styles.featureVisual}>
                <ShelfPreview variant={feature.preview} language={language} />
              </div>
            </article>
          ))}
        </section>

        <section className={`${styles.section} ${styles.privacy}`} aria-labelledby="privacy-title">
          <div className={styles.sectionNarrow}>
            <p className={styles.eyebrow}>{copy.privacyEyebrow}</p>
            <h2 id="privacy-title">{copy.privacyTitle}</h2>
            <ul className={styles.privacyMarks} aria-label={copy.privacyLabel}>
              {copy.privacyMarks.map((mark) => <li key={mark}>{mark}</li>)}
            </ul>
            <p className={styles.centerCopy}>
              {copy.privacyBody}
            </p>
          </div>
        </section>

        <section className={`${styles.section} ${styles.installSection}`} id="install" aria-labelledby="install-title">
          <div className={styles.sectionNarrow}>
            <p className={styles.eyebrow}>{copy.installEyebrow}</p>
            <h2 id="install-title">{copy.installTitle}</h2>
            <p className={styles.centerCopy}>{copy.installBody}</p>
            <div className={styles.installBar}>
              <div className={styles.installName}>
                <Image src="/cc/cc-mark.svg" width={40} height={40} alt={copy.markAlt} unoptimized />
                <span>{copy.installName}</span>
              </div>
              <a className={`${styles.button} ${styles.buttonPrimary}`} href={downloadUrl}>{copy.downloadDmg}</a>
            </div>
            <p className={styles.installMeta}>{copy.installMeta}</p>
            <p className={styles.installNote}>
              {copy.installNote}
            </p>
          </div>
        </section>

        <section className={`${styles.section} ${styles.faq}`} aria-labelledby="faq-title">
          <div className={styles.sectionNarrow}>
            <p className={styles.eyebrow}>{copy.faqEyebrow}</p>
            <h2 id="faq-title">{copy.faqTitle}</h2>
            <div className={styles.faqList}>
              {copy.faqs.map(({ id, question, answer }) => (
                <details className={styles.faqItem} key={id}>
                  <summary>{question}</summary>
                  <p>{answer}</p>
                </details>
              ))}
            </div>
          </div>
        </section>

        <section className={styles.finalCta} aria-labelledby="final-title">
          <h2 id="final-title">{copy.finalTitle}</h2>
          <div className={styles.heroActions}>
            <a className={`${styles.button} ${styles.buttonPrimary}`} href={downloadUrl}>{copy.downloadForMac}</a>
            <a className={`${styles.button} ${styles.buttonSecondary}`} href={repositoryUrl}>{copy.viewOnGitHub}</a>
          </div>
        </section>
      </main>

      <footer className={styles.footer}>
        <div className={styles.footerMeta}>
          <Image src="/cc/cc-mark.svg" width={30} height={24} alt="cc:" unoptimized />
          <span className={styles.dot} /><span>{copy.openSource}</span>
        </div>
        <div className={styles.footerLinks}>
          <a href={repositoryUrl}>GitHub</a>
          <a href={releasesUrl}>{copy.releases}</a>
          <a href={`${repositoryUrl}/issues`}>{copy.issues}</a>
        </div>
      </footer>
    </div>
  );
}
