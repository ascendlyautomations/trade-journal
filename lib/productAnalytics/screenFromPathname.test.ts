import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { screenIdFromPathname } from "./screenFromPathname.ts"
import { PRODUCT_ANALYTICS_SCREENS } from "./constants.ts"

describe("screenIdFromPathname", () => {
  it("maps core app routes", () => {
    assert.equal(screenIdFromPathname("/dashboard"), PRODUCT_ANALYTICS_SCREENS.dashboard)
    assert.equal(screenIdFromPathname("/feed"), PRODUCT_ANALYTICS_SCREENS.feed)
    assert.equal(screenIdFromPathname("/profile/11111111-1111-1111-1111-111111111111"), PRODUCT_ANALYTICS_SCREENS.profileOther)
  })
})