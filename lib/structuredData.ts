import { TRADETRAXS_FAQ_ITEMS, type FaqItem } from "@/lib/faqContent"
import {
  DEFAULT_OG_IMAGE_PATH,
  DEFAULT_SITE_DESCRIPTION,
  HOME_PAGE_TITLE,
  SITE_NAME,
  SITE_URL,
} from "@/lib/site"
import {
  TRADETRAXS_FREE_PLAN,
  TRADETRAXS_PRO_PLAN,
} from "@/lib/tradeTraxsPlans"

const ORG_ID = `${SITE_URL}/#organization`
const WEBSITE_ID = `${SITE_URL}/#website`
const SOFTWARE_ID = `${SITE_URL}/#software`

export function organizationJsonLd() {
  return {
    "@context": "https://schema.org",
    "@type": "Organization",
    "@id": ORG_ID,
    name: SITE_NAME,
    alternateName: ["Trade Traxs", "tradetraxs", "TradeTraxs App"],
    url: SITE_URL,
    logo: {
      "@type": "ImageObject",
      url: `${SITE_URL}/logo.png`,
    },
    image: `${SITE_URL}${DEFAULT_OG_IMAGE_PATH}`,
    description: DEFAULT_SITE_DESCRIPTION,
    sameAs: [] as string[],
  }
}

export function websiteJsonLd() {
  return {
    "@context": "https://schema.org",
    "@type": "WebSite",
    "@id": WEBSITE_ID,
    name: SITE_NAME,
    alternateName: ["Trade Traxs", "tradetraxs"],
    url: SITE_URL,
    description: DEFAULT_SITE_DESCRIPTION,
    publisher: { "@id": ORG_ID },
    inLanguage: "en-US",
  }
}

export function softwareApplicationJsonLd() {
  return {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    "@id": SOFTWARE_ID,
    name: SITE_NAME,
    alternateName: [
      "TradeTraxs Trading Journal",
      "TradeTraxs App",
      "Trade Traxs",
    ],
    applicationCategory: "FinanceApplication",
    applicationSubCategory: "Trading Journal Software",
    operatingSystem: "Web",
    url: SITE_URL,
    description:
      "TradeTraxs is AI-powered trading journal software for futures and active traders. Log trades, analyze performance, and connect with the trading community.",
    offers: [
      {
        "@type": "Offer",
        name: TRADETRAXS_FREE_PLAN.name,
        price: "0",
        priceCurrency: "USD",
        availability: "https://schema.org/OnlineOnly",
        url: `${SITE_URL}/pricing`,
        description: TRADETRAXS_FREE_PLAN.description,
      },
      {
        "@type": "Offer",
        name: TRADETRAXS_PRO_PLAN.name,
        price: "23.99",
        priceCurrency: "USD",
        availability: "https://schema.org/OnlineOnly",
        url: `${SITE_URL}/pricing`,
        description: TRADETRAXS_PRO_PLAN.description,
      },
    ],
    featureList: [
      "Trading journal",
      "AI trade analysis",
      "Futures trading journal",
      "Performance analytics",
      "CSV import",
      "Prop firm tracking",
      "Trading community",
      "Trade rooms",
    ],
    publisher: { "@id": ORG_ID },
    isPartOf: { "@id": WEBSITE_ID },
  }
}

export function faqPageJsonLd(items: FaqItem[] = TRADETRAXS_FAQ_ITEMS) {
  return {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: items.map((item) => ({
      "@type": "Question",
      name: item.question,
      acceptedAnswer: {
        "@type": "Answer",
        text: item.answer,
      },
    })),
  }
}

export type BreadcrumbItem = {
  name: string
  path: `/${string}` | "/"
}

export function breadcrumbJsonLd(items: BreadcrumbItem[]) {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: items.map((item, index) => ({
      "@type": "ListItem",
      position: index + 1,
      name: item.name,
      item: `${SITE_URL}${item.path === "/" ? "" : item.path}`,
    })),
  }
}

export function homePageJsonLd() {
  return [
    softwareApplicationJsonLd(),
    {
      "@context": "https://schema.org",
      "@type": "WebPage",
      "@id": `${SITE_URL}/#webpage`,
      url: SITE_URL,
      name: HOME_PAGE_TITLE,
      description: DEFAULT_SITE_DESCRIPTION,
      isPartOf: { "@id": WEBSITE_ID },
      about: { "@id": SOFTWARE_ID },
      inLanguage: "en-US",
    },
  ]
}
