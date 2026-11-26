import { Geist, Geist_Mono } from "next/font/google"

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
})

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
})

export const rootDocumentFonts = {
  bodyClassName: `${geistSans.variable} ${geistMono.variable} h-full antialiased`,
}

export function rootHtmlClassName(nativeIos: boolean): string {
  return [
    geistSans.variable,
    geistMono.variable,
    "h-full antialiased",
    nativeIos ? "tt-native tt-native-ios" : "",
  ]
    .filter(Boolean)
    .join(" ")
}