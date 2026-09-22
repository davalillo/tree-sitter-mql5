//+------------------------------------------------------------------+
//|                                              PropFirmProfile.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Configuration record for the whole guard, in which |
//|               every rule threshold is paired with its OWN        |
//|               explicit enable flag, so a rule is never considered |
//|               active merely because a number happens to compare  |
//|               true. Also carries the prop-day reset hour and     |
//|               timezone offset, and the terminal-facing inputs    |
//|               the consuming EA exposes to its user.              |
//| Failure mode: A default threshold of 0.0 paired with a check of  |
//|               "value >= threshold" means switching a protection  |
//|               on without typing a number fires it on the first   |
//|               tick and every tick after that. Here enablement is |
//|               a bool that has nothing to do with the threshold's |
//|               value, and Validate() rejects an enabled rule      |
//|               whose threshold is still unset before a single     |
//|               tick is processed. P2 -- the daily boundary was    |
//|               hardcoded to server midnight; reset hour, reset    |
//|               minute and a timezone offset are profile fields    |
//|               here and are the only source CPropSessionClock     |
//|               reads.                                             |
//| Dependencies: none                                               |
//| Part of:      PropFirm Guard class package                    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Known firm families whose researched numbers CPropRulebook::  |
//| LoadPreset() can fill in.                                         |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

enum ENUM_PROP_FIRM_PRESET
{
   PROP_PRESET_CUSTOM             = 0, // Custom (fill every field yourself)
   PROP_PRESET_STATIC_DD          = 1, // Static: 10% max drawdown, 5% daily
   PROP_PRESET_TRAILING_LOCKED    = 2, // Trailing drawdown with lock
   PROP_PRESET_TRAILING_NO_DAILY  = 3, // Trailing drawdown, no daily loss cap
   PROP_PRESET_STATIC_WITH_PAYOUT = 4  // Static drawdown + consistency rules
};

//+------------------------------------------------------------------+
//| Which price series the trailing drawdown floor ratchets on.       |
//|  INTRADAY   : the floor follows the running equity peak, so       |
//|               floating profit counts and floating loss can breach |
//|               (the punitive variant).                             |
//|  END_OF_DAY : the floor only moves at the prop-day rollover using |
//|               the closed balance, and the breach test uses        |
//|               balance rather than equity (the tolerant variant).  |
//+------------------------------------------------------------------+
enum ENUM_PROP_TRAIL_MODE
{
   PROP_TRAIL_INTRADAY   = 0,  // Intraday (equity, tick by tick)
   PROP_TRAIL_END_OF_DAY = 1   // End of day (closed balance at rollover)
};

//--- sentinel meaning "this number was never configured"
#define PROP_UNSET_HOUR (-1)

//+------------------------------------------------------------------+
//| The complete configuration of one guarded account.                |
//+------------------------------------------------------------------+
struct PropFirmProfile
{
   //--- identity -----------------------------------------------------
   string   firm_name;
   double   account_size;             // nominal program size, used by LoadPreset()
   double   initial_balance;          // challenge anchor; 0 means "capture at Init"

   //--- prop-day calendar (P2) ---------------------------------------
   int      daily_reset_hour;         // 0..23, expressed in FIRM-LOCAL time
   int      daily_reset_minute;       // 0..59
   int      timezone_offset_hours;    // firm_local = server_time + this many hours

   //--- static maximum drawdown (C4) ---------------------------------
   bool     use_static_dd;
   double   static_dd_amount;         // account currency, measured from initial_balance

   //--- trailing maximum drawdown ------------------------------------
   bool     use_trailing_dd;
   double   trailing_dd_amount;       // account currency below the running peak
   ENUM_PROP_TRAIL_MODE trailing_mode;
   bool     trailing_lock_enabled;    // freeze the floor once the lock level is reached
   double   trailing_lock_level;      // balance level at which the floor freezes;
                                      // 0 means initial_balance + trailing_dd_amount

   //--- daily loss ----------------------------------------------------
   bool     use_daily_loss;
   double   daily_loss_amount;        // account currency lost since the day boundary

   //--- profit target (C6) --------------------------------------------
   bool     use_profit_target;
   double   profit_target_amount;     // account currency above initial_balance
   bool     flatten_on_profit_target; // ask for a FLATTEN when the target is hit

   //--- payout consistency (P5) ---------------------------------------
   bool     use_consistency;
   double   consistency_max_share;    // 0..1, best day / total profit ceiling

   //--- minimum trading days -------------------------------------------
   bool     use_min_trading_days;
   int      min_trading_days;
   double   min_qualifying_volume;    // lots a day must carry to count

   //--- high-impact news blackout ---------------------------------------
   bool     use_news_window;
   int      news_block_minutes_before;
   int      news_block_minutes_after;
   int      news_exempt_hours;        // a position older than this is exempt from the hold ban
   string   news_currencies;          // CSV filter, "" means every currency
   int      news_lookback_minutes;    // how far back the feed keeps events
   int      news_lookahead_minutes;   // how far ahead the feed reads events
   int      news_refresh_secs;        // minimum seconds between calendar reads

   //--- pre-weekend flat -------------------------------------------------
   bool     use_weekend_flat;
   int      weekend_cutoff_dow;       // 0=Sunday .. 6=Saturday, 5 = Friday
   int      weekend_cutoff_hour;      // PROP_UNSET_HOUR while unconfigured
   int      weekend_cutoff_minute;

   //--- protective actions -----------------------------------------------
   bool     disable_algo_on_breach;   // drive the terminal Algo Trading button (needs DLLs)
   int      algo_switch_max_attempts; // bounded escalation before reporting unrecoverable
   int      algo_switch_verify_secs;  // seconds to wait before re-checking / re-posting
   int      close_rounds;             // full close sweeps per Evaluate() pass
   int      close_retries_per_position;
   int      close_deviation_points;
   bool     notify_on_escalation;     // SendNotification() when a request cannot be applied

   //--- scope ------------------------------------------------------------
   ulong    magic;                    // magic of the trading EA being guarded
   bool     restrict_to_magic;        // false = guard every position on the account
   double   safety_buffer_ratio;      // 0..1, warn once this share of a limit is consumed
   int      max_pass_age_secs;        // CanOpen() refuses when the last pass is older

   //--- persistence ------------------------------------------------------
   string   state_file_name;          // "" means auto ("PropRulebook_<login>.dat")
   bool     state_in_common_folder;
   int      state_save_interval_secs;
   int      max_days_tracked;         // ring size of CDailyProfitLedger

   PropFirmProfile() { Clear(); }

   //+---------------------------------------------------------------+
   //| Everything off, every threshold unset. A profile straight out  |
   //| of Clear() registers ZERO rules -- it cannot fire anything.    |
   //+---------------------------------------------------------------+
   void Clear()
   {
      firm_name                  = "Custom";
      account_size               = 0.0;
      initial_balance            = 0.0;

      daily_reset_hour           = 0;
      daily_reset_minute         = 0;
      timezone_offset_hours      = 0;

      use_static_dd              = false;
      static_dd_amount           = 0.0;

      use_trailing_dd            = false;
      trailing_dd_amount         = 0.0;
      trailing_mode              = PROP_TRAIL_INTRADAY;
      trailing_lock_enabled      = true;
      trailing_lock_level        = 0.0;

      use_daily_loss             = false;
      daily_loss_amount          = 0.0;

      use_profit_target          = false;
      profit_target_amount       = 0.0;
      flatten_on_profit_target   = false;

      use_consistency            = false;
      consistency_max_share      = 0.0;

      use_min_trading_days       = false;
      min_trading_days           = 0;
      min_qualifying_volume      = 0.0;

      use_news_window            = false;
      news_block_minutes_before  = 0;
      news_block_minutes_after   = 0;
      news_exempt_hours          = 0;
      news_currencies            = "";
      news_lookback_minutes      = 240;
      news_lookahead_minutes     = 1440;
      news_refresh_secs          = 300;

      use_weekend_flat           = false;
      weekend_cutoff_dow         = 5;
      weekend_cutoff_hour        = PROP_UNSET_HOUR;
      weekend_cutoff_minute      = 0;

      disable_algo_on_breach     = false;
      algo_switch_max_attempts   = 3;
      algo_switch_verify_secs    = 10;
      close_rounds               = 3;
      close_retries_per_position = 3;
      close_deviation_points     = 20;
      notify_on_escalation       = false;

      magic                      = 0;
      restrict_to_magic          = false;
      safety_buffer_ratio        = 0.80;
      max_pass_age_secs          = 120;

      state_file_name            = "";
      state_in_common_folder     = false;
      state_save_interval_secs   = 30;
      max_days_tracked           = 120;
   }

   //+---------------------------------------------------------------+
   //| C1 gate. Every enabled rule must carry a usable threshold.     |
   //| Returns false and names the offending field, so the consuming  |
   //| EA fails at Init() instead of discovering the problem when a   |
   //| zero threshold flattens the account on the first tick.         |
   //|                                                                |
   //| A DISABLED rule with a zero threshold is perfectly legal and   |
   //| passes -- CRuleRegistry simply never builds it.                |
   //+---------------------------------------------------------------+
   bool Validate(string &err) const
   {
      err = "";

      if(daily_reset_hour < 0 || daily_reset_hour > 23)
         { err = "daily_reset_hour must be 0..23"; return false; }
      if(daily_reset_minute < 0 || daily_reset_minute > 59)
         { err = "daily_reset_minute must be 0..59"; return false; }
      if(timezone_offset_hours < -14 || timezone_offset_hours > 14)
         { err = "timezone_offset_hours must be -14..14"; return false; }
      if(safety_buffer_ratio <= 0.0 || safety_buffer_ratio > 1.0)
         { err = "safety_buffer_ratio must be in (0,1]"; return false; }
      if(max_days_tracked < 2)
         { err = "max_days_tracked must be at least 2"; return false; }
      if(max_pass_age_secs <= 0)
         { err = "max_pass_age_secs must be positive"; return false; }

      if(use_static_dd && static_dd_amount <= 0.0)
         { err = "static_dd_amount is enabled but unset (0.0)"; return false; }

      if(use_trailing_dd && trailing_dd_amount <= 0.0)
         { err = "trailing_dd_amount is enabled but unset (0.0)"; return false; }

      if(use_daily_loss && daily_loss_amount <= 0.0)
         { err = "daily_loss_amount is enabled but unset (0.0)"; return false; }

      if(use_profit_target && profit_target_amount <= 0.0)
         { err = "profit_target_amount is enabled but unset (0.0)"; return false; }

      if(use_consistency && (consistency_max_share <= 0.0 || consistency_max_share >= 1.0))
         { err = "consistency_max_share is enabled but not a share in (0,1)"; return false; }

      if(use_min_trading_days)
      {
         if(min_trading_days <= 0)
            { err = "min_trading_days is enabled but unset (0)"; return false; }
         if(min_qualifying_volume <= 0.0)
            { err = "min_qualifying_volume is enabled but unset (0.0)"; return false; }
      }

      if(use_news_window)
      {
         if(news_block_minutes_before <= 0 && news_block_minutes_after <= 0)
            { err = "news window is enabled but both blackout sides are 0"; return false; }
         if(news_exempt_hours < 0)
            { err = "news_exempt_hours cannot be negative"; return false; }
         if(news_lookahead_minutes <= 0 || news_lookback_minutes < 0)
            { err = "news feed lookahead/lookback window is invalid"; return false; }
         if(news_refresh_secs <= 0)
            { err = "news_refresh_secs must be positive"; return false; }
      }

      if(use_weekend_flat)
      {
         if(weekend_cutoff_hour == PROP_UNSET_HOUR)
            { err = "weekend flat is enabled but weekend_cutoff_hour is unset"; return false; }
         if(weekend_cutoff_hour < 0 || weekend_cutoff_hour > 23)
            { err = "weekend_cutoff_hour must be 0..23"; return false; }
         if(weekend_cutoff_minute < 0 || weekend_cutoff_minute > 59)
            { err = "weekend_cutoff_minute must be 0..59"; return false; }
         if(weekend_cutoff_dow < 0 || weekend_cutoff_dow > 6)
            { err = "weekend_cutoff_dow must be 0..6"; return false; }
      }

      if(disable_algo_on_breach)
      {
         if(algo_switch_max_attempts <= 0)
            { err = "algo_switch_max_attempts must be at least 1"; return false; }
         if(algo_switch_verify_secs <= 0)
            { err = "algo_switch_verify_secs must be at least 1"; return false; }
      }

      if(close_rounds <= 0)
         { err = "close_rounds must be at least 1"; return false; }
      if(close_retries_per_position <= 0)
         { err = "close_retries_per_position must be at least 1"; return false; }

      return true;
   }

   //--- effective lock level of the trailing floor
   double EffectiveLockLevel() const
   {
      if(trailing_lock_level > 0.0)
         return trailing_lock_level;
      return initial_balance + trailing_dd_amount;
   }

   int EnabledRuleCount() const
   {
      int n = 0;
      if(use_static_dd)        n++;
      if(use_trailing_dd)      n++;
      if(use_daily_loss)       n++;
      if(use_profit_target)    n++;
      if(use_consistency)      n++;
      if(use_min_trading_days) n++;
      if(use_news_window)      n++;
      if(use_weekend_flat)     n++;
      return n;
   }
};

//+------------------------------------------------------------------+
//| Terminal inputs.                                                 |
//|                                                                  |
//| Every configurable number of this package lives here, once, so    |
//| the consuming EA gets the full parameter set simply by including  |
//| CPropRulebook.mqh, and BuildProfileFromInputs() is the single |
//| bridge from those inputs into the profile record. The defaults    |
//| deliberately leave every rule DISABLED with a zero threshold:     |
//| the package's C1 stance is that an unconfigured guard must guard  |
//| nothing, never everything.                                        |
//+------------------------------------------------------------------+
input group "=== PropFirm Guard: account ==="
input ENUM_PROP_FIRM_PRESET InpPF_Preset            = PROP_PRESET_CUSTOM; // Firm preset (LoadPreset source)
input double InpPF_AccountSize                      = 0.0;    // Program size (0 = use current balance)
input double InpPF_InitialBalance                   = 0.0;    // Challenge anchor (0 = capture at Init)
input ulong  InpPF_Magic                            = 0;      // Magic of the guarded EA
input bool   InpPF_RestrictToMagic                  = false;  // Guard only that magic's positions
input double InpPF_SafetyBufferRatio                = 0.80;   // Warn once this share of a limit is used
input int    InpPF_MaxPassAgeSecs                   = 120;    // CanOpen() refuses past this pass age

input group "=== PropFirm Guard: prop-day calendar ==="
input int    InpPF_DailyResetHour                   = 0;      // Daily reset hour (firm-local)
input int    InpPF_DailyResetMinute                 = 0;      // Daily reset minute
input int    InpPF_TimezoneOffsetHours              = 0;      // firm_local = server + N hours

input group "=== PropFirm Guard: static drawdown ==="
input bool   InpPF_UseStaticDD                      = false;  // Enable static max drawdown
input double InpPF_StaticDDAmount                   = 0.0;    // Static DD amount (account currency)

input group "=== PropFirm Guard: trailing drawdown ==="
input bool   InpPF_UseTrailingDD                    = false;  // Enable trailing max drawdown
input double InpPF_TrailingDDAmount                 = 0.0;    // Trailing DD amount (account currency)
input ENUM_PROP_TRAIL_MODE InpPF_TrailingMode       = PROP_TRAIL_INTRADAY; // Trailing reference
input bool   InpPF_TrailingLockEnabled              = true;   // Freeze the floor at the lock level
input double InpPF_TrailingLockLevel                = 0.0;    // Lock level (0 = anchor + trail)

input group "=== PropFirm Guard: daily loss ==="
input bool   InpPF_UseDailyLoss                     = false;  // Enable daily loss limit
input double InpPF_DailyLossAmount                  = 0.0;    // Daily loss amount (account currency)

input group "=== PropFirm Guard: profit target ==="
input bool   InpPF_UseProfitTarget                  = false;  // Enable profit target
input double InpPF_ProfitTargetAmount               = 0.0;    // Profit target (above the anchor)
input bool   InpPF_FlattenOnProfitTarget            = false;  // Flatten when the target is reached

input group "=== PropFirm Guard: consistency ==="
input bool   InpPF_UseConsistency                   = false;  // Enable payout consistency rule
input double InpPF_ConsistencyMaxShare              = 0.30;   // Max best-day share of total profit

input group "=== PropFirm Guard: minimum trading days ==="
input bool   InpPF_UseMinTradingDays                = false;  // Enable minimum trading days
input int    InpPF_MinTradingDays                   = 0;      // Required qualifying days
input double InpPF_MinQualifyingVolume              = 0.01;   // Lots that make a day count

input group "=== PropFirm Guard: news blackout ==="
input bool   InpPF_UseNewsWindow                    = false;  // Enable high-impact news blackout
input int    InpPF_NewsMinutesBefore                = 5;      // Blackout minutes before the event
input int    InpPF_NewsMinutesAfter                 = 5;      // Blackout minutes after the event
input int    InpPF_NewsExemptHours                  = 5;      // Positions older than N hours are exempt
input string InpPF_NewsCurrencies                   = "";     // CSV filter ("" = all currencies)
input int    InpPF_NewsLookbackMinutes              = 240;    // Feed window kept behind now
input int    InpPF_NewsLookaheadMinutes             = 1440;   // Feed window read ahead of now
input int    InpPF_NewsRefreshSecs                  = 300;    // Minimum seconds between reads

input group "=== PropFirm Guard: weekend flat ==="
input bool   InpPF_UseWeekendFlat                   = false;  // Enable pre-weekend flat cutoff
input int    InpPF_WeekendCutoffDow                 = 5;      // Cutoff weekday (0=Sun..6=Sat)
input int    InpPF_WeekendCutoffHour                = PROP_UNSET_HOUR; // Cutoff hour (-1 = unset)
input int    InpPF_WeekendCutoffMinute              = 0;      // Cutoff minute

input group "=== PropFirm Guard: protective actions ==="
input bool   InpPF_DisableAlgoOnBreach              = false;  // Toggle Algo Trading off on lockdown
input int    InpPF_AlgoSwitchMaxAttempts            = 3;      // Bounded re-post attempts
input int    InpPF_AlgoSwitchVerifySecs             = 10;     // Seconds before re-check / re-post
input int    InpPF_CloseRounds                      = 3;      // Close sweeps per pass
input int    InpPF_CloseRetriesPerPosition          = 3;      // Retries per position per sweep
input int    InpPF_CloseDeviationPoints             = 20;     // Slippage allowance on close
input bool   InpPF_NotifyOnEscalation               = false;  // Push notification on escalation

input group "=== PropFirm Guard: persistence ==="
input string InpPF_StateFileName                    = "";     // State file ("" = auto per login)
input bool   InpPF_StateInCommonFolder              = false;  // Store in the common data folder
input int    InpPF_StateSaveIntervalSecs            = 30;     // Minimum seconds between saves
input int    InpPF_MaxDaysTracked                   = 120;    // Prop days kept in the ledger

//+------------------------------------------------------------------+
//| Copies the terminal inputs into a profile record.                |
//| Call it in OnInit(), optionally after CPropRulebook::         |
//| LoadPreset() if you want the researched numbers as a starting     |
//| point instead of the zeros above.                                 |
//+------------------------------------------------------------------+
void BuildProfileFromInputs(PropFirmProfile &profile)
{
   profile.account_size               = InpPF_AccountSize;
   profile.initial_balance            = InpPF_InitialBalance;
   profile.magic                      = InpPF_Magic;
   profile.restrict_to_magic          = InpPF_RestrictToMagic;
   profile.safety_buffer_ratio        = InpPF_SafetyBufferRatio;
   profile.max_pass_age_secs          = InpPF_MaxPassAgeSecs;

   profile.daily_reset_hour           = InpPF_DailyResetHour;
   profile.daily_reset_minute         = InpPF_DailyResetMinute;
   profile.timezone_offset_hours      = InpPF_TimezoneOffsetHours;

   profile.use_static_dd              = InpPF_UseStaticDD;
   profile.static_dd_amount           = InpPF_StaticDDAmount;

   profile.use_trailing_dd            = InpPF_UseTrailingDD;
   profile.trailing_dd_amount         = InpPF_TrailingDDAmount;
   profile.trailing_mode              = InpPF_TrailingMode;
   profile.trailing_lock_enabled      = InpPF_TrailingLockEnabled;
   profile.trailing_lock_level        = InpPF_TrailingLockLevel;

   profile.use_daily_loss             = InpPF_UseDailyLoss;
   profile.daily_loss_amount          = InpPF_DailyLossAmount;

   profile.use_profit_target          = InpPF_UseProfitTarget;
   profile.profit_target_amount       = InpPF_ProfitTargetAmount;
   profile.flatten_on_profit_target   = InpPF_FlattenOnProfitTarget;

   profile.use_consistency            = InpPF_UseConsistency;
   profile.consistency_max_share      = InpPF_ConsistencyMaxShare;

   profile.use_min_trading_days       = InpPF_UseMinTradingDays;
   profile.min_trading_days           = InpPF_MinTradingDays;
   profile.min_qualifying_volume      = InpPF_MinQualifyingVolume;

   profile.use_news_window            = InpPF_UseNewsWindow;
   profile.news_block_minutes_before  = InpPF_NewsMinutesBefore;
   profile.news_block_minutes_after   = InpPF_NewsMinutesAfter;
   profile.news_exempt_hours          = InpPF_NewsExemptHours;
   profile.news_currencies            = InpPF_NewsCurrencies;
   profile.news_lookback_minutes      = InpPF_NewsLookbackMinutes;
   profile.news_lookahead_minutes     = InpPF_NewsLookaheadMinutes;
   profile.news_refresh_secs          = InpPF_NewsRefreshSecs;

   profile.use_weekend_flat           = InpPF_UseWeekendFlat;
   profile.weekend_cutoff_dow         = InpPF_WeekendCutoffDow;
   profile.weekend_cutoff_hour        = InpPF_WeekendCutoffHour;
   profile.weekend_cutoff_minute      = InpPF_WeekendCutoffMinute;

   profile.disable_algo_on_breach     = InpPF_DisableAlgoOnBreach;
   profile.algo_switch_max_attempts   = InpPF_AlgoSwitchMaxAttempts;
   profile.algo_switch_verify_secs    = InpPF_AlgoSwitchVerifySecs;
   profile.close_rounds               = InpPF_CloseRounds;
   profile.close_retries_per_position = InpPF_CloseRetriesPerPosition;
   profile.close_deviation_points     = InpPF_CloseDeviationPoints;
   profile.notify_on_escalation       = InpPF_NotifyOnEscalation;

   profile.state_file_name            = InpPF_StateFileName;
   profile.state_in_common_folder     = InpPF_StateInCommonFolder;
   profile.state_save_interval_secs   = InpPF_StateSaveIntervalSecs;
   profile.max_days_tracked           = InpPF_MaxDaysTracked;
}
//+------------------------------------------------------------------+
