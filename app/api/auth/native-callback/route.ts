import { NextRequest } from "next/server"
import { NATIVE_IOS_OAUTH_CALLBACK } from "@/lib/nativeIosOAuthUrls"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

/**
 * Production HTTPS → custom-scheme bridge for Capacitor iOS OAuth (PKCE).
 *
 * Supabase redirects here after Google:
 *   https://www.tradetraxs.com/api/auth/native-callback?code=…&state=…
 *
 * This route immediately hands off to:
 *   com.tradetraxs.ios://auth/callback?code=…&state=…
 *
 * Query params (code, state, error, …) are preserved verbatim.
 * Uses HTML + JS navigation — NextResponse.redirect rejects custom schemes,
 * and SFSafariViewController is unreliable with a raw 302 to a custom scheme.
 */
export async function GET(request: NextRequest) {
  const incoming = new URL(request.url)
  const deepLink = new URL(NATIVE_IOS_OAUTH_CALLBACK)

  // Preserve every query param Supabase appends (code, state, error, …).
  incoming.searchParams.forEach((value, key) => {
    deepLink.searchParams.set(key, value)
  })

  const target = deepLink.toString()
  const safeAttr = escapeHtmlAttr(target)
  const safeJs = JSON.stringify(target)

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta http-equiv="refresh" content="0;url=${safeAttr}" />
  <title>Returning to TradeTraxs…</title>
  <script>
    (function () {
      var target = ${safeJs};
      function go() {
        try { location.replace(target); } catch (e) { location.href = target; }
      }
      go();
      setTimeout(go, 250);
      setTimeout(go, 800);
    })();
  </script>
</head>
<body style="margin:0;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px;background:#0b1f3a;color:#e8eef5;font-family:system-ui,-apple-system,sans-serif;">
  <p style="margin:0;font-size:14px;opacity:.85;">Returning to TradeTraxs…</p>
  <a href="${safeAttr}" style="color:#7dd3fc;font-size:14px;">Tap here if the app does not open</a>
</body>
</html>`

  return new Response(html, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
    },
  })
}

function escapeHtmlAttr(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
}
