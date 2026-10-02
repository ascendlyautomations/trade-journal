/**
 * AUTO-GENERATED — do not hand-edit.
 *
 * Command: npx supabase gen types typescript --project-id "$SUPABASE_PROJECT_ID" --schema public
 * Alternate (MCP): generate_typescript_types(project_id)
 * Schema: public
 * Source: remote TradeTraxs project fobudrkniacatvilbofw (us-east-2)
 * Generated: 2026-09-30 (regenerated from live schema; includes public.trades_public_read)
 *
 * Requires SUPABASE_ACCESS_TOKEN or `supabase login` for CLI regeneration.
 * Set SUPABASE_PROJECT_ID to the linked project ref (not a secret).
 */

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      account_payout_cycles: {
        Row: {
          account_id: string
          balance_after_payout: number | null
          balance_before_payout: number | null
          created_at: string
          cycle_number: number | null
          cycle_start_balance: number
          drawdown_behavior: string | null
          drawdown_floor_after_payout: number | null
          ended_at: string | null
          id: string
          note: string | null
          payout_amount: number | null
          started_at: string
          user_id: string
        }
        Insert: {
          account_id: string
          balance_after_payout?: number | null
          balance_before_payout?: number | null
          created_at?: string
          cycle_number?: number | null
          cycle_start_balance: number
          drawdown_behavior?: string | null
          drawdown_floor_after_payout?: number | null
          ended_at?: string | null
          id?: string
          note?: string | null
          payout_amount?: number | null
          started_at?: string
          user_id: string
        }
        Update: {
          account_id?: string
          balance_after_payout?: number | null
          balance_before_payout?: number | null
          created_at?: string
          cycle_number?: number | null
          cycle_start_balance?: number
          drawdown_behavior?: string | null
          drawdown_floor_after_payout?: number | null
          ended_at?: string | null
          id?: string
          note?: string | null
          payout_amount?: number | null
          started_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "account_payout_cycles_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      account_payout_entries: {
        Row: {
          account_id: string
          amount: number
          created_at: string
          id: string
          image_url: string | null
          note: string | null
          payout_date: string
          updated_at: string
          user_id: string
        }
        Insert: {
          account_id: string
          amount: number
          created_at?: string
          id?: string
          image_url?: string | null
          note?: string | null
          payout_date: string
          updated_at?: string
          user_id: string
        }
        Update: {
          account_id?: string
          amount?: number
          created_at?: string
          id?: string
          image_url?: string | null
          note?: string | null
          payout_date?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "account_payout_entries_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      account_settings: {
        Row: {
          banned_at: string | null
          banned_by: string | null
          created_at: string
          has_used_csv_import: boolean
          has_used_initial_import: boolean
          id: string
          locked_account_name: string | null
          locked_account_number: string | null
          locked_account_size: string | null
          locked_account_type: string | null
          max_drawdown_limit: number | null
          onboarding_completed: boolean
          updated_at: string
          username_change_count: number
        }
        Insert: {
          banned_at?: string | null
          banned_by?: string | null
          created_at?: string
          has_used_csv_import?: boolean
          has_used_initial_import?: boolean
          id: string
          locked_account_name?: string | null
          locked_account_number?: string | null
          locked_account_size?: string | null
          locked_account_type?: string | null
          max_drawdown_limit?: number | null
          onboarding_completed?: boolean
          updated_at?: string
          username_change_count?: number
        }
        Update: {
          banned_at?: string | null
          banned_by?: string | null
          created_at?: string
          has_used_csv_import?: boolean
          has_used_initial_import?: boolean
          id?: string
          locked_account_name?: string | null
          locked_account_number?: string | null
          locked_account_size?: string | null
          locked_account_type?: string | null
          max_drawdown_limit?: number | null
          onboarding_completed?: boolean
          updated_at?: string
          username_change_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "account_settings_id_fkey"
            columns: ["id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      accounts: {
        Row: {
          account_number: string | null
          account_size: string | null
          can_add_trades: boolean
          category: string | null
          consistency: number | null
          created_at: string | null
          custom_public_status: string | null
          daily_drawdown: number | null
          drawdown_type: string | null
          id: string
          is_active: boolean | null
          max_drawdown: number | null
          mode: string | null
          name: string
          note: string | null
          payout_drawdown_behavior: string | null
          profit_target: number | null
          remember_payout_drawdown_behavior: boolean
          show_in_account_dropdowns: boolean
          user_id: string
          winning_day_threshold: number | null
          winning_days: number | null
        }
        Insert: {
          account_number?: string | null
          account_size?: string | null
          can_add_trades?: boolean
          category?: string | null
          consistency?: number | null
          created_at?: string | null
          custom_public_status?: string | null
          daily_drawdown?: number | null
          drawdown_type?: string | null
          id?: string
          is_active?: boolean | null
          max_drawdown?: number | null
          mode?: string | null
          name: string
          note?: string | null
          payout_drawdown_behavior?: string | null
          profit_target?: number | null
          remember_payout_drawdown_behavior?: boolean
          show_in_account_dropdowns?: boolean
          user_id: string
          winning_day_threshold?: number | null
          winning_days?: number | null
        }
        Update: {
          account_number?: string | null
          account_size?: string | null
          can_add_trades?: boolean
          category?: string | null
          consistency?: number | null
          created_at?: string | null
          custom_public_status?: string | null
          daily_drawdown?: number | null
          drawdown_type?: string | null
          id?: string
          is_active?: boolean | null
          max_drawdown?: number | null
          mode?: string | null
          name?: string
          note?: string | null
          payout_drawdown_behavior?: string | null
          profit_target?: number | null
          remember_payout_drawdown_behavior?: boolean
          show_in_account_dropdowns?: boolean
          user_id?: string
          winning_day_threshold?: number | null
          winning_days?: number | null
        }
        Relationships: []
      }
      achievement_post_comments: {
        Row: {
          achievement_post_id: string
          content: string
          created_at: string
          id: string
          parent_comment_id: string | null
          pinned: boolean
          user_id: string
        }
        Insert: {
          achievement_post_id: string
          content: string
          created_at?: string
          id?: string
          parent_comment_id?: string | null
          pinned?: boolean
          user_id: string
        }
        Update: {
          achievement_post_id?: string
          content?: string
          created_at?: string
          id?: string
          parent_comment_id?: string | null
          pinned?: boolean
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "achievement_post_comments_achievement_post_id_fkey"
            columns: ["achievement_post_id"]
            isOneToOne: false
            referencedRelation: "achievement_posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "achievement_post_comments_parent_comment_id_fkey"
            columns: ["parent_comment_id"]
            isOneToOne: false
            referencedRelation: "achievement_post_comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "achievement_post_comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      achievement_post_likes: {
        Row: {
          achievement_post_id: string
          created_at: string
          id: string
          user_id: string
        }
        Insert: {
          achievement_post_id: string
          created_at?: string
          id?: string
          user_id: string
        }
        Update: {
          achievement_post_id?: string
          created_at?: string
          id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "achievement_post_likes_achievement_post_id_fkey"
            columns: ["achievement_post_id"]
            isOneToOne: false
            referencedRelation: "achievement_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      achievement_posts: {
        Row: {
          achievement_id: string
          created_at: string
          id: string
          metadata: Json
          user_id: string
        }
        Insert: {
          achievement_id: string
          created_at?: string
          id?: string
          metadata?: Json
          user_id: string
        }
        Update: {
          achievement_id?: string
          created_at?: string
          id?: string
          metadata?: Json
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "achievement_posts_achievement_id_fkey"
            columns: ["achievement_id"]
            isOneToOne: true
            referencedRelation: "achievements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "achievement_posts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      achievements: {
        Row: {
          account_id: string | null
          account_name: string | null
          account_size: string | null
          account_type: string | null
          achieved_at: string
          achievement_type: string
          badge_key: string | null
          category: string
          created_at: string
          currency: string | null
          description: string | null
          firm: string | null
          id: string
          image_crop: Json | null
          image_url: string | null
          is_featured: boolean
          is_public: boolean
          metadata: Json
          mode: string | null
          sort_order: number
          tier: string | null
          title: string
          updated_at: string
          user_id: string
          value_numeric: number | null
          value_text: string | null
        }
        Insert: {
          account_id?: string | null
          account_name?: string | null
          account_size?: string | null
          account_type?: string | null
          achieved_at?: string
          achievement_type: string
          badge_key?: string | null
          category?: string
          created_at?: string
          currency?: string | null
          description?: string | null
          firm?: string | null
          id?: string
          image_crop?: Json | null
          image_url?: string | null
          is_featured?: boolean
          is_public?: boolean
          metadata?: Json
          mode?: string | null
          sort_order?: number
          tier?: string | null
          title: string
          updated_at?: string
          user_id: string
          value_numeric?: number | null
          value_text?: string | null
        }
        Update: {
          account_id?: string | null
          account_name?: string | null
          account_size?: string | null
          account_type?: string | null
          achieved_at?: string
          achievement_type?: string
          badge_key?: string | null
          category?: string
          created_at?: string
          currency?: string | null
          description?: string | null
          firm?: string | null
          id?: string
          image_crop?: Json | null
          image_url?: string | null
          is_featured?: boolean
          is_public?: boolean
          metadata?: Json
          mode?: string | null
          sort_order?: number
          tier?: string | null
          title?: string
          updated_at?: string
          user_id?: string
          value_numeric?: number | null
          value_text?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "achievements_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "achievements_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      admin_audit_log: {
        Row: {
          action: string
          admin_user_id: string | null
          created_at: string
          details: Json
          id: string
          target_id: string | null
          target_type: string | null
          target_user_id: string | null
        }
        Insert: {
          action: string
          admin_user_id?: string | null
          created_at?: string
          details?: Json
          id?: string
          target_id?: string | null
          target_type?: string | null
          target_user_id?: string | null
        }
        Update: {
          action?: string
          admin_user_id?: string | null
          created_at?: string
          details?: Json
          id?: string
          target_id?: string | null
          target_type?: string | null
          target_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "admin_audit_log_admin_user_id_fkey"
            columns: ["admin_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "admin_audit_log_target_user_id_fkey"
            columns: ["target_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      admin_users: {
        Row: {
          created_at: string
          email: string | null
          role: string
          user_id: string
        }
        Insert: {
          created_at?: string
          email?: string | null
          role?: string
          user_id: string
        }
        Update: {
          created_at?: string
          email?: string | null
          role?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "admin_users_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      affiliate_applications: {
        Row: {
          admin_notes: string | null
          approved_code: string | null
          audience_size: number | null
          created_at: string | null
          email: string | null
          experience: string | null
          followers: number | null
          full_name: string | null
          has_edited: boolean | null
          id: string
          name: string | null
          platform: string | null
          promo_plan: string | null
          requested_code: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          social_handle: string
          status: string | null
          stripe_promo_code_id: string | null
          updated_at: string | null
          user_id: string | null
          why: string | null
          why_join: string | null
        }
        Insert: {
          admin_notes?: string | null
          approved_code?: string | null
          audience_size?: number | null
          created_at?: string | null
          email?: string | null
          experience?: string | null
          followers?: number | null
          full_name?: string | null
          has_edited?: boolean | null
          id?: string
          name?: string | null
          platform?: string | null
          promo_plan?: string | null
          requested_code?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          social_handle: string
          status?: string | null
          stripe_promo_code_id?: string | null
          updated_at?: string | null
          user_id?: string | null
          why?: string | null
          why_join?: string | null
        }
        Update: {
          admin_notes?: string | null
          approved_code?: string | null
          audience_size?: number | null
          created_at?: string | null
          email?: string | null
          experience?: string | null
          followers?: number | null
          full_name?: string | null
          has_edited?: boolean | null
          id?: string
          name?: string | null
          platform?: string | null
          promo_plan?: string | null
          requested_code?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          social_handle?: string
          status?: string | null
          stripe_promo_code_id?: string | null
          updated_at?: string | null
          user_id?: string | null
          why?: string | null
          why_join?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "affiliate_applications_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "affiliate_applications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      affiliate_payout_requests: {
        Row: {
          admin_notes: string | null
          affiliate_id: string | null
          amount: number
          created_at: string
          id: string
          paid_at: string | null
          payout_reference: string | null
          requested_at: string
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          stripe_transfer_id: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          admin_notes?: string | null
          affiliate_id?: string | null
          amount: number
          created_at?: string
          id?: string
          paid_at?: string | null
          payout_reference?: string | null
          requested_at?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          stripe_transfer_id?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          admin_notes?: string | null
          affiliate_id?: string | null
          amount?: number
          created_at?: string
          id?: string
          paid_at?: string | null
          payout_reference?: string | null
          requested_at?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          stripe_transfer_id?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "affiliate_payout_requests_affiliate_id_fkey"
            columns: ["affiliate_id"]
            isOneToOne: false
            referencedRelation: "affiliates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "affiliate_payout_requests_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "affiliate_payout_requests_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      affiliates: {
        Row: {
          code: string | null
          created_at: string | null
          email: string | null
          experience: string | null
          has_edited: boolean | null
          id: string
          is_active: boolean | null
          name: string | null
          platform: string | null
          promo_plan: string | null
          stripe_charges_enabled: boolean
          stripe_connected_account_id: string | null
          stripe_details_submitted: boolean
          stripe_onboarding_complete: boolean
          stripe_onboarding_last_url: string | null
          stripe_onboarding_updated_at: string | null
          stripe_payouts_enabled: boolean
          stripe_promo_code_id: string | null
          user_id: string | null
        }
        Insert: {
          code?: string | null
          created_at?: string | null
          email?: string | null
          experience?: string | null
          has_edited?: boolean | null
          id?: string
          is_active?: boolean | null
          name?: string | null
          platform?: string | null
          promo_plan?: string | null
          stripe_charges_enabled?: boolean
          stripe_connected_account_id?: string | null
          stripe_details_submitted?: boolean
          stripe_onboarding_complete?: boolean
          stripe_onboarding_last_url?: string | null
          stripe_onboarding_updated_at?: string | null
          stripe_payouts_enabled?: boolean
          stripe_promo_code_id?: string | null
          user_id?: string | null
        }
        Update: {
          code?: string | null
          created_at?: string | null
          email?: string | null
          experience?: string | null
          has_edited?: boolean | null
          id?: string
          is_active?: boolean | null
          name?: string | null
          platform?: string | null
          promo_plan?: string | null
          stripe_charges_enabled?: boolean
          stripe_connected_account_id?: string | null
          stripe_details_submitted?: boolean
          stripe_onboarding_complete?: boolean
          stripe_onboarding_last_url?: string | null
          stripe_onboarding_updated_at?: string | null
          stripe_payouts_enabled?: boolean
          stripe_promo_code_id?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "affiliates_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      app_monetization_account_overrides: {
        Row: {
          created_at: string
          entitlement_enforcement_enabled: boolean | null
          ios_paywall_enabled: boolean | null
          note: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          entitlement_enforcement_enabled?: boolean | null
          ios_paywall_enabled?: boolean | null
          note?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          entitlement_enforcement_enabled?: boolean | null
          ios_paywall_enabled?: boolean | null
          note?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      app_monetization_settings: {
        Row: {
          entitlement_enforcement_enabled: boolean
          id: number
          ios_paywall_enabled: boolean
          launch_access_cutoff_at: string | null
          launch_access_mode: string
          updated_at: string
        }
        Insert: {
          entitlement_enforcement_enabled?: boolean
          id: number
          ios_paywall_enabled?: boolean
          launch_access_cutoff_at?: string | null
          launch_access_mode?: string
          updated_at?: string
        }
        Update: {
          entitlement_enforcement_enabled?: boolean
          id?: number
          ios_paywall_enabled?: boolean
          launch_access_cutoff_at?: string | null
          launch_access_mode?: string
          updated_at?: string
        }
        Relationships: []
      }
      apple_sign_in_credentials: {
        Row: {
          apple_sub: string | null
          client_id: string
          created_at: string
          refresh_token_ciphertext: string
          updated_at: string
          user_id: string
        }
        Insert: {
          apple_sub?: string | null
          client_id: string
          created_at?: string
          refresh_token_ciphertext: string
          updated_at?: string
          user_id: string
        }
        Update: {
          apple_sub?: string | null
          client_id?: string
          created_at?: string
          refresh_token_ciphertext?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      apple_sign_in_revoke_queue: {
        Row: {
          attempts: number
          client_id: string
          created_at: string
          id: string
          last_error: string | null
          lease_expires_at: string | null
          next_attempt_at: string
          refresh_token_ciphertext: string
        }
        Insert: {
          attempts?: number
          client_id: string
          created_at?: string
          id?: string
          last_error?: string | null
          lease_expires_at?: string | null
          next_attempt_at?: string
          refresh_token_ciphertext: string
        }
        Update: {
          attempts?: number
          client_id?: string
          created_at?: string
          id?: string
          last_error?: string | null
          lease_expires_at?: string | null
          next_attempt_at?: string
          refresh_token_ciphertext?: string
        }
        Relationships: []
      }
      apple_subscription_notifications: {
        Row: {
          environment: string | null
          id: string
          notification_type: string
          notification_uuid: string
          original_transaction_id: string | null
          processed_at: string
          signed_date: string | null
          subtype: string | null
        }
        Insert: {
          environment?: string | null
          id?: string
          notification_type: string
          notification_uuid: string
          original_transaction_id?: string | null
          processed_at?: string
          signed_date?: string | null
          subtype?: string | null
        }
        Update: {
          environment?: string | null
          id?: string
          notification_type?: string
          notification_uuid?: string
          original_transaction_id?: string | null
          processed_at?: string
          signed_date?: string | null
          subtype?: string | null
        }
        Relationships: []
      }
      apple_subscriptions: {
        Row: {
          billing_interval: string | null
          created_at: string
          environment: string
          expires_at: string | null
          id: string
          last_verified_at: string
          latest_transaction_id: string
          original_transaction_id: string
          product_id: string
          purchased_at: string | null
          revoked_at: string | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          billing_interval?: string | null
          created_at?: string
          environment: string
          expires_at?: string | null
          id?: string
          last_verified_at?: string
          latest_transaction_id: string
          original_transaction_id: string
          product_id: string
          purchased_at?: string | null
          revoked_at?: string | null
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          billing_interval?: string | null
          created_at?: string
          environment?: string
          expires_at?: string | null
          id?: string
          last_verified_at?: string
          latest_transaction_id?: string
          original_transaction_id?: string
          product_id?: string
          purchased_at?: string | null
          revoked_at?: string | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      billing_accounts: {
        Row: {
          created_at: string
          id: string
          stripe_customer_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          id: string
          stripe_customer_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          stripe_customer_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "billing_accounts_id_fkey"
            columns: ["id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      broker_integration_account_sync: {
        Row: {
          auto_sync_enabled: boolean
          broker_integration_account_id: string
          connection_id: string
          created_at: string
          last_auto_sync_at: string | null
          last_event_at: string | null
          last_sync_attempt_at: string | null
          last_sync_error_code: string | null
          last_sync_error_message: string | null
          last_sync_status: string
          last_sync_success_at: string | null
          max_executed_at: string | null
          max_external_fill_id: string | null
          pending_sync_after_current: boolean
          provider_sync_state: Json
          sync_dirty_at: string | null
          sync_lock_until: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          auto_sync_enabled?: boolean
          broker_integration_account_id: string
          connection_id: string
          created_at?: string
          last_auto_sync_at?: string | null
          last_event_at?: string | null
          last_sync_attempt_at?: string | null
          last_sync_error_code?: string | null
          last_sync_error_message?: string | null
          last_sync_status?: string
          last_sync_success_at?: string | null
          max_executed_at?: string | null
          max_external_fill_id?: string | null
          pending_sync_after_current?: boolean
          provider_sync_state?: Json
          sync_dirty_at?: string | null
          sync_lock_until?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          auto_sync_enabled?: boolean
          broker_integration_account_id?: string
          connection_id?: string
          created_at?: string
          last_auto_sync_at?: string | null
          last_event_at?: string | null
          last_sync_attempt_at?: string | null
          last_sync_error_code?: string | null
          last_sync_error_message?: string | null
          last_sync_status?: string
          last_sync_success_at?: string | null
          max_executed_at?: string | null
          max_external_fill_id?: string | null
          pending_sync_after_current?: boolean
          provider_sync_state?: Json
          sync_dirty_at?: string | null
          sync_lock_until?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "broker_integration_account_sy_broker_integration_account_i_fkey"
            columns: ["broker_integration_account_id"]
            isOneToOne: true
            referencedRelation: "broker_integration_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "broker_integration_account_sync_connection_id_fkey"
            columns: ["connection_id"]
            isOneToOne: false
            referencedRelation: "broker_integration_connections"
            referencedColumns: ["id"]
          },
        ]
      }
      broker_integration_accounts: {
        Row: {
          connection_id: string
          created_at: string
          discovered_at: string
          external_account_id: string
          external_account_name: string | null
          external_display_name: string | null
          external_metadata: Json
          id: string
          last_seen_at: string
          provider: string
          status: string
          sync_enabled: boolean
          tradetraxs_account_id: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          connection_id: string
          created_at?: string
          discovered_at?: string
          external_account_id: string
          external_account_name?: string | null
          external_display_name?: string | null
          external_metadata?: Json
          id?: string
          last_seen_at?: string
          provider: string
          status?: string
          sync_enabled?: boolean
          tradetraxs_account_id?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          connection_id?: string
          created_at?: string
          discovered_at?: string
          external_account_id?: string
          external_account_name?: string | null
          external_display_name?: string | null
          external_metadata?: Json
          id?: string
          last_seen_at?: string
          provider?: string
          status?: string
          sync_enabled?: boolean
          tradetraxs_account_id?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "broker_integration_accounts_connection_id_fkey"
            columns: ["connection_id"]
            isOneToOne: false
            referencedRelation: "broker_integration_connections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "broker_integration_accounts_tradetraxs_account_id_fkey"
            columns: ["tradetraxs_account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      broker_integration_connections: {
        Row: {
          access_token_expires_at: string | null
          api_environment: string | null
          broker_login_username: string | null
          connected_at: string | null
          connection_label: string | null
          created_at: string
          credentials_ciphertext: string | null
          disconnected_at: string | null
          id: string
          last_sync_at: string | null
          last_verified_at: string | null
          listener_last_connected_at: string | null
          listener_last_disconnected_at: string | null
          listener_last_error_code: string | null
          listener_last_error_message: string | null
          listener_reconnect_count: number
          listener_status: string
          listener_worker_heartbeat_at: string | null
          provider: string
          provider_display_name: string | null
          provider_user_id: string | null
          refresh_token_expires_at: string | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          access_token_expires_at?: string | null
          api_environment?: string | null
          broker_login_username?: string | null
          connected_at?: string | null
          connection_label?: string | null
          created_at?: string
          credentials_ciphertext?: string | null
          disconnected_at?: string | null
          id?: string
          last_sync_at?: string | null
          last_verified_at?: string | null
          listener_last_connected_at?: string | null
          listener_last_disconnected_at?: string | null
          listener_last_error_code?: string | null
          listener_last_error_message?: string | null
          listener_reconnect_count?: number
          listener_status?: string
          listener_worker_heartbeat_at?: string | null
          provider: string
          provider_display_name?: string | null
          provider_user_id?: string | null
          refresh_token_expires_at?: string | null
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          access_token_expires_at?: string | null
          api_environment?: string | null
          broker_login_username?: string | null
          connected_at?: string | null
          connection_label?: string | null
          created_at?: string
          credentials_ciphertext?: string | null
          disconnected_at?: string | null
          id?: string
          last_sync_at?: string | null
          last_verified_at?: string | null
          listener_last_connected_at?: string | null
          listener_last_disconnected_at?: string | null
          listener_last_error_code?: string | null
          listener_last_error_message?: string | null
          listener_reconnect_count?: number
          listener_status?: string
          listener_worker_heartbeat_at?: string | null
          provider?: string
          provider_display_name?: string | null
          provider_user_id?: string | null
          refresh_token_expires_at?: string | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      broker_integration_executions: {
        Row: {
          broker_integration_account_id: string
          canonical_trade_id: string | null
          connection_id: string
          contract_name: string | null
          created_at: string
          executed_at: string
          external_contract_id: string
          external_fill_id: string
          external_order_id: number | null
          id: string
          lifecycle_key: string | null
          price: number
          provider: string
          provider_metadata: Json
          quantity: number
          side: string
          symbol_root: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          broker_integration_account_id: string
          canonical_trade_id?: string | null
          connection_id: string
          contract_name?: string | null
          created_at?: string
          executed_at: string
          external_contract_id: string
          external_fill_id: string
          external_order_id?: number | null
          id?: string
          lifecycle_key?: string | null
          price: number
          provider?: string
          provider_metadata?: Json
          quantity: number
          side: string
          symbol_root?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          broker_integration_account_id?: string
          canonical_trade_id?: string | null
          connection_id?: string
          contract_name?: string | null
          created_at?: string
          executed_at?: string
          external_contract_id?: string
          external_fill_id?: string
          external_order_id?: number | null
          id?: string
          lifecycle_key?: string | null
          price?: number
          provider?: string
          provider_metadata?: Json
          quantity?: number
          side?: string
          symbol_root?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "broker_integration_executions_broker_integration_account_i_fkey"
            columns: ["broker_integration_account_id"]
            isOneToOne: false
            referencedRelation: "broker_integration_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "broker_integration_executions_canonical_trade_id_fkey"
            columns: ["canonical_trade_id"]
            isOneToOne: false
            referencedRelation: "trades"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "broker_integration_executions_canonical_trade_id_fkey"
            columns: ["canonical_trade_id"]
            isOneToOne: false
            referencedRelation: "trades_public_read"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "broker_integration_executions_connection_id_fkey"
            columns: ["connection_id"]
            isOneToOne: false
            referencedRelation: "broker_integration_connections"
            referencedColumns: ["id"]
          },
        ]
      }
      bug_reports: {
        Row: {
          browser_info: string | null
          created_at: string
          description: string
          id: string
          page_url: string | null
          resolved_at: string | null
          screenshot_url: string | null
          severity: string
          status: string
          title: string
          user_id: string
        }
        Insert: {
          browser_info?: string | null
          created_at?: string
          description: string
          id?: string
          page_url?: string | null
          resolved_at?: string | null
          screenshot_url?: string | null
          severity?: string
          status?: string
          title: string
          user_id: string
        }
        Update: {
          browser_info?: string | null
          created_at?: string
          description?: string
          id?: string
          page_url?: string | null
          resolved_at?: string | null
          screenshot_url?: string | null
          severity?: string
          status?: string
          title?: string
          user_id?: string
        }
        Relationships: []
      }
      comment_likes: {
        Row: {
          comment_id: string
          comment_source: string
          created_at: string
          id: string
          user_id: string
        }
        Insert: {
          comment_id: string
          comment_source: string
          created_at?: string
          id?: string
          user_id: string
        }
        Update: {
          comment_id?: string
          comment_source?: string
          created_at?: string
          id?: string
          user_id?: string
        }
        Relationships: []
      }
      comments: {
        Row: {
          content: string | null
          created_at: string | null
          id: string
          parent_comment_id: string | null
          pinned: boolean
          post_id: string | null
          user_id: string | null
        }
        Insert: {
          content?: string | null
          created_at?: string | null
          id?: string
          parent_comment_id?: string | null
          pinned?: boolean
          post_id?: string | null
          user_id?: string | null
        }
        Update: {
          content?: string | null
          created_at?: string | null
          id?: string
          parent_comment_id?: string | null
          pinned?: boolean
          post_id?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "comments_parent_comment_id_fkey"
            columns: ["parent_comment_id"]
            isOneToOne: false
            referencedRelation: "comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comments_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      content_reports: {
        Row: {
          created_at: string
          details: string | null
          id: string
          reason: string
          reported_user_id: string | null
          reporter_user_id: string
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          target_id: string
          target_type: string
        }
        Insert: {
          created_at?: string
          details?: string | null
          id?: string
          reason: string
          reported_user_id?: string | null
          reporter_user_id: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          target_id: string
          target_type: string
        }
        Update: {
          created_at?: string
          details?: string | null
          id?: string
          reason?: string
          reported_user_id?: string | null
          reporter_user_id?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          target_id?: string
          target_type?: string
        }
        Relationships: []
      }
      conversation_member_preferences: {
        Row: {
          conversation_id: string
          created_at: string
          last_read_at: string | null
          last_read_message_id: string | null
          notifications_enabled: boolean
          updated_at: string
          user_id: string
        }
        Insert: {
          conversation_id: string
          created_at?: string
          last_read_at?: string | null
          last_read_message_id?: string | null
          notifications_enabled?: boolean
          updated_at?: string
          user_id: string
        }
        Update: {
          conversation_id?: string
          created_at?: string
          last_read_at?: string | null
          last_read_message_id?: string | null
          notifications_enabled?: boolean
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "conversation_member_preferences_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversation_member_preferences_last_read_message_id_fkey"
            columns: ["last_read_message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversation_member_preferences_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      conversation_participants: {
        Row: {
          conversation_id: string | null
          id: string
          joined_at: string | null
          user_id: string | null
        }
        Insert: {
          conversation_id?: string | null
          id?: string
          joined_at?: string | null
          user_id?: string | null
        }
        Update: {
          conversation_id?: string | null
          id?: string
          joined_at?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "conversation_participants_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversation_participants_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      conversations: {
        Row: {
          avatar_url: string | null
          created_at: string | null
          id: string
          is_group: boolean | null
          is_pinned: boolean | null
          last_message: string | null
          last_message_at: string | null
          name: string | null
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string | null
          id?: string
          is_group?: boolean | null
          is_pinned?: boolean | null
          last_message?: string | null
          last_message_at?: string | null
          name?: string | null
        }
        Update: {
          avatar_url?: string | null
          created_at?: string | null
          id?: string
          is_group?: boolean | null
          is_pinned?: boolean | null
          last_message?: string | null
          last_message_at?: string | null
          name?: string | null
        }
        Relationships: []
      }
      copy_trading_group_accounts: {
        Row: {
          account_id: string
          created_at: string
          group_id: string
          id: string
          sort_order: number
          user_id: string
        }
        Insert: {
          account_id: string
          created_at?: string
          group_id: string
          id?: string
          sort_order?: number
          user_id: string
        }
        Update: {
          account_id?: string
          created_at?: string
          group_id?: string
          id?: string
          sort_order?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "copy_trading_group_accounts_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "copy_trading_group_accounts_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "copy_trading_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      copy_trading_groups: {
        Row: {
          created_at: string
          id: string
          name: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      creator_access_codes: {
        Row: {
          code: string
          created_at: string
          expires_at: string | null
          is_active: boolean
          label: string | null
          max_redemptions: number
          notes: string | null
        }
        Insert: {
          code: string
          created_at?: string
          expires_at?: string | null
          is_active?: boolean
          label?: string | null
          max_redemptions?: number
          notes?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          expires_at?: string | null
          is_active?: boolean
          label?: string | null
          max_redemptions?: number
          notes?: string | null
        }
        Relationships: []
      }
      creator_code_redemptions: {
        Row: {
          code: string
          id: string
          redeemed_at: string
          user_id: string
        }
        Insert: {
          code: string
          id?: string
          redeemed_at?: string
          user_id: string
        }
        Update: {
          code?: string
          id?: string
          redeemed_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "creator_code_redemptions_code_fkey"
            columns: ["code"]
            isOneToOne: false
            referencedRelation: "creator_access_codes"
            referencedColumns: ["code"]
          },
        ]
      }
      csv_support_requests: {
        Row: {
          broker_name: string | null
          created_at: string | null
          csv_file_url: string | null
          id: string
          notes: string | null
          status: string | null
          user_id: string | null
        }
        Insert: {
          broker_name?: string | null
          created_at?: string | null
          csv_file_url?: string | null
          id?: string
          notes?: string | null
          status?: string | null
          user_id?: string | null
        }
        Update: {
          broker_name?: string | null
          created_at?: string | null
          csv_file_url?: string | null
          id?: string
          notes?: string | null
          status?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      device_push_tokens: {
        Row: {
          app_version: string | null
          created_at: string
          device_token: string
          id: string
          installation_id: string | null
          last_seen_at: string
          platform: string
          updated_at: string
          user_id: string
        }
        Insert: {
          app_version?: string | null
          created_at?: string
          device_token: string
          id?: string
          installation_id?: string | null
          last_seen_at?: string
          platform?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          app_version?: string | null
          created_at?: string
          device_token?: string
          id?: string
          installation_id?: string | null
          last_seen_at?: string
          platform?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "device_push_tokens_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      direct_messages: {
        Row: {
          content: string | null
          conversation_id: string | null
          created_at: string | null
          id: string
          image_url: string | null
          is_read: boolean | null
          recipient_id: string | null
          sender_id: string | null
        }
        Insert: {
          content?: string | null
          conversation_id?: string | null
          created_at?: string | null
          id?: string
          image_url?: string | null
          is_read?: boolean | null
          recipient_id?: string | null
          sender_id?: string | null
        }
        Update: {
          content?: string | null
          conversation_id?: string | null
          created_at?: string | null
          id?: string
          image_url?: string | null
          is_read?: boolean | null
          recipient_id?: string | null
          sender_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "direct_messages_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "direct_messages_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      early_access_campaigns: {
        Row: {
          award_limit: number
          campaign_key: string
          challenge_version: number
          created_at: string
          eligibility_starts_at: string
          enrollment_enabled: boolean
          environment: string
          updated_at: string
        }
        Insert: {
          award_limit: number
          campaign_key: string
          challenge_version?: number
          created_at?: string
          eligibility_starts_at?: string
          enrollment_enabled?: boolean
          environment: string
          updated_at?: string
        }
        Update: {
          award_limit?: number
          campaign_key?: string
          challenge_version?: number
          created_at?: string
          eligibility_starts_at?: string
          enrollment_enabled?: boolean
          environment?: string
          updated_at?: string
        }
        Relationships: []
      }
      feature_requests: {
        Row: {
          created_at: string
          description: string
          id: string
          status: string
          title: string
          user_id: string
        }
        Insert: {
          created_at?: string
          description: string
          id?: string
          status?: string
          title: string
          user_id: string
        }
        Update: {
          created_at?: string
          description?: string
          id?: string
          status?: string
          title?: string
          user_id?: string
        }
        Relationships: []
      }
      feedback_submissions: {
        Row: {
          admin_notes: string | null
          created_at: string
          email: string | null
          id: string
          message: string
          screenshot_url: string | null
          status: string
          subject: string | null
          updated_at: string
          user_id: string | null
          viewed: boolean
          viewed_at: string | null
          viewed_by: string | null
        }
        Insert: {
          admin_notes?: string | null
          created_at?: string
          email?: string | null
          id?: string
          message: string
          screenshot_url?: string | null
          status?: string
          subject?: string | null
          updated_at?: string
          user_id?: string | null
          viewed?: boolean
          viewed_at?: string | null
          viewed_by?: string | null
        }
        Update: {
          admin_notes?: string | null
          created_at?: string
          email?: string | null
          id?: string
          message?: string
          screenshot_url?: string | null
          status?: string
          subject?: string | null
          updated_at?: string
          user_id?: string | null
          viewed?: boolean
          viewed_at?: string | null
          viewed_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "feedback_submissions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feedback_submissions_viewed_by_fkey"
            columns: ["viewed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      follow_requests: {
        Row: {
          created_at: string
          id: string
          requester_id: string
          responded_at: string | null
          status: string
          target_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          requester_id: string
          responded_at?: string | null
          status?: string
          target_id: string
        }
        Update: {
          created_at?: string
          id?: string
          requester_id?: string
          responded_at?: string | null
          status?: string
          target_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "follow_requests_target_id_fkey"
            columns: ["target_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      followers: {
        Row: {
          created_at: string | null
          follower_id: string | null
          following_id: string | null
          id: string
        }
        Insert: {
          created_at?: string | null
          follower_id?: string | null
          following_id?: string | null
          id?: string
        }
        Update: {
          created_at?: string | null
          follower_id?: string | null
          following_id?: string | null
          id?: string
        }
        Relationships: []
      }
      follows: {
        Row: {
          follower_id: string | null
          following_id: string | null
          id: string
        }
        Insert: {
          follower_id?: string | null
          following_id?: string | null
          id?: string
        }
        Update: {
          follower_id?: string | null
          following_id?: string | null
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "follows_follower_id_fkey"
            columns: ["follower_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "follows_following_id_fkey"
            columns: ["following_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      integration_oauth_states: {
        Row: {
          api_environment: string | null
          consumed_at: string | null
          created_at: string
          expires_at: string
          id: string
          oauth_intent: string
          provider: string
          redirect_after: string | null
          state_token: string
          target_connection_id: string | null
          user_id: string
        }
        Insert: {
          api_environment?: string | null
          consumed_at?: string | null
          created_at?: string
          expires_at: string
          id?: string
          oauth_intent?: string
          provider: string
          redirect_after?: string | null
          state_token: string
          target_connection_id?: string | null
          user_id: string
        }
        Update: {
          api_environment?: string | null
          consumed_at?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          oauth_intent?: string
          provider?: string
          redirect_after?: string | null
          state_token?: string
          target_connection_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "integration_oauth_states_target_connection_id_fkey"
            columns: ["target_connection_id"]
            isOneToOne: false
            referencedRelation: "broker_integration_connections"
            referencedColumns: ["id"]
          },
        ]
      }
      likes: {
        Row: {
          created_at: string | null
          id: string
          post_id: string | null
          user_id: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          post_id?: string | null
          user_id?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
          post_id?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "likes_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "likes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      message_comments: {
        Row: {
          content: string | null
          created_at: string | null
          id: string
          message_id: string | null
          user_id: string | null
        }
        Insert: {
          content?: string | null
          created_at?: string | null
          id?: string
          message_id?: string | null
          user_id?: string | null
        }
        Update: {
          content?: string | null
          created_at?: string | null
          id?: string
          message_id?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "message_comments_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      message_deletions: {
        Row: {
          created_at: string | null
          id: string
          message_id: string | null
          user_id: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          message_id?: string | null
          user_id?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
          message_id?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "message_deletions_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_deletions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      message_likes: {
        Row: {
          id: string
          message_id: string | null
          type: string | null
          user_id: string | null
        }
        Insert: {
          id?: string
          message_id?: string | null
          type?: string | null
          user_id?: string | null
        }
        Update: {
          id?: string
          message_id?: string | null
          type?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "message_likes_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_likes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      message_reactions: {
        Row: {
          conversation_id: string
          created_at: string
          id: string
          message_id: string
          reaction: string
          user_id: string
        }
        Insert: {
          conversation_id: string
          created_at?: string
          id?: string
          message_id: string
          reaction: string
          user_id: string
        }
        Update: {
          conversation_id?: string
          created_at?: string
          id?: string
          message_id?: string
          reaction?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "message_reactions_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_reactions_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_reactions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      messages: {
        Row: {
          achievement_post_id: string | null
          audio_duration_ms: number | null
          audio_url: string | null
          channel: string | null
          content: string | null
          conversation_id: string | null
          created_at: string | null
          deleted_for_everyone: boolean | null
          id: string
          image_url: string | null
          is_system: boolean | null
          parent_message_id: string | null
          post_id: string | null
          profile_post_id: string | null
          reel_id: string | null
          seen_by: string[] | null
          sender_anonymized: boolean
          sender_id: string | null
          trade_id: string | null
          type: string | null
          user_id: string | null
        }
        Insert: {
          achievement_post_id?: string | null
          audio_duration_ms?: number | null
          audio_url?: string | null
          channel?: string | null
          content?: string | null
          conversation_id?: string | null
          created_at?: string | null
          deleted_for_everyone?: boolean | null
          id?: string
          image_url?: string | null
          is_system?: boolean | null
          parent_message_id?: string | null
          post_id?: string | null
          profile_post_id?: string | null
          reel_id?: string | null
          seen_by?: string[] | null
          sender_anonymized?: boolean
          sender_id?: string | null
          trade_id?: string | null
          type?: string | null
          user_id?: string | null
        }
        Update: {
          achievement_post_id?: string | null
          audio_duration_ms?: number | null
          audio_url?: string | null
          channel?: string | null
          content?: string | null
          conversation_id?: string | null
          created_at?: string | null
          deleted_for_everyone?: boolean | null
          id?: string
          image_url?: string | null
          is_system?: boolean | null
          parent_message_id?: string | null
          post_id?: string | null
          profile_post_id?: string | null
          reel_id?: string | null
          seen_by?: string[] | null
          sender_anonymized?: boolean
          sender_id?: string | null
          trade_id?: string | null
          type?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "messages_achievement_post_id_fkey"
            columns: ["achievement_post_id"]
            isOneToOne: false
            referencedRelation: "achievement_posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_parent_message_id_fkey"
            columns: ["parent_message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_profile_post_id_fkey"
            columns: ["profile_post_id"]
            isOneToOne: false
            referencedRelation: "profile_posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_reel_id_fkey"
            columns: ["reel_id"]
            isOneToOne: false
            referencedRelation: "reels"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: false
            referencedRelation: "trades"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: false
            referencedRelation: "trades_public_read"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_preferences: {
        Row: {
          achievement_comments_enabled: boolean
          achievement_likes_enabled: boolean
          achievement_unlocks_enabled: boolean
          announcements_enabled: boolean
          comments_enabled: boolean
          direct_messages_enabled: boolean
          follow_request_accepts_enabled: boolean
          follow_requests_enabled: boolean
          followers_enabled: boolean
          likes_enabled: boolean
          maintenance_enabled: boolean
          mentions_enabled: boolean
          notifications_enabled: boolean
          product_updates_enabled: boolean
          reactions_enabled: boolean
          replies_enabled: boolean
          room_joins_enabled: boolean
          room_mentions_enabled: boolean
          room_messages_enabled: boolean
          shares_enabled: boolean
          story_replies_enabled: boolean
          updated_at: string
          user_id: string
        }
        Insert: {
          achievement_comments_enabled?: boolean
          achievement_likes_enabled?: boolean
          achievement_unlocks_enabled?: boolean
          announcements_enabled?: boolean
          comments_enabled?: boolean
          direct_messages_enabled?: boolean
          follow_request_accepts_enabled?: boolean
          follow_requests_enabled?: boolean
          followers_enabled?: boolean
          likes_enabled?: boolean
          maintenance_enabled?: boolean
          mentions_enabled?: boolean
          notifications_enabled?: boolean
          product_updates_enabled?: boolean
          reactions_enabled?: boolean
          replies_enabled?: boolean
          room_joins_enabled?: boolean
          room_mentions_enabled?: boolean
          room_messages_enabled?: boolean
          shares_enabled?: boolean
          story_replies_enabled?: boolean
          updated_at?: string
          user_id: string
        }
        Update: {
          achievement_comments_enabled?: boolean
          achievement_likes_enabled?: boolean
          achievement_unlocks_enabled?: boolean
          announcements_enabled?: boolean
          comments_enabled?: boolean
          direct_messages_enabled?: boolean
          follow_request_accepts_enabled?: boolean
          follow_requests_enabled?: boolean
          followers_enabled?: boolean
          likes_enabled?: boolean
          maintenance_enabled?: boolean
          mentions_enabled?: boolean
          notifications_enabled?: boolean
          product_updates_enabled?: boolean
          reactions_enabled?: boolean
          replies_enabled?: boolean
          room_joins_enabled?: boolean
          room_mentions_enabled?: boolean
          room_messages_enabled?: boolean
          shares_enabled?: boolean
          story_replies_enabled?: boolean
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_preferences_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          achievement_post_id: string | null
          comment_id: string | null
          content: string | null
          created_at: string | null
          id: string
          message: string | null
          post_id: string | null
          profile_post_id: string | null
          read: boolean | null
          reel_id: string | null
          room_id: string | null
          room_message_id: string | null
          sender_id: string | null
          trade_id: string | null
          type: string | null
          user_id: string | null
        }
        Insert: {
          achievement_post_id?: string | null
          comment_id?: string | null
          content?: string | null
          created_at?: string | null
          id?: string
          message?: string | null
          post_id?: string | null
          profile_post_id?: string | null
          read?: boolean | null
          reel_id?: string | null
          room_id?: string | null
          room_message_id?: string | null
          sender_id?: string | null
          trade_id?: string | null
          type?: string | null
          user_id?: string | null
        }
        Update: {
          achievement_post_id?: string | null
          comment_id?: string | null
          content?: string | null
          created_at?: string | null
          id?: string
          message?: string | null
          post_id?: string | null
          profile_post_id?: string | null
          read?: boolean | null
          reel_id?: string | null
          room_id?: string | null
          room_message_id?: string | null
          sender_id?: string | null
          trade_id?: string | null
          type?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notifications_achievement_post_id_fkey"
            columns: ["achievement_post_id"]
            isOneToOne: false
            referencedRelation: "achievement_posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_profile_post_id_fkey"
            columns: ["profile_post_id"]
            isOneToOne: false
            referencedRelation: "profile_posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_reel_id_fkey"
            columns: ["reel_id"]
            isOneToOne: false
            referencedRelation: "reels"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: false
            referencedRelation: "trades"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: false
            referencedRelation: "trades_public_read"
            referencedColumns: ["id"]
          },
        ]
      }
      platform_update_broadcasts: {
        Row: {
          attempted_count: number
          completed_at: string | null
          created_at: string
          cursor_token_id: string | null
          failed_count: number
          id: string
          started_at: string | null
          status: string
          success_count: number
          update_id: string
        }
        Insert: {
          attempted_count?: number
          completed_at?: string | null
          created_at?: string
          cursor_token_id?: string | null
          failed_count?: number
          id?: string
          started_at?: string | null
          status?: string
          success_count?: number
          update_id: string
        }
        Update: {
          attempted_count?: number
          completed_at?: string | null
          created_at?: string
          cursor_token_id?: string | null
          failed_count?: number
          id?: string
          started_at?: string | null
          status?: string
          success_count?: number
          update_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "platform_update_broadcasts_update_id_fkey"
            columns: ["update_id"]
            isOneToOne: true
            referencedRelation: "platform_updates"
            referencedColumns: ["id"]
          },
        ]
      }
      platform_updates: {
        Row: {
          body: string
          category: string
          created_at: string
          created_by: string | null
          destination: string
          id: string
          publish_at: string | null
          published_at: string | null
          send_push: boolean
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          body: string
          category: string
          created_at?: string
          created_by?: string | null
          destination: string
          id?: string
          publish_at?: string | null
          published_at?: string | null
          send_push?: boolean
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          body?: string
          category?: string
          created_at?: string
          created_by?: string | null
          destination?: string
          id?: string
          publish_at?: string | null
          published_at?: string | null
          send_push?: boolean
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      posts: {
        Row: {
          caption: string | null
          created_at: string | null
          id: string
          image_crop: Json | null
          image_url: string | null
          pnl: number | null
          rr: number | null
          trade_id: string | null
          user_id: string | null
        }
        Insert: {
          caption?: string | null
          created_at?: string | null
          id?: string
          image_crop?: Json | null
          image_url?: string | null
          pnl?: number | null
          rr?: number | null
          trade_id?: string | null
          user_id?: string | null
        }
        Update: {
          caption?: string | null
          created_at?: string | null
          id?: string
          image_crop?: Json | null
          image_url?: string | null
          pnl?: number | null
          rr?: number | null
          trade_id?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "posts_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: true
            referencedRelation: "trades"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "posts_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: true
            referencedRelation: "trades_public_read"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "posts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      presets: {
        Row: {
          created_at: string | null
          id: string
          name: string
          user_id: string | null
          values: Json
        }
        Insert: {
          created_at?: string | null
          id?: string
          name: string
          user_id?: string | null
          values: Json
        }
        Update: {
          created_at?: string | null
          id?: string
          name?: string
          user_id?: string | null
          values?: Json
        }
        Relationships: []
      }
      pro_for_life_awards: {
        Row: {
          award_type: string
          awarded_at: string
          campaign_key: string
          challenge_version: number
          environment: string
          follow_count: number
          public_trade_day_count: number
          referral_count: number
          referral_user_id: string | null
          user_id: string
        }
        Insert: {
          award_type?: string
          awarded_at?: string
          campaign_key: string
          challenge_version: number
          environment: string
          follow_count: number
          public_trade_day_count: number
          referral_count: number
          referral_user_id?: string | null
          user_id: string
        }
        Update: {
          award_type?: string
          awarded_at?: string
          campaign_key?: string
          challenge_version?: number
          environment?: string
          follow_count?: number
          public_trade_day_count?: number
          referral_count?: number
          referral_user_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pro_for_life_awards_campaign_environment_fkey"
            columns: ["campaign_key", "environment"]
            isOneToOne: false
            referencedRelation: "early_access_campaigns"
            referencedColumns: ["campaign_key", "environment"]
          },
          {
            foreignKeyName: "pro_for_life_awards_referral_user_id_fkey"
            columns: ["referral_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pro_for_life_awards_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_pinned_content: {
        Row: {
          content_id: string
          content_type: string
          created_at: string
          id: string
          position: number
          user_id: string
        }
        Insert: {
          content_id: string
          content_type: string
          created_at?: string
          id?: string
          position: number
          user_id: string
        }
        Update: {
          content_id?: string
          content_type?: string
          created_at?: string
          id?: string
          position?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "profile_pinned_content_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_post_comments: {
        Row: {
          content: string
          created_at: string
          id: string
          parent_comment_id: string | null
          pinned: boolean
          profile_post_id: string
          user_id: string
        }
        Insert: {
          content: string
          created_at?: string
          id?: string
          parent_comment_id?: string | null
          pinned?: boolean
          profile_post_id: string
          user_id: string
        }
        Update: {
          content?: string
          created_at?: string
          id?: string
          parent_comment_id?: string | null
          pinned?: boolean
          profile_post_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "profile_post_comments_parent_comment_id_fkey"
            columns: ["parent_comment_id"]
            isOneToOne: false
            referencedRelation: "profile_post_comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_post_comments_profile_post_id_fkey"
            columns: ["profile_post_id"]
            isOneToOne: false
            referencedRelation: "profile_posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_post_comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_post_likes: {
        Row: {
          created_at: string
          id: string
          profile_post_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          profile_post_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          profile_post_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "profile_post_likes_profile_post_id_fkey"
            columns: ["profile_post_id"]
            isOneToOne: false
            referencedRelation: "profile_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_posts: {
        Row: {
          content: string | null
          created_at: string | null
          id: string
          image_crop: Json | null
          image_url: string | null
          is_pinned: boolean | null
          room_description: string | null
          room_id: string | null
          room_logo: string | null
          room_name: string | null
          user_id: string | null
        }
        Insert: {
          content?: string | null
          created_at?: string | null
          id?: string
          image_crop?: Json | null
          image_url?: string | null
          is_pinned?: boolean | null
          room_description?: string | null
          room_id?: string | null
          room_logo?: string | null
          room_name?: string | null
          user_id?: string | null
        }
        Update: {
          content?: string | null
          created_at?: string | null
          id?: string
          image_crop?: Json | null
          image_url?: string | null
          is_pinned?: boolean | null
          room_description?: string | null
          room_id?: string | null
          room_logo?: string | null
          room_name?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "profile_posts_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_posts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_public_analytics_state: {
        Row: {
          revision: number
          updated_at: string
          user_id: string
        }
        Insert: {
          revision?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          revision?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "profile_public_analytics_state_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          avatar_url: string | null
          banned_at: string | null
          banned_by: string | null
          banned_reason: string | null
          beta_signup_notified_at: string | null
          billing_interval: string | null
          bio: string | null
          cancel_at: string | null
          cancel_at_period_end: boolean | null
          created_at: string | null
          creator_access: boolean
          creator_code: string | null
          creator_granted_at: string | null
          current_period_end: string | null
          dm_privacy: string
          early_access_campaign_id: string | null
          early_access_ends_at: string | null
          early_access_enrolled_at: string | null
          early_access_enrollment_source: string | null
          early_access_started_at: string | null
          early_access_status: string | null
          experience: string | null
          has_email_password: boolean
          has_seen_getting_started_intro: boolean
          has_seen_onboarding_complete_popup: boolean
          has_used_csv_import: boolean | null
          has_used_initial_import: boolean | null
          id: string
          is_banned: boolean
          is_beta_tester: boolean
          is_private: boolean | null
          is_pro: boolean | null
          last_csv_import_at: string | null
          lifetime_access_granted_at: string | null
          lifetime_access_source: string | null
          locked_account_id: string | null
          locked_account_name: string | null
          locked_account_number: string | null
          locked_account_size: string | null
          locked_account_type: string | null
          max_drawdown_limit: number | null
          name: string | null
          onboarding_completed: boolean | null
          primary_market: string | null
          referral_code: string | null
          referral_count: number | null
          referral_earnings: number
          referred_by: string | null
          signup_flow_source: string | null
          started_trading: string | null
          stripe_customer_id: string | null
          stripe_price_id: string | null
          subscription_status: string | null
          trader_type: string | null
          trading_model: string | null
          trading_style: string | null
          tradovate_login_import_reminder_opt_out: boolean
          trial_end: string | null
          use_free_tier: boolean
          username: string | null
          username_change_count: number
        }
        Insert: {
          avatar_url?: string | null
          banned_at?: string | null
          banned_by?: string | null
          banned_reason?: string | null
          beta_signup_notified_at?: string | null
          billing_interval?: string | null
          bio?: string | null
          cancel_at?: string | null
          cancel_at_period_end?: boolean | null
          created_at?: string | null
          creator_access?: boolean
          creator_code?: string | null
          creator_granted_at?: string | null
          current_period_end?: string | null
          dm_privacy?: string
          early_access_campaign_id?: string | null
          early_access_ends_at?: string | null
          early_access_enrolled_at?: string | null
          early_access_enrollment_source?: string | null
          early_access_started_at?: string | null
          early_access_status?: string | null
          experience?: string | null
          has_email_password?: boolean
          has_seen_getting_started_intro?: boolean
          has_seen_onboarding_complete_popup?: boolean
          has_used_csv_import?: boolean | null
          has_used_initial_import?: boolean | null
          id: string
          is_banned?: boolean
          is_beta_tester?: boolean
          is_private?: boolean | null
          is_pro?: boolean | null
          last_csv_import_at?: string | null
          lifetime_access_granted_at?: string | null
          lifetime_access_source?: string | null
          locked_account_id?: string | null
          locked_account_name?: string | null
          locked_account_number?: string | null
          locked_account_size?: string | null
          locked_account_type?: string | null
          max_drawdown_limit?: number | null
          name?: string | null
          onboarding_completed?: boolean | null
          primary_market?: string | null
          referral_code?: string | null
          referral_count?: number | null
          referral_earnings?: number
          referred_by?: string | null
          signup_flow_source?: string | null
          started_trading?: string | null
          stripe_customer_id?: string | null
          stripe_price_id?: string | null
          subscription_status?: string | null
          trader_type?: string | null
          trading_model?: string | null
          trading_style?: string | null
          tradovate_login_import_reminder_opt_out?: boolean
          trial_end?: string | null
          use_free_tier?: boolean
          username?: string | null
          username_change_count?: number
        }
        Update: {
          avatar_url?: string | null
          banned_at?: string | null
          banned_by?: string | null
          banned_reason?: string | null
          beta_signup_notified_at?: string | null
          billing_interval?: string | null
          bio?: string | null
          cancel_at?: string | null
          cancel_at_period_end?: boolean | null
          created_at?: string | null
          creator_access?: boolean
          creator_code?: string | null
          creator_granted_at?: string | null
          current_period_end?: string | null
          dm_privacy?: string
          early_access_campaign_id?: string | null
          early_access_ends_at?: string | null
          early_access_enrolled_at?: string | null
          early_access_enrollment_source?: string | null
          early_access_started_at?: string | null
          early_access_status?: string | null
          experience?: string | null
          has_email_password?: boolean
          has_seen_getting_started_intro?: boolean
          has_seen_onboarding_complete_popup?: boolean
          has_used_csv_import?: boolean | null
          has_used_initial_import?: boolean | null
          id?: string
          is_banned?: boolean
          is_beta_tester?: boolean
          is_private?: boolean | null
          is_pro?: boolean | null
          last_csv_import_at?: string | null
          lifetime_access_granted_at?: string | null
          lifetime_access_source?: string | null
          locked_account_id?: string | null
          locked_account_name?: string | null
          locked_account_number?: string | null
          locked_account_size?: string | null
          locked_account_type?: string | null
          max_drawdown_limit?: number | null
          name?: string | null
          onboarding_completed?: boolean | null
          primary_market?: string | null
          referral_code?: string | null
          referral_count?: number | null
          referral_earnings?: number
          referred_by?: string | null
          signup_flow_source?: string | null
          started_trading?: string | null
          stripe_customer_id?: string | null
          stripe_price_id?: string | null
          subscription_status?: string | null
          trader_type?: string | null
          trading_model?: string | null
          trading_style?: string | null
          tradovate_login_import_reminder_opt_out?: boolean
          trial_end?: string | null
          use_free_tier?: boolean
          username?: string | null
          username_change_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "profiles_banned_by_fkey"
            columns: ["banned_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      psychology_coach_snapshots: {
        Row: {
          ai_explanation: string | null
          facts_hash: string
          generated_at: string
          summary_json: Json
          updated_at: string
          user_id: string
        }
        Insert: {
          ai_explanation?: string | null
          facts_hash: string
          generated_at?: string
          summary_json?: Json
          updated_at?: string
          user_id: string
        }
        Update: {
          ai_explanation?: string | null
          facts_hash?: string
          generated_at?: string
          summary_json?: Json
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "psychology_coach_snapshots_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      psychology_report_ai_cache: {
        Row: {
          ai_summary: string
          facts_hash: string
          generated_at: string
          report_id: string
          user_id: string
        }
        Insert: {
          ai_summary: string
          facts_hash: string
          generated_at?: string
          report_id: string
          user_id: string
        }
        Update: {
          ai_summary?: string
          facts_hash?: string
          generated_at?: string
          report_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "psychology_report_ai_cache_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      public_contact_submissions: {
        Row: {
          category: string
          created_at: string
          email: string
          id: string
          message: string
          name: string
          subject: string
          user_id: string | null
        }
        Insert: {
          category: string
          created_at?: string
          email: string
          id?: string
          message: string
          name: string
          subject: string
          user_id?: string | null
        }
        Update: {
          category?: string
          created_at?: string
          email?: string
          id?: string
          message?: string
          name?: string
          subject?: string
          user_id?: string | null
        }
        Relationships: []
      }
      rate_limit_counters: {
        Row: {
          action: string
          count: number
          user_id: string
          window_seconds: number
          window_start: string
          windows: Json
        }
        Insert: {
          action: string
          count?: number
          user_id: string
          window_seconds: number
          window_start: string
          windows?: Json
        }
        Update: {
          action?: string
          count?: number
          user_id?: string
          window_seconds?: number
          window_start?: string
          windows?: Json
        }
        Relationships: []
      }
      rate_limit_rules: {
        Row: {
          action: string
          max_count: number
          window_seconds: number
        }
        Insert: {
          action: string
          max_count: number
          window_seconds: number
        }
        Update: {
          action?: string
          max_count?: number
          window_seconds?: number
        }
        Relationships: []
      }
      reel_comments: {
        Row: {
          content: string
          created_at: string
          id: string
          parent_comment_id: string | null
          pinned: boolean
          reel_id: string
          user_id: string
        }
        Insert: {
          content: string
          created_at?: string
          id?: string
          parent_comment_id?: string | null
          pinned?: boolean
          reel_id: string
          user_id: string
        }
        Update: {
          content?: string
          created_at?: string
          id?: string
          parent_comment_id?: string | null
          pinned?: boolean
          reel_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "reel_comments_parent_comment_id_fkey"
            columns: ["parent_comment_id"]
            isOneToOne: false
            referencedRelation: "reel_comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reel_comments_reel_id_fkey"
            columns: ["reel_id"]
            isOneToOne: false
            referencedRelation: "reels"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reel_comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      reel_likes: {
        Row: {
          created_at: string
          id: string
          reel_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          reel_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          reel_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "reel_likes_reel_id_fkey"
            columns: ["reel_id"]
            isOneToOne: false
            referencedRelation: "reels"
            referencedColumns: ["id"]
          },
        ]
      }
      reels: {
        Row: {
          caption: string | null
          created_at: string
          duration_seconds: number | null
          id: string
          kind: string | null
          thumbnail_url: string
          trade_id: string | null
          updated_at: string
          user_id: string
          video_url: string
          visibility: string
        }
        Insert: {
          caption?: string | null
          created_at?: string
          duration_seconds?: number | null
          id?: string
          kind?: string | null
          thumbnail_url: string
          trade_id?: string | null
          updated_at?: string
          user_id: string
          video_url: string
          visibility?: string
        }
        Update: {
          caption?: string | null
          created_at?: string
          duration_seconds?: number | null
          id?: string
          kind?: string | null
          thumbnail_url?: string
          trade_id?: string | null
          updated_at?: string
          user_id?: string
          video_url?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "reels_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: false
            referencedRelation: "trades"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reels_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: false
            referencedRelation: "trades_public_read"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reels_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      referrals: {
        Row: {
          amount_earned: number
          commission_rate: number | null
          created_at: string
          currency: string | null
          id: string
          referred_user_id: string
          referrer_user_id: string
          stripe_customer_id: string | null
          stripe_invoice_id: string | null
          stripe_price_id: string | null
          stripe_subscription_id: string | null
          transaction_amount: number | null
        }
        Insert: {
          amount_earned?: number
          commission_rate?: number | null
          created_at?: string
          currency?: string | null
          id?: string
          referred_user_id: string
          referrer_user_id: string
          stripe_customer_id?: string | null
          stripe_invoice_id?: string | null
          stripe_price_id?: string | null
          stripe_subscription_id?: string | null
          transaction_amount?: number | null
        }
        Update: {
          amount_earned?: number
          commission_rate?: number | null
          created_at?: string
          currency?: string | null
          id?: string
          referred_user_id?: string
          referrer_user_id?: string
          stripe_customer_id?: string | null
          stripe_invoice_id?: string | null
          stripe_price_id?: string | null
          stripe_subscription_id?: string | null
          transaction_amount?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "referrals_referred_user_id_fkey"
            columns: ["referred_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referrals_referrer_user_id_fkey"
            columns: ["referrer_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      room_bans: {
        Row: {
          banned_by: string
          created_at: string
          id: string
          room_id: string
          user_id: string
        }
        Insert: {
          banned_by: string
          created_at?: string
          id?: string
          room_id: string
          user_id: string
        }
        Update: {
          banned_by?: string
          created_at?: string
          id?: string
          room_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "room_bans_banned_by_fkey"
            columns: ["banned_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_bans_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_bans_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      room_join_requests: {
        Row: {
          created_at: string
          id: string
          resolved_at: string | null
          resolved_by: string | null
          room_id: string
          status: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          resolved_at?: string | null
          resolved_by?: string | null
          room_id: string
          status?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          resolved_at?: string | null
          resolved_by?: string | null
          room_id?: string
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "room_join_requests_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_join_requests_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_join_requests_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      room_member_channel_preferences: {
        Row: {
          created_at: string
          id: string
          notifications_enabled: boolean
          room_id: string
          section_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          notifications_enabled?: boolean
          room_id: string
          section_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          notifications_enabled?: boolean
          room_id?: string
          section_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "room_member_channel_preferences_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_member_channel_preferences_section_id_fkey"
            columns: ["section_id"]
            isOneToOne: false
            referencedRelation: "room_sections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_member_channel_preferences_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      room_member_tag_assignments: {
        Row: {
          created_at: string
          room_id: string
          tag_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          room_id: string
          tag_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          room_id?: string
          tag_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "room_member_tag_assignments_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_member_tag_assignments_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "room_member_tags"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_member_tag_assignments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      room_member_tags: {
        Row: {
          color_key: string
          created_at: string
          created_by: string | null
          id: string
          is_preset: boolean
          name: string
          room_id: string
        }
        Insert: {
          color_key?: string
          created_at?: string
          created_by?: string | null
          id?: string
          is_preset?: boolean
          name: string
          room_id: string
        }
        Update: {
          color_key?: string
          created_at?: string
          created_by?: string | null
          id?: string
          is_preset?: boolean
          name?: string
          room_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "room_member_tags_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_member_tags_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      room_members: {
        Row: {
          created_at: string | null
          id: string
          last_read_at: string | null
          last_read_message_id: string | null
          left_at: string | null
          notification_enabled: boolean
          room_id: string | null
          user_id: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          last_read_at?: string | null
          last_read_message_id?: string | null
          left_at?: string | null
          notification_enabled?: boolean
          room_id?: string | null
          user_id?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
          last_read_at?: string | null
          last_read_message_id?: string | null
          left_at?: string | null
          notification_enabled?: boolean
          room_id?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "room_members_last_read_message_id_fkey"
            columns: ["last_read_message_id"]
            isOneToOne: false
            referencedRelation: "room_messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_members_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      room_message_reactions: {
        Row: {
          created_at: string
          id: string
          message_id: string
          reaction: string
          room_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          message_id: string
          reaction: string
          room_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          message_id?: string
          reaction?: string
          room_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "room_message_reactions_message_room_fkey"
            columns: ["message_id", "room_id"]
            isOneToOne: false
            referencedRelation: "room_messages"
            referencedColumns: ["id", "room_id"]
          },
          {
            foreignKeyName: "room_message_reactions_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_message_reactions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      room_messages: {
        Row: {
          audio_duration_ms: number | null
          audio_url: string | null
          content: string | null
          created_at: string | null
          id: string
          image_url: string | null
          parent_message_id: string | null
          pinned: boolean | null
          pinned_trade_id: string | null
          room_id: string | null
          section_id: string | null
          seen_by: Json | null
          trade_id: string | null
          type: string | null
          user_id: string | null
        }
        Insert: {
          audio_duration_ms?: number | null
          audio_url?: string | null
          content?: string | null
          created_at?: string | null
          id?: string
          image_url?: string | null
          parent_message_id?: string | null
          pinned?: boolean | null
          pinned_trade_id?: string | null
          room_id?: string | null
          section_id?: string | null
          seen_by?: Json | null
          trade_id?: string | null
          type?: string | null
          user_id?: string | null
        }
        Update: {
          audio_duration_ms?: number | null
          audio_url?: string | null
          content?: string | null
          created_at?: string | null
          id?: string
          image_url?: string | null
          parent_message_id?: string | null
          pinned?: boolean | null
          pinned_trade_id?: string | null
          room_id?: string | null
          section_id?: string | null
          seen_by?: Json | null
          trade_id?: string | null
          type?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "room_messages_parent_message_id_fkey"
            columns: ["parent_message_id"]
            isOneToOne: false
            referencedRelation: "room_messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_messages_pinned_trade_id_fkey"
            columns: ["pinned_trade_id"]
            isOneToOne: false
            referencedRelation: "trades"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_messages_pinned_trade_id_fkey"
            columns: ["pinned_trade_id"]
            isOneToOne: false
            referencedRelation: "trades_public_read"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_messages_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_messages_section_id_fkey"
            columns: ["section_id"]
            isOneToOne: false
            referencedRelation: "room_sections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_messages_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: false
            referencedRelation: "trades"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_messages_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: false
            referencedRelation: "trades_public_read"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_messages_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      room_presence: {
        Row: {
          id: string
          last_seen: string | null
          room_id: string | null
          user_id: string | null
        }
        Insert: {
          id?: string
          last_seen?: string | null
          room_id?: string | null
          user_id?: string | null
        }
        Update: {
          id?: string
          last_seen?: string | null
          room_id?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "room_presence_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_presence_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      room_sections: {
        Row: {
          allow_members_chat: boolean | null
          created_at: string | null
          id: string
          name: string
          position: number
          room_id: string | null
        }
        Insert: {
          allow_members_chat?: boolean | null
          created_at?: string | null
          id?: string
          name: string
          position?: number
          room_id?: string | null
        }
        Update: {
          allow_members_chat?: boolean | null
          created_at?: string | null
          id?: string
          name?: string
          position?: number
          room_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "room_sections_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      rooms: {
        Row: {
          allow_members_chat: boolean | null
          category: string | null
          created_at: string | null
          description: string | null
          discovery_tags: string[]
          id: string
          image_url: string | null
          is_private: boolean | null
          join_policy: string
          members_can_message: boolean
          members_can_share_media: boolean
          members_can_share_trades: boolean
          name: string
          owner_user_id: string | null
          room_kind: string
          rules: string | null
          show_on_profile: boolean | null
          slug: string | null
        }
        Insert: {
          allow_members_chat?: boolean | null
          category?: string | null
          created_at?: string | null
          description?: string | null
          discovery_tags?: string[]
          id?: string
          image_url?: string | null
          is_private?: boolean | null
          join_policy?: string
          members_can_message?: boolean
          members_can_share_media?: boolean
          members_can_share_trades?: boolean
          name: string
          owner_user_id?: string | null
          room_kind?: string
          rules?: string | null
          show_on_profile?: boolean | null
          slug?: string | null
        }
        Update: {
          allow_members_chat?: boolean | null
          category?: string | null
          created_at?: string | null
          description?: string | null
          discovery_tags?: string[]
          id?: string
          image_url?: string | null
          is_private?: boolean | null
          join_policy?: string
          members_can_message?: boolean
          members_can_share_media?: boolean
          members_can_share_trades?: boolean
          name?: string
          owner_user_id?: string | null
          room_kind?: string
          rules?: string | null
          show_on_profile?: boolean | null
          slug?: string | null
        }
        Relationships: []
      }
      saved_posts: {
        Row: {
          created_at: string | null
          id: string
          post_id: string | null
          user_id: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          post_id?: string | null
          user_id?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
          post_id?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "saved_posts_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "profile_posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "saved_posts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      saved_trades: {
        Row: {
          created_at: string | null
          id: string
          trade_id: string | null
          user_id: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          trade_id?: string | null
          user_id?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
          trade_id?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "saved_trades_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: false
            referencedRelation: "trades"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "saved_trades_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: false
            referencedRelation: "trades_public_read"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "saved_trades_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      settings: {
        Row: {
          id: string
          max_daily_loss: number | null
          max_loss_enabled: boolean | null
          max_loss_streak: number | null
          max_loss_streak_enabled: boolean | null
          min_rr: number | null
          min_rr_enabled: boolean | null
          overtrading_enabled: boolean | null
          overtrading_limit: number | null
          preferred_session: string | null
          session_focus_enabled: boolean | null
          user_id: string | null
        }
        Insert: {
          id?: string
          max_daily_loss?: number | null
          max_loss_enabled?: boolean | null
          max_loss_streak?: number | null
          max_loss_streak_enabled?: boolean | null
          min_rr?: number | null
          min_rr_enabled?: boolean | null
          overtrading_enabled?: boolean | null
          overtrading_limit?: number | null
          preferred_session?: string | null
          session_focus_enabled?: boolean | null
          user_id?: string | null
        }
        Update: {
          id?: string
          max_daily_loss?: number | null
          max_loss_enabled?: boolean | null
          max_loss_streak?: number | null
          max_loss_streak_enabled?: boolean | null
          min_rr?: number | null
          min_rr_enabled?: boolean | null
          overtrading_enabled?: boolean | null
          overtrading_limit?: number | null
          preferred_session?: string | null
          session_focus_enabled?: boolean | null
          user_id?: string | null
        }
        Relationships: []
      }
      stories: {
        Row: {
          created_at: string | null
          id: string
          image_url: string | null
          user_id: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          image_url?: string | null
          user_id?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
          image_url?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "stories_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      support_tickets: {
        Row: {
          admin_notes: string | null
          category: string
          created_at: string
          email: string | null
          id: string
          message: string
          priority: string
          screenshot_url: string | null
          status: string
          subject: string
          updated_at: string
          user_id: string | null
          viewed: boolean
          viewed_at: string | null
          viewed_by: string | null
        }
        Insert: {
          admin_notes?: string | null
          category?: string
          created_at?: string
          email?: string | null
          id?: string
          message: string
          priority?: string
          screenshot_url?: string | null
          status?: string
          subject: string
          updated_at?: string
          user_id?: string | null
          viewed?: boolean
          viewed_at?: string | null
          viewed_by?: string | null
        }
        Update: {
          admin_notes?: string | null
          category?: string
          created_at?: string
          email?: string | null
          id?: string
          message?: string
          priority?: string
          screenshot_url?: string | null
          status?: string
          subject?: string
          updated_at?: string
          user_id?: string | null
          viewed?: boolean
          viewed_at?: string | null
          viewed_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "support_tickets_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "support_tickets_viewed_by_fkey"
            columns: ["viewed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      trade_comments: {
        Row: {
          content: string | null
          created_at: string | null
          id: string
          parent_comment_id: string | null
          pinned: boolean
          trade_id: string | null
          user_id: string | null
        }
        Insert: {
          content?: string | null
          created_at?: string | null
          id?: string
          parent_comment_id?: string | null
          pinned?: boolean
          trade_id?: string | null
          user_id?: string | null
        }
        Update: {
          content?: string | null
          created_at?: string | null
          id?: string
          parent_comment_id?: string | null
          pinned?: boolean
          trade_id?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "trade_comments_parent_comment_id_fkey"
            columns: ["parent_comment_id"]
            isOneToOne: false
            referencedRelation: "trade_comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trade_comments_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: false
            referencedRelation: "trades"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trade_comments_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: false
            referencedRelation: "trades_public_read"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trade_comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      trade_daily_stats: {
        Row: {
          account_id: string | null
          breakeven_count: number
          calendar_day: string
          gross_loss: number
          gross_profit: number
          hold_count: number
          id: number
          largest_loss: number | null
          largest_win: number | null
          long_count: number
          long_pnl: number
          loss_count: number
          mode_effective: string
          net_pnl: number
          rr_count: number
          short_count: number
          short_pnl: number
          sum_hold_seconds: number
          sum_rr: number
          trade_count: number
          updated_at: string
          user_id: string
          win_count: number
        }
        Insert: {
          account_id?: string | null
          breakeven_count?: number
          calendar_day: string
          gross_loss?: number
          gross_profit?: number
          hold_count?: number
          id?: never
          largest_loss?: number | null
          largest_win?: number | null
          long_count?: number
          long_pnl?: number
          loss_count?: number
          mode_effective: string
          net_pnl?: number
          rr_count?: number
          short_count?: number
          short_pnl?: number
          sum_hold_seconds?: number
          sum_rr?: number
          trade_count?: number
          updated_at?: string
          user_id: string
          win_count?: number
        }
        Update: {
          account_id?: string | null
          breakeven_count?: number
          calendar_day?: string
          gross_loss?: number
          gross_profit?: number
          hold_count?: number
          id?: never
          largest_loss?: number | null
          largest_win?: number | null
          long_count?: number
          long_pnl?: number
          loss_count?: number
          mode_effective?: string
          net_pnl?: number
          rr_count?: number
          short_count?: number
          short_pnl?: number
          sum_hold_seconds?: number
          sum_rr?: number
          trade_count?: number
          updated_at?: string
          user_id?: string
          win_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "trade_daily_stats_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      trade_likes: {
        Row: {
          created_at: string | null
          id: string
          trade_id: string | null
          user_id: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          trade_id?: string | null
          user_id?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
          trade_id?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "trade_likes_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: false
            referencedRelation: "trades"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trade_likes_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: false
            referencedRelation: "trades_public_read"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trade_likes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      trade_public_daily_stats: {
        Row: {
          account_id: string | null
          breakeven_count: number
          calendar_day: string
          gross_loss: number
          gross_profit: number
          hold_count: number
          id: number
          largest_loss: number | null
          largest_win: number | null
          long_count: number
          long_pnl: number
          loss_count: number
          mode_effective: string
          net_pnl: number
          rr_count: number
          short_count: number
          short_pnl: number
          sum_hold_seconds: number
          sum_rr: number
          trade_count: number
          updated_at: string
          user_id: string
          win_count: number
        }
        Insert: {
          account_id?: string | null
          breakeven_count?: number
          calendar_day: string
          gross_loss?: number
          gross_profit?: number
          hold_count?: number
          id?: never
          largest_loss?: number | null
          largest_win?: number | null
          long_count?: number
          long_pnl?: number
          loss_count?: number
          mode_effective: string
          net_pnl?: number
          rr_count?: number
          short_count?: number
          short_pnl?: number
          sum_hold_seconds?: number
          sum_rr?: number
          trade_count?: number
          updated_at?: string
          user_id: string
          win_count?: number
        }
        Update: {
          account_id?: string | null
          breakeven_count?: number
          calendar_day?: string
          gross_loss?: number
          gross_profit?: number
          hold_count?: number
          id?: never
          largest_loss?: number | null
          largest_win?: number | null
          long_count?: number
          long_pnl?: number
          loss_count?: number
          mode_effective?: string
          net_pnl?: number
          rr_count?: number
          short_count?: number
          short_pnl?: number
          sum_hold_seconds?: number
          sum_rr?: number
          trade_count?: number
          updated_at?: string
          user_id?: string
          win_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "trade_public_daily_stats_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      trader_daily_check_ins: {
        Row: {
          check_in_date: string
          created_at: string
          energy_level: number | null
          focus_level: number | null
          id: string
          morning_rating: number | null
          notes: string | null
          sleep_hours: number | null
          sleep_quality: number | null
          stress_level: number | null
          updated_at: string
          user_id: string
        }
        Insert: {
          check_in_date: string
          created_at?: string
          energy_level?: number | null
          focus_level?: number | null
          id?: string
          morning_rating?: number | null
          notes?: string | null
          sleep_hours?: number | null
          sleep_quality?: number | null
          stress_level?: number | null
          updated_at?: string
          user_id: string
        }
        Update: {
          check_in_date?: string
          created_at?: string
          energy_level?: number | null
          focus_level?: number | null
          id?: string
          morning_rating?: number | null
          notes?: string | null
          sleep_hours?: number | null
          sleep_quality?: number | null
          stress_level?: number | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "trader_daily_check_ins_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      trades: {
        Row: {
          account_category: string | null
          account_id: string | null
          account_name: string | null
          account_size: string | null
          account_type: string | null
          ai_feedback: string | null
          ai_feedback_created_at: string | null
          broker_connection_id: string | null
          broker_enrichment_status: string | null
          broker_integration_account_id: string | null
          broker_lifecycle_id: string | null
          confidence: number | null
          contracts: number | null
          copied_account_ids: string[]
          copy_trading_group_id: string | null
          created_at: string | null
          date: string | null
          direction: string | null
          duration_seconds: number | null
          duration_text: string | null
          emotion: string | null
          entry_price: number | null
          entry_time: string | null
          execution_rating: number | null
          exit_emotion: string | null
          exit_price: number | null
          exit_time: string | null
          first_published_at: string | null
          followed_plan: boolean | null
          id: string
          image_crop: Json | null
          image_display_mode: string
          image_url: string | null
          import_fingerprint: string | null
          import_source: string | null
          is_initial_import: boolean | null
          is_pinned: boolean | null
          is_public: boolean | null
          last_broker_sync_at: string | null
          market_condition: string | null
          mistake_type: string | null
          mode: string | null
          news_event: boolean | null
          notes: string | null
          pnl: number | null
          points: number | null
          psychology_notes: string | null
          public_description: string | null
          reviewed: boolean | null
          rr: number | null
          session: string | null
          source_account_id: string | null
          strategy: string | null
          ticker: string | null
          timeframe: string | null
          top_confluences: string | null
          trade_date: string | null
          trade_mode: string | null
          trade_type: string | null
          user_id: string | null
        }
        Insert: {
          account_category?: string | null
          account_id?: string | null
          account_name?: string | null
          account_size?: string | null
          account_type?: string | null
          ai_feedback?: string | null
          ai_feedback_created_at?: string | null
          broker_connection_id?: string | null
          broker_enrichment_status?: string | null
          broker_integration_account_id?: string | null
          broker_lifecycle_id?: string | null
          confidence?: number | null
          contracts?: number | null
          copied_account_ids?: string[]
          copy_trading_group_id?: string | null
          created_at?: string | null
          date?: string | null
          direction?: string | null
          duration_seconds?: number | null
          duration_text?: string | null
          emotion?: string | null
          entry_price?: number | null
          entry_time?: string | null
          execution_rating?: number | null
          exit_emotion?: string | null
          exit_price?: number | null
          exit_time?: string | null
          first_published_at?: string | null
          followed_plan?: boolean | null
          id?: string
          image_crop?: Json | null
          image_display_mode?: string
          image_url?: string | null
          import_fingerprint?: string | null
          import_source?: string | null
          is_initial_import?: boolean | null
          is_pinned?: boolean | null
          is_public?: boolean | null
          last_broker_sync_at?: string | null
          market_condition?: string | null
          mistake_type?: string | null
          mode?: string | null
          news_event?: boolean | null
          notes?: string | null
          pnl?: number | null
          points?: number | null
          psychology_notes?: string | null
          public_description?: string | null
          reviewed?: boolean | null
          rr?: number | null
          session?: string | null
          source_account_id?: string | null
          strategy?: string | null
          ticker?: string | null
          timeframe?: string | null
          top_confluences?: string | null
          trade_date?: string | null
          trade_mode?: string | null
          trade_type?: string | null
          user_id?: string | null
        }
        Update: {
          account_category?: string | null
          account_id?: string | null
          account_name?: string | null
          account_size?: string | null
          account_type?: string | null
          ai_feedback?: string | null
          ai_feedback_created_at?: string | null
          broker_connection_id?: string | null
          broker_enrichment_status?: string | null
          broker_integration_account_id?: string | null
          broker_lifecycle_id?: string | null
          confidence?: number | null
          contracts?: number | null
          copied_account_ids?: string[]
          copy_trading_group_id?: string | null
          created_at?: string | null
          date?: string | null
          direction?: string | null
          duration_seconds?: number | null
          duration_text?: string | null
          emotion?: string | null
          entry_price?: number | null
          entry_time?: string | null
          execution_rating?: number | null
          exit_emotion?: string | null
          exit_price?: number | null
          exit_time?: string | null
          first_published_at?: string | null
          followed_plan?: boolean | null
          id?: string
          image_crop?: Json | null
          image_display_mode?: string
          image_url?: string | null
          import_fingerprint?: string | null
          import_source?: string | null
          is_initial_import?: boolean | null
          is_pinned?: boolean | null
          is_public?: boolean | null
          last_broker_sync_at?: string | null
          market_condition?: string | null
          mistake_type?: string | null
          mode?: string | null
          news_event?: boolean | null
          notes?: string | null
          pnl?: number | null
          points?: number | null
          psychology_notes?: string | null
          public_description?: string | null
          reviewed?: boolean | null
          rr?: number | null
          session?: string | null
          source_account_id?: string | null
          strategy?: string | null
          ticker?: string | null
          timeframe?: string | null
          top_confluences?: string | null
          trade_date?: string | null
          trade_mode?: string | null
          trade_type?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "trades_broker_connection_id_fkey"
            columns: ["broker_connection_id"]
            isOneToOne: false
            referencedRelation: "broker_integration_connections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trades_broker_integration_account_id_fkey"
            columns: ["broker_integration_account_id"]
            isOneToOne: false
            referencedRelation: "broker_integration_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trades_copy_trading_group_id_fkey"
            columns: ["copy_trading_group_id"]
            isOneToOne: false
            referencedRelation: "copy_trading_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trades_source_account_id_fkey"
            columns: ["source_account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      user_accounts: {
        Row: {
          account_name: string
          account_type: string
          created_at: string | null
          id: string
          user_id: string | null
        }
        Insert: {
          account_name: string
          account_type?: string
          created_at?: string | null
          id?: string
          user_id?: string | null
        }
        Update: {
          account_name?: string
          account_type?: string
          created_at?: string | null
          id?: string
          user_id?: string | null
        }
        Relationships: []
      }
      user_analytics_state: {
        Row: {
          revision: number
          updated_at: string
          user_id: string
        }
        Insert: {
          revision?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          revision?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_analytics_state_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      user_blocks: {
        Row: {
          blocked_id: string
          blocker_id: string
          created_at: string
        }
        Insert: {
          blocked_id: string
          blocker_id: string
          created_at?: string
        }
        Update: {
          blocked_id?: string
          blocker_id?: string
          created_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_blocks_blocked_id_fkey"
            columns: ["blocked_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_blocks_blocker_id_fkey"
            columns: ["blocker_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      user_reviews: {
        Row: {
          avatar_snapshot: string | null
          created_at: string
          display_name: string | null
          featured: boolean
          id: string
          rating: number
          review: string
          status: string
          title: string | null
          updated_at: string
          user_id: string
          username_snapshot: string | null
          version: number
          would_recommend: boolean
        }
        Insert: {
          avatar_snapshot?: string | null
          created_at?: string
          display_name?: string | null
          featured?: boolean
          id?: string
          rating: number
          review: string
          status?: string
          title?: string | null
          updated_at?: string
          user_id: string
          username_snapshot?: string | null
          version?: number
          would_recommend?: boolean
        }
        Update: {
          avatar_snapshot?: string | null
          created_at?: string
          display_name?: string | null
          featured?: boolean
          id?: string
          rating?: number
          review?: string
          status?: string
          title?: string | null
          updated_at?: string
          user_id?: string
          username_snapshot?: string | null
          version?: number
          would_recommend?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "user_reviews_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      vault_folder_items: {
        Row: {
          created_at: string
          folder_id: string
          vault_item_id: string
        }
        Insert: {
          created_at?: string
          folder_id: string
          vault_item_id: string
        }
        Update: {
          created_at?: string
          folder_id?: string
          vault_item_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vault_folder_items_folder_id_fkey"
            columns: ["folder_id"]
            isOneToOne: false
            referencedRelation: "vault_folders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vault_folder_items_vault_item_id_fkey"
            columns: ["vault_item_id"]
            isOneToOne: false
            referencedRelation: "vault_items"
            referencedColumns: ["id"]
          },
        ]
      }
      vault_folders: {
        Row: {
          created_at: string
          id: string
          name: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      vault_items: {
        Row: {
          content_id: string
          content_type: string
          created_at: string
          id: string
          user_id: string
        }
        Insert: {
          content_id: string
          content_type: string
          created_at?: string
          id?: string
          user_id: string
        }
        Update: {
          content_id?: string
          content_type?: string
          created_at?: string
          id?: string
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      trades_public_read: {
        Row: {
          account_type: string | null
          contracts: number | null
          copied_account_ids: string[] | null
          copy_trading_group_id: string | null
          created_at: string | null
          date: string | null
          direction: string | null
          duration_seconds: number | null
          duration_text: string | null
          entry_price: number | null
          entry_time: string | null
          exit_price: number | null
          exit_time: string | null
          first_published_at: string | null
          id: string | null
          image_crop: Json | null
          image_display_mode: string | null
          image_url: string | null
          is_pinned: boolean | null
          is_public: boolean | null
          market_condition: string | null
          mode: string | null
          pnl: number | null
          points: number | null
          public_description: string | null
          rr: number | null
          session: string | null
          ticker: string | null
          timeframe: string | null
          trade_date: string | null
          trade_mode: string | null
          trade_type: string | null
          user_id: string | null
        }
        Insert: {
          account_type?: string | null
          contracts?: number | null
          copied_account_ids?: string[] | null
          copy_trading_group_id?: string | null
          created_at?: string | null
          date?: string | null
          direction?: string | null
          duration_seconds?: number | null
          duration_text?: string | null
          entry_price?: number | null
          entry_time?: string | null
          exit_price?: number | null
          exit_time?: string | null
          first_published_at?: string | null
          id?: string | null
          image_crop?: Json | null
          image_display_mode?: string | null
          image_url?: string | null
          is_pinned?: boolean | null
          is_public?: boolean | null
          market_condition?: string | null
          mode?: string | null
          pnl?: number | null
          points?: number | null
          public_description?: string | null
          rr?: number | null
          session?: string | null
          ticker?: string | null
          timeframe?: string | null
          trade_date?: string | null
          trade_mode?: string | null
          trade_type?: string | null
          user_id?: string | null
        }
        Update: {
          account_type?: string | null
          contracts?: number | null
          copied_account_ids?: string[] | null
          copy_trading_group_id?: string | null
          created_at?: string | null
          date?: string | null
          direction?: string | null
          duration_seconds?: number | null
          duration_text?: string | null
          entry_price?: number | null
          entry_time?: string | null
          exit_price?: number | null
          exit_time?: string | null
          first_published_at?: string | null
          id?: string | null
          image_crop?: Json | null
          image_display_mode?: string | null
          image_url?: string | null
          is_pinned?: boolean | null
          is_public?: boolean | null
          market_condition?: string | null
          mode?: string | null
          pnl?: number | null
          points?: number | null
          public_description?: string | null
          rr?: number | null
          session?: string | null
          ticker?: string | null
          timeframe?: string | null
          trade_date?: string | null
          trade_mode?: string | null
          trade_type?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "trades_copy_trading_group_id_fkey"
            columns: ["copy_trading_group_id"]
            isOneToOne: false
            referencedRelation: "copy_trading_groups"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      _trade_rooms_parse_discovery_cursor: {
        Args: { p_cursor: string }
        Returns: Json
      }
      _trade_rooms_popular_after: {
        Args: {
          p_cursor: Json
          p_id: string
          p_mc: number
          p_name: string
          p_ra: number
        }
        Returns: boolean
      }
      _trade_rooms_suggested_after: {
        Args: {
          p_cursor: Json
          p_fc: number
          p_id: string
          p_mc: number
          p_name: string
          p_ra: number
          p_sb: number
        }
        Returns: boolean
      }
      _v1_feed_before_cursor: {
        Args: {
          p_cursor_id: string
          p_cursor_kind: string
          p_cursor_kind_rank: number
          p_cursor_ts: string
          p_legacy_only: boolean
          p_row_id: string
          p_row_kind: string
          p_row_ts: string
        }
        Returns: boolean
      }
      _v1_feed_kind_rank: { Args: { p_kind: string }; Returns: number }
      _v1_feed_parse_cursor: {
        Args: { p_cursor: string }
        Returns: {
          cursor_id: string
          cursor_kind: string
          cursor_kind_rank: number
          cursor_ts: string
          legacy_only: boolean
        }[]
      }
      _v1_feed_post_trade_payload: {
        Args: {
          p_guest: boolean
          p_reel: Database["public"]["Tables"]["reels"]["Row"]
          p_trade: Database["public"]["Tables"]["trades"]["Row"]
        }
        Returns: Json
      }
      _v1_guest_feed_achievement_projection: {
        Args: { p_row: Database["public"]["Tables"]["achievements"]["Row"] }
        Returns: Json
      }
      _v1_session_early_access_active: {
        Args: { p: Database["public"]["Tables"]["profiles"]["Row"] }
        Returns: boolean
      }
      _v1_session_is_pro: {
        Args: { p: Database["public"]["Tables"]["profiles"]["Row"] }
        Returns: boolean
      }
      _v1_trade_room_guest_readable: {
        Args: { p_room: Database["public"]["Tables"]["rooms"]["Row"] }
        Returns: boolean
      }
      _v2_messaging_before_cursor: {
        Args: {
          p_cursor_id: string
          p_cursor_ts: string
          p_legacy_only: boolean
          p_row_id: string
          p_row_ts: string
        }
        Returns: boolean
      }
      _v2_messaging_inbox_preview_text: {
        Args: {
          p_content: string
          p_deleted_for_everyone: boolean
          p_image_url: string
          p_is_system: boolean
          p_trade_id: string
          p_type: string
        }
        Returns: string
      }
      _v2_messaging_parse_cursor: {
        Args: { p_cursor: string }
        Returns: {
          cursor_id: string
          cursor_ts: string
          legacy_only: boolean
        }[]
      }
      admin_affiliate_application_approve: {
        Args: {
          p_admin_notes?: string
          p_application_id: string
          p_final_code: string
          p_stripe_promo_code_id?: string
        }
        Returns: Json
      }
      admin_affiliate_application_counts: { Args: never; Returns: Json }
      admin_affiliate_application_reject: {
        Args: { p_admin_notes?: string; p_application_id: string }
        Returns: Json
      }
      admin_affiliate_approve: {
        Args: {
          p_admin_code?: string
          p_application_id: string
          p_stripe_promo?: string
        }
        Returns: undefined
      }
      admin_affiliate_reject: {
        Args: { p_admin_notes?: string; p_application_id: string }
        Returns: undefined
      }
      admin_analytics_bundle: {
        Args: { p_series_days?: number }
        Returns: Json
      }
      admin_beta_activity: {
        Args: { p_limit?: number; p_offset?: number; p_search?: string }
        Returns: Json
      }
      admin_beta_dashboard_bundle: { Args: never; Returns: Json }
      admin_is_current_user_admin: { Args: never; Returns: boolean }
      admin_list_users: {
        Args: {
          p_banned?: boolean
          p_limit?: number
          p_offset?: number
          p_private?: boolean
          p_pro?: boolean
          p_search?: string
        }
        Returns: {
          avatar_url: string
          banned_at: string
          banned_reason: string
          created_at: string
          email: string
          full_count: number
          id: string
          is_banned: boolean
          is_beta_tester: boolean
          is_private: boolean
          is_pro: boolean
          name: string
          referral_code: string
          subscription_status: string
          username: string
        }[]
      }
      admin_recent_audit: { Args: { p_limit?: number }; Returns: Json }
      admin_user_activity_counts: { Args: { p_target: string }; Returns: Json }
      affiliate_payout_balance: { Args: { p_user_id: string }; Returns: Json }
      analytics_apply_trade_contribution: {
        Args: {
          p_account_id: string
          p_calendar_day: string
          p_contrib: Database["public"]["CompositeTypes"]["trade_analytics_contribution"]
          p_mode_effective: string
          p_sign: number
          p_user_id: string
        }
        Returns: undefined
      }
      analytics_apply_trade_public_contribution: {
        Args: {
          p_account_id: string
          p_calendar_day: string
          p_contrib: Database["public"]["CompositeTypes"]["trade_analytics_contribution"]
          p_mode_effective: string
          p_sign: number
          p_user_id: string
        }
        Returns: undefined
      }
      analytics_bump_profile_public_revision: {
        Args: { p_user_id: string }
        Returns: undefined
      }
      analytics_bump_user_revision: {
        Args: { p_user_id: string }
        Returns: undefined
      }
      analytics_calendar_day: {
        Args: {
          p_created_at: string
          p_entry_time: string
          p_exit_time: string
        }
        Returns: string
      }
      analytics_dashboard_as_of_et: { Args: never; Returns: string }
      analytics_dashboard_charts_bundle: {
        Args: {
          p_account_id?: string
          p_as_of: string
          p_preset: string
          p_user_id: string
        }
        Returns: Json
      }
      analytics_dashboard_compose_metrics: {
        Args: {
          p_breakeven_count: number
          p_gross_loss: number
          p_gross_profit: number
          p_hold_count: number
          p_largest_loss: number
          p_largest_win: number
          p_long_count: number
          p_long_pnl: number
          p_loss_count: number
          p_net_pnl: number
          p_rr_count: number
          p_short_count: number
          p_short_pnl: number
          p_sum_hold_seconds: number
          p_sum_rr: number
          p_trade_count: number
          p_win_count: number
        }
        Returns: Json
      }
      analytics_dashboard_distributions_block: {
        Args: {
          p_account_id?: string
          p_end: string
          p_start: string
          p_user_id: string
        }
        Returns: Json
      }
      analytics_dashboard_equity_block: {
        Args: {
          p_account_id?: string
          p_end: string
          p_start: string
          p_user_id: string
        }
        Returns: Json
      }
      analytics_dashboard_insights_block: {
        Args: {
          p_account_id?: string
          p_end: string
          p_start: string
          p_user_id: string
        }
        Returns: Json
      }
      analytics_dashboard_metrics_from_daily: {
        Args: {
          p_account_id?: string
          p_end: string
          p_start: string
          p_user_id: string
        }
        Returns: Json
      }
      analytics_dashboard_metrics_multi_preset_bundles: {
        Args: { p_account_id?: string; p_as_of: string; p_user_id: string }
        Returns: Json
      }
      analytics_dashboard_metrics_preset_bundle: {
        Args: {
          p_account_id?: string
          p_as_of: string
          p_preset: string
          p_user_id: string
        }
        Returns: Json
      }
      analytics_dashboard_preset_bounds: {
        Args: { p_as_of: string; p_preset: string }
        Returns: Record<string, unknown>
      }
      analytics_dashboard_preset_bundle: {
        Args: {
          p_account_id?: string
          p_as_of: string
          p_preset: string
          p_user_id: string
        }
        Returns: Json
      }
      analytics_dashboard_session_label: {
        Args: { p_session: string }
        Returns: string
      }
      analytics_dashboard_streak_snapshot: {
        Args: {
          p_account_id?: string
          p_end: string
          p_start: string
          p_user_id: string
        }
        Returns: Json
      }
      analytics_dashboard_trade_in_scope: {
        Args: {
          p_account_id?: string
          p_trade: Database["public"]["Tables"]["trades"]["Row"]
        }
        Returns: boolean
      }
      analytics_legacy_trading_day_key: {
        Args: {
          p_created_at: string
          p_entry_time: string
          p_exit_time: string
        }
        Returns: string
      }
      analytics_mode_effective: {
        Args: {
          p_account_mode: string
          p_account_type: string
          p_trade_mode: string
        }
        Returns: string
      }
      analytics_numeric_near: {
        Args: { p_a: number; p_abs_tol?: number; p_b: number }
        Returns: boolean
      }
      analytics_parity_user_range: {
        Args: {
          p_account_id?: string
          p_end: string
          p_mode?: string
          p_start: string
          p_user_id: string
        }
        Returns: Json
      }
      analytics_parse_trade_timestamp: {
        Args: { p_raw: string }
        Returns: string
      }
      analytics_raw_normal_range_metrics: {
        Args: {
          p_account_id?: string
          p_end: string
          p_mode?: string
          p_start: string
          p_user_id: string
        }
        Returns: Json
      }
      analytics_realized_sort_ts: {
        Args: {
          p_created_at: string
          p_entry_time: string
          p_exit_time: string
        }
        Returns: string
      }
      analytics_refresh_daily_bucket_extrema: {
        Args: {
          p_account_id: string
          p_calendar_day: string
          p_mode_effective: string
          p_user_id: string
        }
        Returns: undefined
      }
      analytics_refresh_public_daily_bucket_extrema: {
        Args: {
          p_account_id: string
          p_calendar_day: string
          p_mode_effective: string
          p_user_id: string
        }
        Returns: undefined
      }
      analytics_sync_trade_daily_stats_from_row: {
        Args: {
          p_sign: number
          p_trade: Database["public"]["Tables"]["trades"]["Row"]
        }
        Returns: undefined
      }
      analytics_sync_trade_public_daily_stats_from_row: {
        Args: {
          p_sign: number
          p_trade: Database["public"]["Tables"]["trades"]["Row"]
        }
        Returns: undefined
      }
      analytics_trade_account_uuid: {
        Args: { p_account_id: string }
        Returns: string
      }
      analytics_trade_bucket_key: {
        Args: { p_trade: Database["public"]["Tables"]["trades"]["Row"] }
        Returns: {
          account_id: string
          calendar_day: string
          mode_effective: string
          user_id: string
        }[]
      }
      analytics_trade_contribution: {
        Args: { p_trade: Database["public"]["Tables"]["trades"]["Row"] }
        Returns: Database["public"]["CompositeTypes"]["trade_analytics_contribution"]
        SetofOptions: {
          from: "trades"
          to: "trade_analytics_contribution"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      analytics_trade_created_at_utc: {
        Args: { p_created_at: string }
        Returns: string
      }
      analytics_trade_eligible_public_profile: {
        Args: { p_trade: Database["public"]["Tables"]["trades"]["Row"] }
        Returns: boolean
      }
      analytics_trade_hold_seconds: {
        Args: { p_trade: Database["public"]["Tables"]["trades"]["Row"] }
        Returns: number
      }
      analytics_trade_row_affects_public_stats: {
        Args: {
          p_new: Database["public"]["Tables"]["trades"]["Row"]
          p_old: Database["public"]["Tables"]["trades"]["Row"]
        }
        Returns: boolean
      }
      analytics_trade_row_affects_stats: {
        Args: {
          p_new: Database["public"]["Tables"]["trades"]["Row"]
          p_old: Database["public"]["Tables"]["trades"]["Row"]
        }
        Returns: boolean
      }
      analytics_trade_sort_instant: {
        Args: {
          p_created_at: string
          p_entry_time: string
          p_exit_time: string
        }
        Returns: string
      }
      analytics_wire_trade_timestamp_utc: {
        Args: { p_raw: string }
        Returns: string
      }
      apple_subscription_is_active: {
        Args: {
          p_row: Database["public"]["Tables"]["apple_subscriptions"]["Row"]
        }
        Returns: boolean
      }
      backfill_trade_daily_stats_batch: {
        Args: { p_limit?: number }
        Returns: number
      }
      backfill_trade_public_daily_stats_batch: {
        Args: { p_limit?: number }
        Returns: number
      }
      can_manage_trade_room: {
        Args: { p_room_id: string; p_user_id: string }
        Returns: boolean
      }
      can_read_trade_room_messages: {
        Args: { p_room_id: string }
        Returns: boolean
      }
      claim_apple_sign_in_revoke_queue: {
        Args: { p_limit?: number }
        Returns: {
          attempts: number
          client_id: string
          created_at: string
          id: string
          last_error: string | null
          lease_expires_at: string | null
          next_attempt_at: string
          refresh_token_ciphertext: string
        }[]
        SetofOptions: {
          from: "*"
          to: "apple_sign_in_revoke_queue"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      claim_pro_for_life: {
        Args: { p_environment: string; p_user_id: string }
        Returns: {
          awarded_at: string
          follow_count: number
          public_trade_day_count: number
          referral_count: number
          result: string
          spots_remaining: number
        }[]
      }
      consume_app_rate_limit: { Args: { p_action: string }; Returns: undefined }
      conversations_preview_from_message_row: {
        Args: { p_message: Database["public"]["Tables"]["messages"]["Row"] }
        Returns: {
          activity_at: string
          preview: string
        }[]
      }
      default_public_account_label: {
        Args: { p_category: string; p_mode: string }
        Returns: string
      }
      delete_own_trade: { Args: { p_trade_id: string }; Returns: undefined }
      early_access_environment_valid: {
        Args: { p_environment: string }
        Returns: boolean
      }
      enable_all_account_trade_entry: {
        Args: { p_user_id: string }
        Returns: undefined
      }
      enroll_early_access: {
        Args: {
          p_enrollment_source: string
          p_environment: string
          p_user_id: string
        }
        Returns: string
      }
      ensure_room_member_tags_defaults: {
        Args: { p_room_id: string }
        Returns: undefined
      }
      expire_early_access: { Args: { p_user_id: string }; Returns: boolean }
      expire_early_access_batch: { Args: never; Returns: number }
      explore_profile_public_win_rates: {
        Args: { p_profile_ids: string[] }
        Returns: {
          user_id: string
          win_rate: number
        }[]
      }
      explore_social_counts: {
        Args: { p_profile_ids: string[] }
        Returns: {
          followers_count: number
          following_count: number
          profile_id: string
        }[]
      }
      explore_trade_meta_aggregates: {
        Args: { p_limit?: number }
        Returns: {
          freq: number
          last_trade_at: string
          row_kind: string
          session: string
          ticker: string
          total_pnl: number
          trade_count: number
          user_id: string
          win_count: number
        }[]
      }
      feed_engagement_counts: {
        Args: {
          p_achievement_post_ids?: string[]
          p_post_ids?: string[]
          p_profile_post_ids?: string[]
          p_reel_ids?: string[]
        }
        Returns: {
          comment_count: number
          content_id: string
          content_type: string
          like_count: number
          liked_by_me: boolean
        }[]
      }
      free_plan_count_clips_today: {
        Args: { p_user_id: string }
        Returns: number
      }
      free_plan_count_direct_messages_rolling_24h: {
        Args: { p_user_id: string }
        Returns: number
      }
      free_plan_count_posts_today: {
        Args: { p_user_id: string }
        Returns: number
      }
      free_plan_count_trades_today: {
        Args: { p_user_id: string }
        Returns: number
      }
      free_plan_limits_enforced: { Args: never; Returns: boolean }
      free_plan_utc_day_start: { Args: never; Returns: string }
      get_active_block_peer_ids: { Args: never; Returns: string[] }
      get_app_icon_badge: { Args: { p_user_id?: string }; Returns: number }
      get_conversation_shared_media: {
        Args: {
          p_before_created_at?: string
          p_before_id?: string
          p_conversation_id: string
          p_limit?: number
        }
        Returns: {
          created_at: string
          image_url: string
          message_id: string
          sender_id: string
        }[]
      }
      get_conversation_unread_counts: {
        Args: { p_conversation_ids?: string[] }
        Returns: {
          conversation_id: string
          unread_count: number
        }[]
      }
      get_dm_block_status: {
        Args: { p_conversation_id: string }
        Returns: {
          blocked_by_me: boolean
          blocked_by_other: boolean
          other_user_id: string
        }[]
      }
      get_early_access_progress: {
        Args: { p_environment: string; p_user_id: string }
        Returns: {
          all_complete: boolean
          already_awarded: boolean
          award_limit: number
          awards_claimed: number
          completed_count: number
          ends_at: string
          enrolled_at: string
          follow_count: number
          public_trade_day_count: number
          referral_count: number
          referral_user_id: string
          spots_remaining: number
          status: string
        }[]
      }
      get_hidden_blocked_dm_conversation_ids: {
        Args: never
        Returns: {
          conversation_id: string
        }[]
      }
      get_navbar_badges: {
        Args: never
        Returns: {
          dm_unread: number
          notification_unread: number
        }[]
      }
      get_room_unread_counts: {
        Args: { p_room_ids?: string[] }
        Returns: {
          room_id: string
          unread_count: number
        }[]
      }
      get_user_block_status: {
        Args: { p_other_user_id: string }
        Returns: {
          blocked_by_me: boolean
          blocked_by_other: boolean
          other_user_id: string
        }[]
      }
      is_active_room_member: {
        Args: { p_room_id: string; p_user_id: string }
        Returns: boolean
      }
      is_conversation_participant: {
        Args: { p_conversation_id: string; p_user_id: string }
        Returns: boolean
      }
      is_room_banned: {
        Args: { p_room_id: string; p_user_id: string }
        Returns: boolean
      }
      is_room_owner: {
        Args: { p_room_id: string; p_user_id: string }
        Returns: boolean
      }
      launch_access_grant_applies: {
        Args: { p_user_id: string }
        Returns: boolean
      }
      leaderboard_ranked_window: {
        Args: {
          p_account_type?: string
          p_custom_end?: string
          p_custom_end_ymd?: string
          p_custom_start?: string
          p_custom_start_ymd?: string
          p_now?: string
          p_rank_limit?: number
          p_view: string
          p_viewer_id?: string
        }
        Returns: Json
      }
      leaderboard_ranked_window_one: {
        Args: {
          p_account_type: string
          p_custom_end: string
          p_custom_end_ymd: string
          p_custom_start: string
          p_custom_start_ymd: string
          p_now: string
          p_rank_limit: number
          p_view: string
          p_viewer_id: string
        }
        Returns: Json
      }
      leaderboard_trade_rows: {
        Args: { p_limit?: number; p_offset?: number }
        Returns: {
          account_type: string
          created_at: string
          mode: string
          pnl: number
          rr: number
          user_id: string
        }[]
      }
      leaderboard_trade_rows_page: {
        Args: {
          p_after_created_at?: string
          p_after_user_id?: string
          p_limit?: number
        }
        Returns: {
          account_type: string
          created_at: string
          mode: string
          pnl: number
          rr: number
          user_id: string
        }[]
      }
      list_muted_dm_peers: {
        Args: never
        Returns: {
          avatar_url: string
          conversation_id: string
          name: string
          peer_id: string
          username: string
        }[]
      }
      list_public_user_reviews: {
        Args: never
        Returns: {
          avatar_snapshot: string
          created_at: string
          display_name: string
          featured: boolean
          id: string
          rating: number
          review: string
          title: string
          username_snapshot: string
          would_recommend: boolean
        }[]
      }
      mark_conversation_read: {
        Args: { p_conversation_id: string }
        Returns: undefined
      }
      mark_conversation_unread: {
        Args: { p_conversation_id: string }
        Returns: string
      }
      mark_getting_started_intro_seen: { Args: never; Returns: boolean }
      mark_onboarding_complete_popup_seen: { Args: never; Returns: boolean }
      mark_room_read: { Args: { p_room_id: string }; Returns: undefined }
      messages_assert_trade_share_allowed: {
        Args: { p_sender_id: string; p_trade_id: string; p_type: string }
        Returns: undefined
      }
      normalize_trade_ticker: { Args: { p_raw: string }; Returns: string }
      owner_comparison_scope_trades: {
        Args: { p_viewer: string }
        Returns: {
          activity_at: string
          hold_seconds: number
          id: string
          pnl: number
          root_ticker: string
          rr: number
        }[]
      }
      popular_trade_rooms: {
        Args: { p_limit?: number }
        Returns: {
          description: string
          id: string
          member_count: number
          name: string
          slug: string
        }[]
      }
      profile_analytics_v2_perf_probe: {
        Args: { p_profile_id: string }
        Returns: Json
      }
      profile_analytics_v2_shadow_compare: {
        Args: { p_profile_id: string; p_viewer_id?: string }
        Returns: Json
      }
      profile_has_active_apple_subscription: {
        Args: { p_user_id: string }
        Returns: boolean
      }
      profile_is_pro_user: { Args: { p_user_id: string }; Returns: boolean }
      profile_pinned_content_bootstrap: {
        Args: {
          p_can_view: boolean
          p_is_own: boolean
          p_profile_id: string
          p_viewer_id: string
        }
        Returns: Json
      }
      profile_pinned_item_visible: {
        Args: {
          p_can_view: boolean
          p_content_id: string
          p_content_type: string
          p_is_own: boolean
          p_profile_id: string
          p_viewer_id: string
        }
        Returns: boolean
      }
      profile_public_daily_stats_mode_rollup: {
        Args: { p_filter_mode: string; p_profile_id: string }
        Returns: Json
      }
      profile_public_daily_stats_raw_parity: {
        Args: { p_filter_mode: string; p_profile_id: string }
        Returns: Json
      }
      profile_statistics_public_trades: {
        Args: { p_profile_id: string }
        Returns: {
          acct_mode: string
          created_at: string
          is_long: boolean
          pnl: number
          session_raw: string
          trade_id: string
        }[]
      }
      profile_statistics_resolve_account_mode: {
        Args: {
          p_account_mode: string
          p_account_type: string
          p_trade_mode: string
        }
        Returns: string
      }
      profile_statistics_trade_matches_mode: {
        Args: { p_acct_mode: string; p_filter_mode: string }
        Returns: boolean
      }
      profile_viewer_can_view_trades: {
        Args: { p_profile_id: string }
        Returns: boolean
      }
      rate_limit_cleanup_counters: {
        Args: { p_retain?: string }
        Returns: number
      }
      rate_limit_hit: { Args: { p_action: string }; Returns: undefined }
      rate_limit_is_service_role: { Args: never; Returns: boolean }
      rebuild_trade_daily_stats_all_users: { Args: never; Returns: number }
      rebuild_trade_daily_stats_for_account: {
        Args: { p_account_id: string; p_user_id: string }
        Returns: undefined
      }
      rebuild_trade_daily_stats_for_user: {
        Args: { p_user_id: string }
        Returns: undefined
      }
      rebuild_trade_public_daily_stats_all_users: {
        Args: never
        Returns: number
      }
      rebuild_trade_public_daily_stats_for_account: {
        Args: {
          p_account_id: string
          p_bump_revision?: boolean
          p_user_id: string
        }
        Returns: undefined
      }
      rebuild_trade_public_daily_stats_for_user: {
        Args: { p_bump_revision?: boolean; p_user_id: string }
        Returns: undefined
      }
      recipient_allows_dm: {
        Args: { p_recipient: string; p_sender: string }
        Returns: boolean
      }
      record_account_payout: {
        Args: {
          p_account_id: string
          p_balance_after_payout: number
          p_balance_before_payout: number
          p_drawdown_behavior: string
          p_drawdown_floor_after_payout: number
          p_payout_amount: number
          p_remember_drawdown_behavior?: boolean
        }
        Returns: string
      }
      redeem_creator_access_code: {
        Args: { p_code: string; p_user_id: string }
        Returns: string
      }
      room_message_insert_allowed: {
        Args: {
          p_audio_url: string
          p_image_url: string
          p_message_type: string
          p_room_id: string
          p_section_id: string
          p_trade_id: string
          p_user_id: string
        }
        Returns: boolean
      }
      room_message_insert_section_allowed: {
        Args: { p_room_id: string; p_section_id: string; p_user_id: string }
        Returns: boolean
      }
      rpc_v1_activity_bootstrap: {
        Args: { p_cursor?: string; p_limit?: number }
        Returns: Json
      }
      rpc_v1_analytics_calendar_day_trades: {
        Args: { p_account_id?: string; p_calendar_day: string; p_mode?: string }
        Returns: Json
      }
      rpc_v1_analytics_daily_range_bootstrap: {
        Args: {
          p_account_id?: string
          p_end: string
          p_mode?: string
          p_start: string
        }
        Returns: Json
      }
      rpc_v1_analytics_dashboard_account_charts_v3: {
        Args: { p_account_id: string }
        Returns: Json
      }
      rpc_v1_analytics_dashboard_aggregate_charts_v3: {
        Args: never
        Returns: Json
      }
      rpc_v1_analytics_dashboard_bootstrap_v3: { Args: never; Returns: Json }
      rpc_v1_analytics_revision: { Args: never; Returns: Json }
      rpc_v1_analytics_shadow_compare_range: {
        Args: {
          p_account_id?: string
          p_end: string
          p_mode?: string
          p_start: string
        }
        Returns: Json
      }
      rpc_v1_broker_integration_status: {
        Args: { p_provider?: string }
        Returns: Json
      }
      rpc_v1_calendar_bootstrap: {
        Args: {
          p_account_id?: string
          p_entry_from?: string
          p_entry_to?: string
          p_month: number
          p_year: number
        }
        Returns: Json
      }
      rpc_v1_check_in_history_bootstrap: {
        Args: {
          p_account_id?: string
          p_end_date: string
          p_start_date: string
        }
        Returns: Json
      }
      rpc_v1_conversation_thread_bootstrap: {
        Args: {
          p_conversation_id: string
          p_cursor?: string
          p_mark_read?: boolean
          p_message_limit?: number
        }
        Returns: Json
      }
      rpc_v1_conversation_thread_message_row: {
        Args: { p_message_id: string }
        Returns: Json
      }
      rpc_v1_create_trade_room: {
        Args: {
          p_category?: string
          p_channels?: Json
          p_description?: string
          p_discovery_tags?: string[]
          p_image_url?: string
          p_is_private?: boolean
          p_join_policy?: string
          p_members_can_message?: boolean
          p_members_can_share_media?: boolean
          p_members_can_share_trades?: boolean
          p_name: string
          p_rules?: string
          p_show_on_profile?: boolean
        }
        Returns: Json
      }
      rpc_v1_dashboard_bootstrap: {
        Args: { p_account_id?: string; p_trade_limit?: number }
        Returns: Json
      }
      rpc_v1_explore_bootstrap: {
        Args: {
          p_room_limit?: number
          p_trader_limit?: number
          p_trader_offset?: number
        }
        Returns: Json
      }
      rpc_v1_feed_bootstrap: {
        Args: {
          p_content_filter?: string
          p_cursor?: string
          p_limit?: number
          p_scope?: string
        }
        Returns: Json
      }
      rpc_v1_getting_started_signals: { Args: never; Returns: Json }
      rpc_v1_leaderboard_bootstrap: {
        Args: {
          p_audience?: string
          p_category?: string
          p_cursor?: string
          p_limit?: number
          p_timeframe?: string
        }
        Returns: Json
      }
      rpc_v1_list_trade_room_join_requests: {
        Args: { p_room_id: string; p_status?: string }
        Returns: Json
      }
      rpc_v1_messaging_bootstrap: {
        Args: { p_cursor?: string; p_limit?: number }
        Returns: Json
      }
      rpc_v1_profile_account_insights: {
        Args: { p_identifier: string }
        Returns: Json
      }
      rpc_v1_profile_analytics_bootstrap_v2: {
        Args: { p_profile_id: string }
        Returns: Json
      }
      rpc_v1_profile_bootstrap: {
        Args: {
          p_cursor?: string
          p_identifier: string
          p_initial_tab?: string
          p_limit?: number
        }
        Returns: Json
      }
      rpc_v1_profile_pin_content: {
        Args: {
          p_content_id: string
          p_content_type: string
          p_replace_position?: number
        }
        Returns: Json
      }
      rpc_v1_profile_public_analytics_revision: {
        Args: { p_profile_id: string }
        Returns: Json
      }
      rpc_v1_profile_reorder_pinned: {
        Args: { p_from_position: number; p_to_position: number }
        Returns: Json
      }
      rpc_v1_profile_statistics_bootstrap: {
        Args: { p_profile_id: string }
        Returns: Json
      }
      rpc_v1_profile_tab_achievements: {
        Args: { p_cursor?: string; p_limit?: number; p_profile_id: string }
        Returns: Json
      }
      rpc_v1_profile_tab_posts: {
        Args: { p_cursor?: string; p_limit?: number; p_profile_id: string }
        Returns: Json
      }
      rpc_v1_profile_tab_reels: {
        Args: { p_cursor?: string; p_limit?: number; p_profile_id: string }
        Returns: Json
      }
      rpc_v1_profile_tab_trades: {
        Args: { p_cursor?: string; p_limit?: number; p_profile_id: string }
        Returns: Json
      }
      rpc_v1_profile_tab_trades_summary_shadow_compare: {
        Args: { p_cursor?: string; p_limit?: number; p_profile_id: string }
        Returns: Json
      }
      rpc_v1_profile_tab_trades_v2: {
        Args: { p_cursor?: string; p_limit?: number; p_profile_id: string }
        Returns: Json
      }
      rpc_v1_profile_unpin_content: {
        Args: { p_content_id: string; p_content_type: string }
        Returns: Json
      }
      rpc_v1_prop_firm_bootstrap: { Args: never; Returns: Json }
      rpc_v1_psychology_check_in_window: {
        Args: { p_account_id?: string }
        Returns: Json
      }
      rpc_v1_public_room_guest_bootstrap: {
        Args: {
          p_cursor?: string
          p_limit?: number
          p_room_id: string
          p_section_id?: string
        }
        Returns: Json
      }
      rpc_v1_public_room_guest_message_row: {
        Args: { p_message_id: string; p_room_id: string }
        Returns: Json
      }
      rpc_v1_request_trade_room_join: {
        Args: { p_room_id: string }
        Returns: Json
      }
      rpc_v1_resolve_trade_room_join_request: {
        Args: { p_action: string; p_request_id: string }
        Returns: Json
      }
      rpc_v1_room_bootstrap: {
        Args: {
          p_mark_read?: boolean
          p_message_limit?: number
          p_room_id: string
          p_section_id?: string
        }
        Returns: Json
      }
      rpc_v1_room_bootstrap_message_row: {
        Args: { p_message_id: string }
        Returns: Json
      }
      rpc_v1_search_trade_rooms: {
        Args: { p_limit?: number; p_query: string }
        Returns: Json
      }
      rpc_v1_session_bootstrap: { Args: never; Returns: Json }
      rpc_v1_trade_detail_owner_comparison: {
        Args: { p_trade_id: string }
        Returns: Json
      }
      rpc_v1_trade_owner_read: { Args: { p_trade_id: string }; Returns: Json }
      rpc_v1_trade_room_discovery: {
        Args: { p_limit?: number; p_mode?: string; p_scope?: string }
        Returns: Json
      }
      rpc_v1_trade_room_join_request_detail: {
        Args: { p_request_id: string }
        Returns: Json
      }
      rpc_v1_trade_rooms_home_bootstrap: {
        Args: {
          p_limit?: number
          p_popular_cursor?: string
          p_scope?: string
          p_suggested_cursor?: string
        }
        Returns: Json
      }
      rpc_v1_trades_list_bootstrap:
        | {
            Args: {
              p_account_id?: string
              p_created_from?: string
              p_created_to?: string
              p_cursor?: string
              p_direction?: string
              p_limit?: number
              p_pnl_max?: number
              p_pnl_min?: number
              p_result?: string
              p_search?: string
              p_sort?: string
              p_visibility?: string
            }
            Returns: Json
          }
        | {
            Args: {
              p_account_id?: string
              p_account_mode?: string
              p_created_from?: string
              p_created_to?: string
              p_cursor?: string
              p_direction?: string
              p_limit?: number
              p_pnl_max?: number
              p_pnl_min?: number
              p_result?: string
              p_rr_max?: number
              p_rr_min?: number
              p_search?: string
              p_session?: string
              p_sort?: string
              p_visibility?: string
            }
            Returns: Json
          }
      rpc_v1_trades_list_bootstrap_v2: {
        Args: {
          p_account_id?: string
          p_account_mode?: string
          p_created_from?: string
          p_created_to?: string
          p_cursor?: string
          p_direction?: string
          p_limit?: number
          p_pnl_max?: number
          p_pnl_min?: number
          p_result?: string
          p_rr_max?: number
          p_rr_min?: number
          p_search?: string
          p_session?: string
          p_sort?: string
          p_visibility?: string
        }
        Returns: Json
      }
      rpc_v1_trades_owner_rows: {
        Args: { p_limit?: number; p_trade_ids?: string[] }
        Returns: Json
      }
      rpc_v1_vault_state_batch: { Args: { p_items: Json }; Returns: Json }
      rpc_v1_viewer_sync_state: { Args: never; Returns: Json }
      rpc_v1_viewer_trade_room_join_request: {
        Args: { p_room_id: string }
        Returns: Json
      }
      rpc_v2_messaging_bootstrap: {
        Args: {
          p_cursor: string
          p_limit: number
          p_mark_message_notifications_read: boolean
        }
        Returns: Json
      }
      safe_public_account_display_name: {
        Args: {
          p_account_number: string
          p_category: string
          p_mode: string
          p_name: string
        }
        Returns: string
      }
      search_public_trade_rooms: {
        Args: { p_limit?: number; p_query: string }
        Returns: {
          description: string
          id: string
          image_url: string
          member_count: number
          name: string
          slug: string
        }[]
      }
      select_free_plan_trade_accounts: {
        Args: { p_account_ids: string[] }
        Returns: undefined
      }
      set_dm_user_block: {
        Args: { p_blocked: boolean; p_conversation_id: string }
        Returns: {
          blocked_by_me: boolean
          blocked_by_other: boolean
          other_user_id: string
        }[]
      }
      set_user_block: {
        Args: { p_blocked: boolean; p_blocked_id: string }
        Returns: {
          blocked_by_me: boolean
          blocked_by_other: boolean
          other_user_id: string
        }[]
      }
      should_deliver_notification: {
        Args: {
          p_achievement_post_id?: string
          p_recipient_id: string
          p_type: string
        }
        Returns: boolean
      }
      sync_trade_room_join_request_notifications: {
        Args: { p_request_id: string; p_status: string }
        Returns: undefined
      }
      trade_room_join_request_recipient_ids: {
        Args: { p_room_id: string }
        Returns: string[]
      }
      trade_room_suggested_official_slug: {
        Args: { p_user_id: string }
        Returns: string
      }
      trade_summary_json: {
        Args: {
          p_trade: Database["public"]["Tables"]["trades"]["Row"]
          p_viewer_id?: string
        }
        Returns: Json
      }
      trade_summary_note_preview: {
        Args: {
          p_trade: Database["public"]["Tables"]["trades"]["Row"]
          p_viewer_id: string
        }
        Returns: string
      }
      trade_summary_owner_extension_json: {
        Args: { p_trade: Database["public"]["Tables"]["trades"]["Row"] }
        Returns: Json
      }
      trade_summary_owner_journal_json: {
        Args: {
          p_trade: Database["public"]["Tables"]["trades"]["Row"]
          p_viewer_id: string
        }
        Returns: Json
      }
      try_story_reply_image_url: {
        Args: { p_content: string }
        Returns: string
      }
      user_streak_milestone_bundle: {
        Args: { p_user_id?: string }
        Returns: {
          comment_count: number
          likes_received_count: number
          onboarding_completed: boolean
          posting_timestamps: string[]
          profile_post_count: number
          public_trade_count: number
          reel_count: number
          trade_count: number
        }[]
      }
      users_have_active_block: {
        Args: { p_user_a: string; p_user_b: string }
        Returns: boolean
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      trade_analytics_contribution: {
        trade_count: number | null
        win_count: number | null
        loss_count: number | null
        breakeven_count: number | null
        net_pnl: number | null
        gross_profit: number | null
        gross_loss: number | null
        long_count: number | null
        long_pnl: number | null
        short_count: number | null
        short_pnl: number | null
        sum_rr: number | null
        rr_count: number | null
        sum_hold_seconds: number | null
        hold_count: number | null
        largest_win: number | null
        largest_loss: number | null
      }
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
