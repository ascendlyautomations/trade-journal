/**
 * AUTO-GENERATED — do not hand-edit.
 *
 * Command: npx supabase gen types typescript --project-id "$SUPABASE_PROJECT_ID" --schema public
 * Alternate (MCP): generate_typescript_types(project_id)
 * Schema: public
 * Source: remote TradeTraxs project fobudrkniacatvilbofw (us-east-2)
 * Generated: 2026-08-24
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
    PostgrestVersion: "14.4"
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
          daily_drawdown: number | null
          id: string
          is_active: boolean | null
          max_drawdown: number | null
          mode: string | null
          name: string
          note: string | null
          payout_drawdown_behavior: string | null
          profit_target: number | null
          remember_payout_drawdown_behavior: boolean
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
          daily_drawdown?: number | null
          id?: string
          is_active?: boolean | null
          max_drawdown?: number | null
          mode?: string | null
          name: string
          note?: string | null
          payout_drawdown_behavior?: string | null
          profit_target?: number | null
          remember_payout_drawdown_behavior?: boolean
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
          daily_drawdown?: number | null
          id?: string
          is_active?: boolean | null
          max_drawdown?: number | null
          mode?: string | null
          name?: string
          note?: string | null
          payout_drawdown_behavior?: string | null
          profit_target?: number | null
          remember_payout_drawdown_behavior?: boolean
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
        ]
      }
      posts: {
        Row: {
          caption: string | null
          created_at: string | null
          id: string
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
          content: string | null
          created_at: string | null
          id: string
          image_url: string | null
          audio_duration_ms: number | null
          audio_url: string | null
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
          content?: string | null
          created_at?: string | null
          id?: string
          image_url?: string | null
          audio_duration_ms?: number | null
          audio_url?: string | null
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
          content?: string | null
          created_at?: string | null
          id?: string
          image_url?: string | null
          audio_duration_ms?: number | null
          audio_url?: string | null
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
          created_at: string | null
          description: string | null
          id: string
          image_url: string | null
          is_private: boolean | null
          name: string
          owner_user_id: string | null
          show_on_profile: boolean | null
          slug: string | null
        }
        Insert: {
          allow_members_chat?: boolean | null
          created_at?: string | null
          description?: string | null
          id?: string
          image_url?: string | null
          is_private?: boolean | null
          name: string
          owner_user_id?: string | null
          show_on_profile?: boolean | null
          slug?: string | null
        }
        Update: {
          allow_members_chat?: boolean | null
          created_at?: string | null
          description?: string | null
          id?: string
          image_url?: string | null
          is_private?: boolean | null
          name?: string
          owner_user_id?: string | null
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
            foreignKeyName: "trade_comments_user_id_fkey"
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
            foreignKeyName: "trade_likes_user_id_fkey"
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
          exit_price: number | null
          exit_time: string | null
          first_published_at: string | null
          followed_plan: boolean | null
          id: string
          image_display_mode: string
          image_url: string | null
          is_initial_import: boolean | null
          is_pinned: boolean | null
          is_public: boolean | null
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
          import_source: string | null
          import_fingerprint: string | null
        }
        Insert: {
          account_category?: string | null
          account_id?: string | null
          account_name?: string | null
          account_size?: string | null
          account_type?: string | null
          ai_feedback?: string | null
          ai_feedback_created_at?: string | null
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
          exit_price?: number | null
          exit_time?: string | null
          first_published_at?: string | null
          followed_plan?: boolean | null
          id?: string
          image_display_mode?: string
          image_url?: string | null
          is_initial_import?: boolean | null
          is_pinned?: boolean | null
          is_public?: boolean | null
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
          import_source?: string | null
          import_fingerprint?: string | null
        }
        Update: {
          account_category?: string | null
          account_id?: string | null
          account_name?: string | null
          account_size?: string | null
          account_type?: string | null
          ai_feedback?: string | null
          ai_feedback_created_at?: string | null
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
          exit_price?: number | null
          exit_time?: string | null
          first_published_at?: string | null
          followed_plan?: boolean | null
          id?: string
          image_display_mode?: string
          image_url?: string | null
          is_initial_import?: boolean | null
          is_pinned?: boolean | null
          is_public?: boolean | null
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
          import_source?: string | null
          import_fingerprint?: string | null
        }
        Relationships: [
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
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
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
      _v1_session_early_access_active: {
        Args: { p: Database["public"]["Tables"]["profiles"]["Row"] }
        Returns: boolean
      }
      _v1_session_is_pro: {
        Args: { p: Database["public"]["Tables"]["profiles"]["Row"] }
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
      expire_early_access: { Args: { p_user_id: string }; Returns: boolean }
      expire_early_access_batch: { Args: never; Returns: number }
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
      free_plan_utc_day_start: { Args: never; Returns: string }
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
      profile_is_pro_user: { Args: { p_user_id: string }; Returns: boolean }
      rate_limit_cleanup_counters: {
        Args: { p_retain?: string }
        Returns: number
      }
      rate_limit_hit: { Args: { p_action: string }; Returns: undefined }
      rate_limit_is_service_role: { Args: never; Returns: boolean }
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
      room_message_insert_section_allowed: {
        Args: { p_room_id: string; p_section_id: string; p_user_id: string }
        Returns: boolean
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
      rpc_v1_dashboard_bootstrap: {
        Args: { p_account_id?: string; p_trade_limit?: number }
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
      rpc_v1_messaging_bootstrap: {
        Args: { p_cursor?: string; p_limit?: number }
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
      rpc_v1_prop_firm_bootstrap: { Args: never; Returns: Json }
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
      rpc_v1_session_bootstrap: { Args: never; Returns: Json }
      rpc_v2_messaging_bootstrap: {
        Args: {
          p_cursor: string
          p_limit: number
          p_mark_message_notifications_read: boolean
        }
        Returns: Json
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
      should_deliver_notification: {
        Args: {
          p_achievement_post_id?: string
          p_recipient_id: string
          p_type: string
        }
        Returns: boolean
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
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
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
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
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
