import assert from "node:assert/strict"
import test from "node:test"
import { computeTextareaNewlineInsert } from "./insertTextareaNewline.ts"

test("computeTextareaNewlineInsert inserts at cursor", () => {
  assert.deepEqual(computeTextareaNewlineInsert("hello world", 5, 5), {
    value: "hello\n world",
    caret: 6,
  })
})

test("computeTextareaNewlineInsert replaces selection", () => {
  assert.deepEqual(computeTextareaNewlineInsert("hello world", 0, 5), {
    value: "\n world",
    caret: 1,
  })
})

test("computeTextareaNewlineInsert appends at end", () => {
  assert.deepEqual(computeTextareaNewlineInsert("line one", 8, 8), {
    value: "line one\n",
    caret: 9,
  })
})

test("computeTextareaNewlineInsert supports multiple newlines", () => {
  const first = computeTextareaNewlineInsert("abc", 3, 3)
  assert.equal(first.value, "abc\n")
  const second = computeTextareaNewlineInsert(first.value, first.caret, first.caret)
  assert.equal(second.value, "abc\n\n")
  assert.equal(second.caret, 5)
})
