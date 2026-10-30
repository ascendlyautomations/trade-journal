import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  isSupabaseRequestUrl,
  sanitizeSentrySpanForSupabase,
  sanitizeSupabaseUrl,
  supabaseQueryFingerprint,
  supabaseSpanAttributesFromResponse,
} from "./supabaseHttpTelemetry.ts"

const POSTS =
  "https://fobudrkniacatvilbofw.supabase.co/rest/v1/posts?select=id%2Cuser_id%2Cprofiles%21inner%28username%29&trades.is_public=eq.true&created_at=gte.2025-10-27T00%3A00%3A00.000Z&order=created_at.desc&limit=400&id=eq.e432738b-47bd-439b-a669-c71082202895"

describe("supabase HTTP telemetry", () => {
  it("fingerprints select/limit/order and redacts ids", () => {
    const url = new URL(POSTS)
    const fingerprint = supabaseQueryFingerprint(url.searchParams, url.pathname)
    assert.match(fingerprint, /select=id,user_id,profiles!inner\(username\)/)
    assert.match(fingerprint, /limit=400/)
    assert.match(fingerprint, /order=created_at\.desc/)
    assert.match(fingerprint, /id=eq\.<id>/)
    assert.doesNotMatch(fingerprint, /e432738b/)
    assert.match(fingerprint, /trades\.is_public=eq\.true/)
    assert.match(fingerprint, /created_at=gte\.2025-10-27/)
  })

  it("drops auth tokens and auth-query strings", () => {
    const auth =
      "https://fobudrkniacatvilbofw.supabase.co/auth/v1/token?grant_type=refresh_token&refresh_token=secret"
    const sanitized = sanitizeSupabaseUrl(auth)
    assert.equal(
      sanitized,
      "https://fobudrkniacatvilbofw.supabase.co/auth/v1/token"
    )
    const rest = new URL(
      "https://x.supabase.co/rest/v1/profiles?apikey=secret&id=eq.1"
    )
    const fingerprint = supabaseQueryFingerprint(rest.searchParams, rest.pathname)
    assert.doesNotMatch(fingerprint, /apikey/)
    assert.doesNotMatch(fingerprint, /secret/)
  })

  it("copies safe gateway headers and skips authorization", () => {
    const headers = new Headers({
      "x-envoy-upstream-service-time": "31",
      "cf-ray": "a524328d1d35c953-IAD",
      "content-range": "0-37/*",
      authorization: "Bearer secret",
    })
    const attrs = supabaseSpanAttributesFromResponse(POSTS, headers)
    assert.equal(attrs["supabase.upstream_ms"], 31)
    assert.equal(attrs["supabase.cf_ray"], "a524328d1d35c953-IAD")
    assert.equal(attrs["supabase.content_range"], "0-37/*")
    assert.equal(attrs["url.path"], "/rest/v1/posts")
    assert.match(String(attrs["http.query"]), /limit=400/)
    assert.equal(attrs["authorization"], undefined)
  })

  it("records rpc name for review spans", () => {
    const attrs = supabaseSpanAttributesFromResponse(
      "https://x.supabase.co/rest/v1/rpc/list_public_user_reviews",
      new Headers({ "x-envoy-upstream-service-time": "12" })
    )
    assert.equal(attrs["supabase.rpc"], "list_public_user_reviews")
    assert.equal(attrs["supabase.upstream_ms"], 12)
  })

  it("sanitizes Sentry span urls and strips auth headers", () => {
    const span = sanitizeSentrySpanForSupabase({
      op: "http.client",
      description: `GET ${POSTS}`,
      data: {
        "http.url": POSTS,
        "url.full": POSTS,
        "http.request.header.authorization": "Bearer secret",
        "http.request.header.apikey": "anon",
        "http.response.status_code": 200,
      },
    })
    assert.doesNotMatch(span.description ?? "", /e432738b/)
    assert.doesNotMatch(String(span.data?.["http.url"]), /e432738b/)
    assert.equal(span.data?.["http.request.header.authorization"], undefined)
    assert.equal(span.data?.["http.request.header.apikey"], undefined)
    assert.equal(span.data?.["http.response.status_code"], 200)
    assert.match(String(span.data?.["http.url"]), /limit=400/)
  })

  it("ignores non-supabase urls", () => {
    assert.equal(isSupabaseRequestUrl("https://example.com/rest/v1/posts"), false)
    const raw = "https://example.com/rest/v1/posts?id=eq.secret"
    assert.equal(sanitizeSupabaseUrl(raw), raw)
  })
})
