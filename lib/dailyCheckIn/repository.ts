import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import {
  TRADER_DAILY_CHECK_IN_CONFLICT,
  TRADER_DAILY_CHECK_IN_SELECT,
  TRADER_DAILY_CHECK_INS_TABLE,
} from "./constants.ts"
import type { TraderDailyCheckIn, TraderDailyCheckInDraft } from "./types.ts"
import { validateCheckInDraft } from "./validation.ts"

type CheckInRow =
  Database["public"]["Tables"]["trader_daily_check_ins"]["Row"]

function asFiniteNumber(value: unknown): number | null {
  if (value == null || value === "") return null
  const parsed = typeof value === "number" ? value : Number(value)
  return Number.isFinite(parsed) ? parsed : null
}

function asInt(value: unknown): number | null {
  const parsed = asFiniteNumber(value)
  if (parsed == null) return null
  return Math.trunc(parsed)
}

function asText(value: unknown): string | null {
  if (value == null) return null
  const trimmed = String(value).trim()
  return trimmed ? trimmed : null
}

export function mapCheckInRow(
  row: CheckInRow | Record<string, unknown>
): TraderDailyCheckIn | null {
  const id = asText(row.id)
  const userId = asText(row.user_id)
  const checkInDate = asText(row.check_in_date)
  if (!id || !userId || !checkInDate) return null

  return {
    id,
    ownerProfileId: userId,
    checkInDate,
    sleepHours: asFiniteNumber(row.sleep_hours),
    sleepQuality: asInt(row.sleep_quality),
    morningRating: asInt(row.morning_rating),
    stressLevel: asInt(row.stress_level),
    energyLevel: asInt(row.energy_level),
    focusLevel: asInt(row.focus_level),
    notes: asText(row.notes),
    createdAt: asText(row.created_at) ?? "",
    updatedAt: asText(row.updated_at) ?? asText(row.created_at) ?? "",
  }
}

export async function fetchTodayCheckIn(
  supabase: SupabaseClient<Database>,
  userId: string,
  dateKey: string
): Promise<TraderDailyCheckIn | null> {
  const { data, error } = await supabase
    .from(TRADER_DAILY_CHECK_INS_TABLE)
    .select(TRADER_DAILY_CHECK_IN_SELECT)
    .eq("user_id", userId)
    .eq("check_in_date", dateKey)
    .limit(1)
    .maybeSingle()

  if (error) throw error
  if (!data) return null
  return mapCheckInRow(data as unknown as CheckInRow)
}

export async function fetchCheckInsInRange(
  supabase: SupabaseClient<Database>,
  userId: string,
  startDate: string,
  endDate: string
): Promise<TraderDailyCheckIn[]> {
  const { data, error } = await supabase
    .from(TRADER_DAILY_CHECK_INS_TABLE)
    .select(TRADER_DAILY_CHECK_IN_SELECT)
    .eq("user_id", userId)
    .gte("check_in_date", startDate)
    .lte("check_in_date", endDate)
    .order("check_in_date", { ascending: false })

  if (error) throw error
  if (!Array.isArray(data)) return []
  return data
    .map((row) => mapCheckInRow(row as unknown as CheckInRow))
    .filter((row): row is TraderDailyCheckIn => row != null)
}

export async function upsertDailyCheckIn(
  supabase: SupabaseClient<Database>,
  userId: string,
  draft: TraderDailyCheckInDraft
): Promise<TraderDailyCheckIn> {
  const message = validateCheckInDraft(draft)
  if (message) {
    throw new Error(message)
  }

  const notes = draft.notes.trim()
  const { data, error } = await supabase
    .from(TRADER_DAILY_CHECK_INS_TABLE)
    .upsert(
      {
        user_id: userId,
        check_in_date: draft.checkInDate,
        sleep_hours: draft.sleepHours,
        sleep_quality: draft.sleepQuality,
        morning_rating: draft.morningRating,
        stress_level: draft.stressLevel,
        energy_level: draft.energyLevel,
        focus_level: draft.focusLevel,
        notes: notes ? notes : null,
        updated_at: new Date().toISOString(),
      },
      { onConflict: TRADER_DAILY_CHECK_IN_CONFLICT }
    )
    .select(TRADER_DAILY_CHECK_IN_SELECT)
    .single()

  if (error) throw error
  const mapped = mapCheckInRow(data as unknown as CheckInRow)
  if (!mapped) {
    throw new Error("Your check-in could not be saved.")
  }
  return mapped
}
