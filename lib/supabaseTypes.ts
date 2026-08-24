import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "./database.types"

export type { Database, Json } from "./database.types"

/** Browser, server, and route-handler Supabase clients for this app. */
export type AppSupabaseClient = SupabaseClient<Database>

export type PublicTables = Database["public"]["Tables"]
export type PublicViews = Database["public"]["Views"]
export type PublicFunctions = Database["public"]["Functions"]

export type TableRow<T extends keyof PublicTables> = PublicTables[T]["Row"]
export type TableInsert<T extends keyof PublicTables> = PublicTables[T]["Insert"]
export type TableUpdate<T extends keyof PublicTables> = PublicTables[T]["Update"]

export type ProfileRow = TableRow<"profiles">
export type TradeRow = TableRow<"trades">
export type ReelRow = TableRow<"reels">
