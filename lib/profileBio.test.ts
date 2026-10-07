import assert from "node:assert/strict"
import test from "node:test"
import { constrainProfileBio } from "./profileBio.ts"

test("profile bio keeps at most three lines", () => {
  assert.equal(constrainProfileBio("one\ntwo"), "one\ntwo")
  assert.equal(constrainProfileBio("one\ntwo\nthree"), "one\ntwo\nthree")
  assert.equal(constrainProfileBio("one\ntwo\nthree\nfour"), "one\ntwo\nthree")
  assert.equal(constrainProfileBio("one\r\ntwo\r\nthree\r\nfour"), "one\ntwo\nthree")
  assert.equal(constrainProfileBio("one\ntwo\nthree\n"), "one\ntwo\nthree")
})
