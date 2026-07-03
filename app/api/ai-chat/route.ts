import { NextResponse } from "next/server"

/** Unused endpoint — disabled to prevent OpenAI cost abuse. */
export async function POST() {
  return NextResponse.json({ error: "Not found" }, { status: 404 })
}
