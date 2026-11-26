import { Suspense } from "react"
import type { ReactNode } from "react"
import "./globals.css"
import "./components/mobile/mobileWebTouch.css"
import "./authenticatedAppearance.css"
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
import MobileWebOpenAppBanner from "./components/MobileWebOpenAppBanner"
import ScrollLockRouteReset from "./components/ScrollLockRouteReset"
import MobileWebOfflineIndicator from "./components/mobile/MobileWebOfflineIndicator"
import MobileWebTouchRoot from "./components/mobile/MobileWebTouchRoot"
import SubscriptionGateShell from "./components/SubscriptionGateShell"
import FreePlanAccountSlotShell from "./components/FreePlanAccountSlotShell"
import { UserProfileProvider } from "@/lib/UserProfileProvider"
import { BillingEntitlementProvider } from "@/app/components/monetization/BillingEntitlementProvider"
import { TraxProPriceCatalogProvider } from "@/app/components/monetization/TraxProPriceCatalogProvider"
import { ProUpgradeProvider } from "@/app/components/monetization/ProUpgradeProvider"
import { GettingStartedProgressProvider } from "@/lib/GettingStartedProgressProvider"
import { VaultProvider } from "@/lib/vault/VaultProvider"
import BrokerImportedTradesRealtimeBridge from "./components/BrokerImportedTradesRealtimeBridge"
import BrokerEnrichmentBridge from "./components/BrokerEnrichmentBridge"
import BrokerTradovateLoginImportGate from "./components/BrokerTradovateLoginImportGate"
import NativeAppShell from "./components/NativeAppShell"
import NativeHomeRedirect from "./components/NativeHomeRedirect"
import NativeSessionPersistence from "./components/NativeSessionPersistence"
import NativeSilentCacheBootstrap from "./components/NativeSilentCacheBootstrap"
import NativeAwareVercelInsights from "./components/NativeAwareVercelInsights"
import MessagingInAppBanner from "./components/MessagingInAppBanner"
import { isNativeIosShellRequest } from "@/lib/nativeRequest"
import JsonLd from "./components/JsonLd"
import { organizationJsonLd, websiteJsonLd } from "@/lib/structuredData"
import { DEFAULT_WEB_THEME } from "@/lib/webTheme"
import { webAppearanceBootScript } from "@/lib/webAppearance"
import WebAppearanceController from "./components/WebAppearanceController"
import ContextualTourRoot from "./components/contextualTour/ContextualTourRoot"
import ProductAnalyticsBridge from "./components/ProductAnalyticsBridge"
import { rootDocumentFonts, rootHtmlClassName } from "./rootDocument"

export default async function AppRootLayout({
  children,
}: Readonly<{
  children: ReactNode
}>) {
  const nativeIos = await isNativeIosShellRequest()
  const htmlClassName = rootHtmlClassName(nativeIos)

  return (
    <html
      lang="en"
      className={htmlClassName}
      data-theme={DEFAULT_WEB_THEME}
      suppressHydrationWarning
    >
      <head>
        <script dangerouslySetInnerHTML={{ __html: webAppearanceBootScript() }} />
      </head>
      <body className={`${rootDocumentFonts.bodyClassName} flex flex-col`}>
        <MobileWebOpenAppBanner />
        <WebAppearanceController />
        <JsonLd data={[organizationJsonLd(), websiteJsonLd()]} />
        <ScrollLockRouteReset />
        <MobileWebTouchRoot />
        <MobileWebOfflineIndicator />
        <ToastRoot>
          <UploadProgressProvider>
            <ReferralPersistence />
            <UserProfileProvider>
              <BillingEntitlementProvider>
                <TraxProPriceCatalogProvider>
                  <ProUpgradeProvider>
                    <GettingStartedProgressProvider>
                      <VaultProvider>
                        <BrokerImportedTradesRealtimeBridge />
                        <BrokerEnrichmentBridge />
                        <BrokerTradovateLoginImportGate />
                        <NativeAppShell />
                        <NativeSilentCacheBootstrap />
                        <MessagingInAppBanner />
                        <NativeHomeRedirect />
                        <Suspense fallback={null}>
                          <NativeSessionPersistence />
                        </Suspense>
                        <SentryIdentifyUser />
                        <ProductAnalyticsBridge />
                        <BannedAccountShell>
                          <OnboardingGateShell>
                            <ContextualTourRoot>
                              <DemoAppShell>
                                <SubscriptionGateShell>
                                  <FreePlanAccountSlotShell>
                                    <MarketingNavbarRoot />
                                    <AppChrome>{children}</AppChrome>
                                    <CookieConsentBanner />
                                  </FreePlanAccountSlotShell>
                                </SubscriptionGateShell>
                              </DemoAppShell>
                            </ContextualTourRoot>
                          </OnboardingGateShell>
                        </BannedAccountShell>
                      </VaultProvider>
                    </GettingStartedProgressProvider>
                  </ProUpgradeProvider>
                </TraxProPriceCatalogProvider>
              </BillingEntitlementProvider>
            </UserProfileProvider>
          </UploadProgressProvider>
        </ToastRoot>
        <NativeAwareVercelInsights />
      </body>
    </html>
  )
}