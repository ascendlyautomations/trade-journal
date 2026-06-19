import type { Metadata } from "next";
import { Suspense } from "react";
import { Geist, Geist_Mono } from "next/font/google";
import { Analytics } from "@vercel/analytics/next";
import { SpeedInsights } from "@vercel/speed-insights/next";
import "./globals.css";
import BannedAccountShell from "./components/BannedAccountShell"
import OnboardingGateShell from "./components/OnboardingGateShell"
import ReferralPersistence from "./components/ReferralPersistence"
import SentryIdentifyUser from "./components/SentryIdentifyUser"
import ToastRoot from "./components/ToastRoot"
import { UserProfileProvider } from "@/lib/UserProfileProvider"
import { GettingStartedProgressProvider } from "@/lib/GettingStartedProgressProvider"
import {
  DEFAULT_OG_IMAGE_PATH,
  DEFAULT_SITE_DESCRIPTION,
  SITE_NAME,
  SITE_URL,
} from "@/lib/site"

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: SITE_NAME,
    template: `%s | ${SITE_NAME}`,
  },
  description: DEFAULT_SITE_DESCRIPTION,
  openGraph: {
    type: "website",
    locale: "en_US",
    siteName: SITE_NAME,
    title: SITE_NAME,
    description: DEFAULT_SITE_DESCRIPTION,
    url: SITE_URL,
    images: [
      {
        url: DEFAULT_OG_IMAGE_PATH,
        alt: SITE_NAME,
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: SITE_NAME,
    description: DEFAULT_SITE_DESCRIPTION,
    images: [DEFAULT_OG_IMAGE_PATH],
  },
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
            <Suspense fallback={null}>
              <ReferralPersistence />
            </Suspense>
            <GettingStartedProgressProvider>
            <SentryIdentifyUser />
            <BannedAccountShell>
              <OnboardingGateShell>
                {/* pt-16: fixed Navbar offset (AppShell + page-level). Login/onboarding use -mt-16. */}
                <div className="w-full flex flex-col pt-16">
                  {children}
                </div>
              </OnboardingGateShell>
            </BannedAccountShell>
            </GettingStartedProgressProvider>
          </UserProfileProvider>
        </ToastRoot>
        <Analytics />
        <SpeedInsights />
      </body>
    </html>
  );
}
