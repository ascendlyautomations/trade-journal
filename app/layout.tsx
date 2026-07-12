import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { Analytics } from "@vercel/analytics/next";
import { SpeedInsights } from "@vercel/speed-insights/next";
import "./globals.css";
import BannedAccountShell from "./components/BannedAccountShell"
import OnboardingGateShell from "./components/OnboardingGateShell"
import ReferralPersistence from "./components/ReferralPersistence"
import SentryIdentifyUser from "./components/SentryIdentifyUser"
import ToastRoot from "./components/ToastRoot"
import { UploadProgressProvider } from "@/lib/uploadProgress/UploadProgressProvider"
import DemoAppShell from "./components/demo/DemoAppShell"
import AppChrome from "./components/AppChrome"
import MarketingNavbarRoot from "./components/MarketingNavbarRoot"
import CookieConsentBanner from "./components/CookieConsentBanner"
import ScrollLockRouteReset from "./components/ScrollLockRouteReset"
import SubscriptionGateShell from "./components/SubscriptionGateShell"
import FreePlanAccountSlotShell from "./components/FreePlanAccountSlotShell"
import { UserProfileProvider } from "@/lib/UserProfileProvider"
import { GettingStartedProgressProvider } from "@/lib/GettingStartedProgressProvider"
import {
  DEFAULT_OG_IMAGE_ALT,
  DEFAULT_OG_IMAGE_PATH,
  DEFAULT_SITE_DESCRIPTION,
  HOME_PAGE_TITLE,
  OG_IMAGE_HEIGHT,
  OG_IMAGE_WIDTH,
  SITE_KEYWORDS,
  SITE_NAME,
  SITE_URL,
  TWITTER_HANDLE,
} from "@/lib/site"
import JsonLd from "./components/JsonLd"
import { organizationJsonLd, websiteJsonLd } from "@/lib/structuredData"

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
  keywords: [...SITE_KEYWORDS],
  applicationName: SITE_NAME,
  authors: [{ name: SITE_NAME, url: SITE_URL }],
  creator: SITE_NAME,
  publisher: SITE_NAME,
  formatDetection: {
    email: false,
    address: false,
    telephone: false,
  },
  icons: {
    icon: [
      { url: "/favicon.ico" },
      { url: "/logo.png", type: "image/png", sizes: "512x512" },
    ],
    apple: [{ url: "/logo.png", sizes: "180x180", type: "image/png" }],
  },
  manifest: "/manifest.webmanifest",
  alternates: {
    canonical: "/",
  },
  openGraph: {
    type: "website",
    locale: "en_US",
    siteName: SITE_NAME,
    title: HOME_PAGE_TITLE,
    description: DEFAULT_SITE_DESCRIPTION,
    url: SITE_URL,
    images: [
      {
        url: DEFAULT_OG_IMAGE_PATH,
        width: OG_IMAGE_WIDTH,
        height: OG_IMAGE_HEIGHT,
        alt: DEFAULT_OG_IMAGE_ALT,
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    site: TWITTER_HANDLE,
    creator: TWITTER_HANDLE,
    title: HOME_PAGE_TITLE,
    description: DEFAULT_SITE_DESCRIPTION,
    images: [DEFAULT_OG_IMAGE_PATH],
  },
  ...(process.env.NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION
    ? {
        verification: {
          google: process.env.NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION,
        },
      }
    : {}),
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
        <JsonLd data={[organizationJsonLd(), websiteJsonLd()]} />
        <ScrollLockRouteReset />
        <ToastRoot>
          <UploadProgressProvider>
          <ReferralPersistence />
          <UserProfileProvider>
            <GettingStartedProgressProvider>
            <SentryIdentifyUser />
            <BannedAccountShell>
              <OnboardingGateShell>
                <DemoAppShell>
                  <SubscriptionGateShell>
                    <FreePlanAccountSlotShell>
                    <MarketingNavbarRoot />
                    <AppChrome>{children}</AppChrome>
                    <CookieConsentBanner />
                    </FreePlanAccountSlotShell>
                  </SubscriptionGateShell>
                </DemoAppShell>
              </OnboardingGateShell>
            </BannedAccountShell>
            </GettingStartedProgressProvider>
          </UserProfileProvider>
          </UploadProgressProvider>
        </ToastRoot>
        <Analytics />
        <SpeedInsights />
      </body>
    </html>
  );
}
