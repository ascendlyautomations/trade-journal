import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import BannedAccountShell from "./components/BannedAccountShell"
import ToastRoot from "./components/ToastRoot"
import { UserProfileProvider } from "@/lib/UserProfileProvider"

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
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="flex flex-col">
        <ToastRoot>
          <UserProfileProvider>
            <BannedAccountShell>
              {/* pt-16: fixed Navbar offset (AppShell + page-level). Login uses -mt-16. */}
              <div className="w-full flex flex-col pt-16">
                {children}
              </div>
            </BannedAccountShell>
          </UserProfileProvider>
        </ToastRoot>
      </body>
    </html>
  );
}
