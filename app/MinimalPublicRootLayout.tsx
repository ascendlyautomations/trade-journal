import type { ReactNode } from "react"
import "./globals.css"
import { DEFAULT_WEB_THEME } from "@/lib/webTheme"
import { webAppearanceBootScript } from "@/lib/webAppearance"
import { rootDocumentFonts } from "./rootDocument"

/**
 * Minimal document shell for public routes that must SSR without the authenticated
 * app provider tree (e.g. /download for link-preview crawlers).
 */
export default function MinimalPublicRootLayout({
  children,
}: Readonly<{
  children: ReactNode
}>) {
  return (
    <html
      lang="en"
      className={rootDocumentFonts.bodyClassName}
      data-theme={DEFAULT_WEB_THEME}
      suppressHydrationWarning
    >
      <head>
        <script dangerouslySetInnerHTML={{ __html: webAppearanceBootScript() }} />
      </head>
      <body className={`${rootDocumentFonts.bodyClassName} min-h-full`}>
        {children}
      </body>
    </html>
  )
}