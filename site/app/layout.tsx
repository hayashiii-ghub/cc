import type { Metadata } from "next";

import "./globals.css";

const title = "cc: · A copy for what’s next.";
const description =
  "Files, links, and notes. Ready for your next app or agent.";

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
        url: "/cc/cc-og.png",
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
        url: "/cc/cc-og.png",
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
