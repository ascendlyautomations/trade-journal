# TradeTraxs Native iOS

This directory is the home of the **true native iOS application** foundation.

It is **not** the Capacitor / WKWebView shell under `/ios`.

| Path | What it is |
|------|------------|
| `/ios` | Legacy Capacitor host (web app in WebView) — do not extend for the native rebuild |
| `/native-ios` | Native Swift application architecture, docs, and (later) Xcode project sources |

## Xcode project (open this)

**Canonical path:** `native-ios/TradeTraxs/TradeTraxs.xcodeproj`

A symlink also exists at `native-ios/TradeTraxs.xcodeproj` → the same project.

Use the **TradeTraxs** shared scheme (main app). Do not run the widget scheme for day-to-day development.

## Current status

Foundation phase only:

- [`ARCHITECTURE.md`](./ARCHITECTURE.md) — permanent source of truth for how this app is built
- Native Swift app under `TradeTraxs/` (LiveKit voice, livestream viewing, Live Activity widget extension)

## Next steps (after architecture sign-off)

1. Create the Xcode project / SPM package layout matching `ARCHITECTURE.md`
2. Wire Auth + App shell (tabs) with empty placeholders
3. Implement repositories against existing Supabase + BFF contracts
4. Build features in the order defined in the architecture roadmap section

## Backend reuse

The native app reuses the existing platform:

- Supabase (Auth, Postgres/RLS, Realtime, Storage)
- Selected Next.js API routes (Bearer JWT) for privileged operations
- Existing RPCs and business rules

The web application remains a separate frontend.
