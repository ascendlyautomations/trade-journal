import assert from "node:assert/strict"
import test from "node:test"
import vm from "node:vm"
import {
  appearanceForPath,
  parseWebAppearance,
  shouldApplyWebAppearance,
  webAppearanceBootScript,
} from "./webAppearance.ts"

test("default appearance is dark", () => {
  assert.equal(parseWebAppearance(null), "dark")
  assert.equal(parseWebAppearance(undefined), "dark")
  assert.equal(parseWebAppearance(""), "dark")
  assert.equal(appearanceForPath("/dashboard", null), "dark")
})

test("stored light and OG are preserved", () => {
  assert.equal(parseWebAppearance("light"), "light")
  assert.equal(parseWebAppearance("og"), "og")
  assert.equal(appearanceForPath("/trades", "light"), "light")
  assert.equal(appearanceForPath("/settings", "og"), "og")
})

test("invalid preference falls back to dark", () => {
  assert.equal(parseWebAppearance("tradetraxs"), "dark")
  assert.equal(parseWebAppearance("LIGHT"), "dark")
  assert.equal(parseWebAppearance("legacy"), "dark")
  assert.equal(appearanceForPath("/feed", "nope"), "dark")
})

test("public, auth, and onboarding paths do not take an appearance", () => {
  for (const path of [
    "/",
    "/faq",
    "/pricing",
    "/about",
    "/login",
    "/login/forgot",
    "/reset-password",
    "/onboarding",
    "/choose-plan",
    "/finish-trial",
    "/privacy",
    "/terms",
    "/affiliate",
    "/contact",
    "/copyright",
    "/native",
    "/demo",
  ]) {
    assert.equal(shouldApplyWebAppearance(path), false, path)
    assert.equal(appearanceForPath(path, "light"), null, path)
  }
})

test("authenticated routes keep a stored appearance", () => {
  for (const path of [
    "/dashboard",
    "/trades",
    "/feed",
    "/messages",
    "/profile/abc",
    "/settings",
    "/affiliate/dashboard",
    "/calendar",
  ]) {
    assert.equal(shouldApplyWebAppearance(path), true, path)
  }
})

test("native shell never receives an appearance", () => {
  assert.equal(appearanceForPath("/dashboard", "light", { native: true }), null)
  assert.equal(appearanceForPath("/dashboard", "og", { native: true }), null)
})

function runBoot(pathname: string, stored: string | null, native = false) {
  const attrs = new Map<string, string>()
  const meta = {
    content: "#0b1f3a",
    setAttribute(key: string, value: string) {
      if (key === "content") this.content = value
    },
  }
  const context = {
    document: {
      documentElement: {
        classList: {
          contains: (name: string) => native && (name === "tt-native" || name === "tt-native-ios"),
        },
        setAttribute: (key: string, value: string) => attrs.set(key, value),
        removeAttribute: (key: string) => attrs.delete(key),
        getAttribute: (key: string) => attrs.get(key) ?? null,
      },
      querySelector: () => meta,
    },
    location: { pathname },
    localStorage: {
      getItem: () => stored,
    },
  }
  vm.createContext(context)
  vm.runInContext(webAppearanceBootScript(), context)
  return {
    appearance: context.document.documentElement.getAttribute("data-tt-appearance"),
    themeColor: meta.content,
  }
}

test("pre-hydration boot paints dark by default on authenticated routes", () => {
  const result = runBoot("/dashboard", null)
  assert.equal(result.appearance, "dark")
  assert.equal(result.themeColor, "#0d1117")
})

test("pre-hydration boot paints a stored light or OG preference", () => {
  assert.equal(runBoot("/trades", "light").appearance, "light")
  assert.equal(runBoot("/feed", "og").appearance, "og")
  assert.equal(runBoot("/messages", "light").themeColor, "#f6f8fa")
})

test("pre-hydration boot ignores an invalid preference", () => {
  assert.equal(runBoot("/profile/1", "legacy").appearance, "dark")
})

test("pre-hydration boot leaves public and auth pages unthemed", () => {
  assert.equal(runBoot("/", "light").appearance, null)
  assert.equal(runBoot("/login", "og").appearance, null)
  assert.equal(runBoot("/onboarding", "light").appearance, null)
  assert.equal(runBoot("/", "dark").themeColor, "#0b1f3a")
})

test("pre-hydration boot skips the native shell", () => {
  assert.equal(runBoot("/dashboard", "light", true).appearance, null)
})

test("appearance switching is a stored value change", () => {
  assert.equal(appearanceForPath("/settings", "dark"), "dark")
  assert.equal(appearanceForPath("/settings", "light"), "light")
  assert.equal(appearanceForPath("/settings", "og"), "og")
  assert.equal(appearanceForPath("/settings", "dark"), "dark")
})
