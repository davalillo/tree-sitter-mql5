//+------------------------------------------------------------------+
//|                                          PropAccountSnapshot.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Immutable per-pass data record holding every       |
//|               account, session, excursion, exposure and calendar |
//|               figure a rule evaluator is allowed to read. It     |
//|               carries no logic of its own: no thresholds, no     |
//|               comparisons, no verdicts. Exactly one instance is  |
//|               built per Evaluate() pass by CPropSnapshotBuilder, |
//|               and every rule in that pass reads that same frozen |
//|               copy instead of re-reading live account state.     |
//| Failure mode: Re-reading live account/position state inside each |
//|               of a dozen trigger checks while an earlier trigger |
//|               is still mutating shared flags lets one pass       |
//|               cascade into up to a dozen firings. A single       |
//|               frozen record per pass makes that class of cascade |
//|               structurally impossible: no rule can observe a     |
//|               mid-pass change because there is nothing live left |
//|               to observe.                                        |
//| Dependencies: none                                               |
//| Part of:      PropFirm Guard class package                    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| One frozen observation of the guarded account.                   |
//|                                                                  |
//| Contract (enforced by convention, see IPropRule.mqh):            |
//|  - CPropSnapshotBuilder is the ONLY writer.                      |
//|  - Rules receive it as "const PropAccountSnapshot &" and must    |
//|    never call AccountInfoDouble(), PositionsTotal(), TimeCurrent()|
//|    or the calendar API directly.                                 |
//|  - Every figure below is measured at the same instant, so two    |
//|    rules in the same pass can never disagree about the account.  |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

struct PropAccountSnapshot
{
   //--- pass identity -----------------------------------------------
   ulong    pass_id;                 // monotonic counter, 1 for the first pass
   datetime server_time;             // TimeCurrent() at the moment of the build

   //--- account figures (each terminal function called exactly once) -
   double   balance;
   double   equity;
   double   credit;
   double   floating_pl;             // equity - balance - credit
   double   margin;
   double   free_margin;
   double   margin_level;            // percent, 0.0 when margin is 0
   double   initial_balance;         // challenge anchor supplied by the facade

   //--- prop-firm calendar (from CPropSessionClock) ------------------
   int      prop_day_index;          // integer day number under the firm's reset hour
   datetime prop_day_start;          // server time of the current prop day's boundary
   bool     is_new_prop_day;         // true only on the first pass of a new prop day
   bool     past_weekend_cutoff;     // pre-weekend flat cutoff already reached
   int      minutes_to_weekend_cutoff;

   //--- current prop day --------------------------------------------
   double   day_start_balance;       // balance captured at the day boundary
   double   day_start_equity;        // equity captured at the day boundary
   double   realized_today;          // realized P/L booked to the current prop day

   //--- ledger aggregates (from CDailyProfitLedger) ------------------
   double   total_realized_profit;   // sum of realized P/L over every tracked day
   double   best_day_profit;         // largest single prop-day realized profit
   double   best_day_share;          // best_day_profit / total_realized_profit, 0..1
   double   projected_best_day_share;// same share IF today's floating P/L were realized now
   int      qualifying_days;         // days carrying a trade of at least the minimum volume

   //--- excursion measurement (from CExcursionTracker, C6) -----------
   //--- Measurement only. No rule may derive a trigger from these.
   double   peak_balance;
   double   peak_equity;
   double   trough_equity;
   double   mfe_balance;             // max favourable excursion of balance
   double   mae_balance;             // max adverse excursion of balance (positive number)
   double   mfe_equity;
   double   mae_equity;

   //--- exposure ------------------------------------------------------
   int      positions_total;         // positions relevant to this guard (magic filtered)
   double   open_volume;             // summed lots of those positions
   int      pending_orders;          // pending orders relevant to this guard
   datetime oldest_position_time;    // open time of the oldest relevant position
   datetime newest_position_time;    // open time of the newest relevant position

   //--- economic calendar (from CEconomicCalendarFeed) ----------------
   bool     news_available;          // false in Strategy Tester / when calendar is unreachable
   bool     has_next_event;
   bool     has_last_event;
   int      minutes_to_next_event;   // >= 0 when has_next_event, else -1
   int      minutes_since_last_event;// >= 0 when has_last_event, else -1
   datetime next_event_time;
   datetime last_event_time;
   string   next_event_name;
   string   last_event_name;

   //--- terminal permissions (read once, like everything else) --------
   bool     terminal_trade_allowed;  // TERMINAL_TRADE_ALLOWED
   bool     expert_trade_allowed;    // MQL_TRADE_ALLOWED

   PropAccountSnapshot() { Clear(); }

   void Clear()
   {
      pass_id                  = 0;
      server_time              = 0;

      balance                  = 0.0;
      equity                   = 0.0;
      credit                   = 0.0;
      floating_pl              = 0.0;
      margin                   = 0.0;
      free_margin              = 0.0;
      margin_level             = 0.0;
      initial_balance          = 0.0;

      prop_day_index           = 0;
      prop_day_start           = 0;
      is_new_prop_day          = false;
      past_weekend_cutoff      = false;
      minutes_to_weekend_cutoff= 0;

      day_start_balance        = 0.0;
      day_start_equity         = 0.0;
      realized_today           = 0.0;

      total_realized_profit    = 0.0;
      best_day_profit          = 0.0;
      best_day_share           = 0.0;
      projected_best_day_share = 0.0;
      qualifying_days          = 0;

      peak_balance             = 0.0;
      peak_equity              = 0.0;
      trough_equity            = 0.0;
      mfe_balance              = 0.0;
      mae_balance              = 0.0;
      mfe_equity               = 0.0;
      mae_equity               = 0.0;

      positions_total          = 0;
      open_volume              = 0.0;
      pending_orders           = 0;
      oldest_position_time     = 0;
      newest_position_time     = 0;

      news_available           = false;
      has_next_event           = false;
      has_last_event           = false;
      minutes_to_next_event    = -1;
      minutes_since_last_event = -1;
      next_event_time          = 0;
      last_event_time          = 0;
      next_event_name          = "";
      last_event_name          = "";

      terminal_trade_allowed   = false;
      expert_trade_allowed     = false;
   }

   //--- convenience readers used by several rules ---------------------
   bool   HasExposure()      const { return positions_total > 0; }
   double DayLoss()          const { return day_start_balance - equity; }   // positive while losing
   double DayProfit()        const { return equity - day_start_balance; }
   double ChallengeProfit()  const { return equity - initial_balance; }
};
//+------------------------------------------------------------------+
