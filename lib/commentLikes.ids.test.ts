import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { commentIdsForLikeQuery } from "./commentLikes.ts"

describe("commentIdsForLikeQuery", () => {
  it("drops optimistic ids that are not uuids", () => {
    const persisted = "f399c827-7c90-4d56-b760-55b5dd0aa501"
    assert.deepEqual(
      commentIdsForLikeQuery([
        "temp-c-1790370313360",
        persisted,
        "temp-c-" + persisted,
        "00000000-0000-4000-8000-00000000demo",
        "dt-24",
      ]),
      [persisted]
    )
  })

  it("returns an empty list when every id is optimistic", () => {
    assert.deepEqual(commentIdsForLikeQuery(["temp-c-1790370313360"]), [])
  })
})
