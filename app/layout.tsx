import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import BannedAccountShell from "./components/BannedAccountShell";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata = {
  title: {
    default: "TradeTraxs",
    template: "%s | TradeTraxs",
  },
  description: "Track your trades like a pro",
}
export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} h-full bg-[#0b1f3a] antialiased`}
    >
      <body className="flex min-h-screen min-h-full flex-col bg-[#0b1f3a]">
        <BannedAccountShell>
          <div className="flex min-h-screen flex-1 flex-col bg-[#0b1f3a] pt-16">
            {children}
          </div>
        </BannedAccountShell>
      </body>
    </html>
  );
}
