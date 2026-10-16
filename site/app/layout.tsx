import type { Metadata } from "next";

import "./globals.css";

const title = "cc:";
const description =
  "Gather files, links, and long notes for your agent. Ask it to leave its work on the same shelf.";

export const metadata: Metadata = {
  metadataBase: new URL("https://cc.hayashiii-gpt.chatgpt.site"),
  title,
  description,
  icons: {
    icon: [{ url: "/cc/cc-favicon.svg", type: "image/svg+xml" }],
    shortcut: ["/cc/cc-favicon.svg"],
  },
  openGraph: {
    title,
    description,
    type: "website",
    url: "/",
    images: [
      {
        url: "/cc/cc-og.png?v=0.4.4",
        width: 1200,
        height: 630,
        alt: title,
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title,
    description,
    images: [
      {
        url: "/cc/cc-og.png?v=0.4.4",
        alt: title,
      },
    ],
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
