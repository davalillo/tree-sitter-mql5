//+------------------------------------------------------------------+
//|                                                CPropRulebook.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Public facade of the package. Wires the session     |
//|               clock, profit ledger, calendar feed, excursion      |
//|               tracker, snapshot builder, rule table, coordinator, |
//|               the two actuators and the state store into one      |
//|               guard API, and owns the two things no single        |
//|               component may own: the challenge anchor and the     |
//|               decision to act.                                    |
//| Failure mode: C1 -- Init() refuses to start when any enabled rule |
//|               is unconfigured, so the guard never runs half-armed.|
//|               C2 -- Evaluate() is one build, one evaluation pass, |
//|               one directive. Protective actions happen after the  |
//|               whole table has been evaluated, never during.       |
//|               C3/C7/M1 -- the Algo Trading actuator is verified   |
//|               across passes through IsProtectionSettled(), and    |
//|               Init() fails loudly when DLL permission is missing  |
//|               while automatic control is requested.               |
//|               C4/C9 -- the anchor is captured once, persisted,    |
//|               restored on start and moved by ResetChallenge()     |
//|               alone.                                              |
//|               C5 -- a prop-day rollover drives ResetIntraday()    |
//|               across the table; only ResetChallenge() drives      |
//|               Reset().                                            |
//|               C8 -- "protected" is reported only after the        |
//|               executor verified a flat account.                   |
//|               P5 -- a profit-target flatten that would break the  |
//|               consistency ceiling is downgraded, not executed.    |
//| Dependencies: CPropSnapshotBuilder.mqh, CRuleRegistry.mqh,        |
//|               CRuleCoordinator.mqh, CTerminalAlgoSwitch.mqh,      |
//|               CProtectiveActionExecutor.mqh, CGuardStateStore.mqh,|
//|               CDailyProfitLedger.mqh, CExcursionTracker.mqh       |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

#include "CPropSnapshotBuilder.mqh"
#include "CRuleRegistry.mqh"
#include "CRuleCoordinator.mqh"
#include "CTerminalAlgoSwitch.mqh"
#include "CProtectiveActionExecutor.mqh"
#include "CGuardStateStore.mqh"
#include "CDailyProfitLedger.mqh"
#include "CExcursionTracker.mqh"

//--- persisted key names
#define PFD_KEY_ANCHOR   "anchor"
#define PFD_KEY_CLOCK    "clock"
#define PFD_KEY_LEDGER   "ledger"
#define PFD_KEY_TRACKER  "tracker"
#define PFD_KEY_BUILDER  "builder"
#define PFD_KEY_ALGO     "algo"
#define PFD_KEY_LOCKDOWN "lockdown"
#define PFD_KEY_RULE     "rule."

//+------------------------------------------------------------------+
//| The guard.                                                       |
//+------------------------------------------------------------------+
class CPropRulebook
{
private:
   PropFirmProfile           m_profile;

   //--- owned components, wired here and nowhere else
   CPropSessionClock         m_clock;
   CDailyProfitLedger        m_ledger;
   CEconomicCalendarFeed     m_feed;
   CExcursionTracker         m_tracker;
   CPropSnapshotBuilder      m_builder;
   CRuleRegistry             m_registry;
   CRuleCoordinator          m_coordinator;
   CTerminalAlgoSwitch       m_algo;
   CProtectiveActionExecutor m_executor;
   CGuardStateStore          m_store;

   //--- pass state
   PropAccountSnapshot       m_snap;
   PropRuleVerdict           m_verdicts[];
   ENUM_PROP_DIRECTIVE       m_last_directive;
   ENUM_PROP_DIRECTIVE       m_prev_directive;   // for change-only journal output
   string                    m_last_reason;
   datetime                  m_last_pass_time;

   //--- guard state
   double                    m_anchor;
   bool                      m_initialized;
   bool                      m_lockdown_latched;
   bool                      m_block_new_entries;
   bool                      m_protection_requested;
   bool                      m_last_flatten_ok;
   datetime                  m_last_save;
   bool                      m_state_dirty;
   string                    m_init_error;

   //+---------------------------------------------------------------+
   //| Writes every component's state into the store and flushes it.  |
   //+---------------------------------------------------------------+
   bool PersistState()
   {
      if(!m_store.IsReady())
         return false;

      m_store.SetDouble(PFD_KEY_ANCHOR,  m_anchor);
      m_store.Set(PFD_KEY_CLOCK,         m_clock.Serialize());
      m_store.Set(PFD_KEY_LEDGER,        m_ledger.Serialize());
      m_store.Set(PFD_KEY_TRACKER,       m_tracker.Serialize());
      m_store.Set(PFD_KEY_BUILDER,       m_builder.Serialize());
      m_store.Set(PFD_KEY_ALGO,          m_algo.Serialize());
      m_store.SetBool(PFD_KEY_LOCKDOWN,  m_lockdown_latched);

      for(int i = 0; i < m_registry.Count(); i++)
      {
         IPropRule *rule = m_registry.At(i);
         if(rule == NULL)
            continue;
         m_store.Set(PFD_KEY_RULE + IntegerToString((int)rule.Id()), rule.Serialize());
      }

      bool ok = m_store.Save();
      if(ok)
      {
         m_state_dirty = false;
         m_last_save   = TimeCurrent();
      }
      return ok;
   }

   //+---------------------------------------------------------------+
   //| Restores every component. Returns false on the FIRST piece     |
   //| that does not parse, so the caller can start clean rather than |
   //| run on a mixture of restored and default state (C9).           |
   //+---------------------------------------------------------------+
   bool RestoreComponents()
   {
      if(!m_clock.Deserialize(m_store.Get(PFD_KEY_CLOCK, "")))
         return false;
      if(!m_ledger.Deserialize(m_store.Get(PFD_KEY_LEDGER, "")))
         return false;
      if(!m_tracker.Deserialize(m_store.Get(PFD_KEY_TRACKER, "")))
         return false;
      if(!m_builder.Deserialize(m_store.Get(PFD_KEY_BUILDER, "")))
         return false;
      if(!m_algo.Deserialize(m_store.Get(PFD_KEY_ALGO, "")))
         return false;

      for(int i = 0; i < m_registry.Count(); i++)
      {
         IPropRule *rule = m_registry.At(i);
         if(rule == NULL)
            continue;

         string key = PFD_KEY_RULE + IntegerToString((int)rule.Id());
         if(!m_store.Has(key))
            continue;                    // a rule enabled since the last run
         if(!rule.Deserialize(m_store.Get(key, "")))
         {
            PrintFormat("CPropRulebook: rule %s could not restore its state",
                        rule.Name());
            return false;
         }
      }

      m_lockdown_latched  = m_store.GetBool(PFD_KEY_LOCKDOWN, false);
      m_block_new_entries = m_lockdown_latched;
      if(m_lockdown_latched)
         m_protection_requested = true;

      return true;
   }

   void MaybeSave(const datetime now)
   {
      if(!m_state_dirty)
         return;
      if(m_last_save != 0 &&
         ((long)now - (long)m_last_save) < m_profile.state_save_interval_secs)
         return;
      PersistState();
   }

   //+---------------------------------------------------------------+
   //| The action phase. Runs AFTER the whole table was evaluated, so |
   //| closing positions here cannot influence any rule of this pass  |
   //| (C2). Every rule of the next pass will simply see the new,     |
   //| already-flat account in its own frozen snapshot.               |
   //+---------------------------------------------------------------+
   void ApplyDirective(const ENUM_PROP_DIRECTIVE directive, const string reason)
   {
      //--- Non-latched blocking is recomputed from scratch every pass: a news
      //--- window that has passed, or a weekend cutoff on a new week, must
      //--- stop blocking by itself. Only an account-level lockdown latch
      //--- survives a pass, and only ResetChallenge() lifts that. The same
      //--- applies to "a protective action is outstanding": if no rule is
      //--- asking for one this pass, there is nothing left to settle.
      m_block_new_entries    = m_lockdown_latched;
      m_protection_requested = m_lockdown_latched;

      bool changed = (directive != m_prev_directive);
      m_prev_directive = directive;

      switch(directive)
      {
         case PROP_DIRECTIVE_NONE:
            return;

         case PROP_DIRECTIVE_ADVISORY:
            if(changed)
               PrintFormat("PropFirm Guard [advisory]: %s", reason);
            return;

         case PROP_DIRECTIVE_BLOCK_NEW_ENTRIES:
            if(changed)
               PrintFormat("PropFirm Guard [block]: %s", reason);
            m_block_new_entries = true;
            m_state_dirty       = true;
            return;

         case PROP_DIRECTIVE_FLATTEN:
         {
            m_block_new_entries    = true;
            m_protection_requested = true;
            m_state_dirty          = true;

            if(m_executor.IsFlat())
            {
               m_last_flatten_ok = true;
               return;
            }

            if(changed)
               PrintFormat("PropFirm Guard [flatten]: %s", reason);
            m_last_flatten_ok = m_executor.FlattenAll(reason);
            m_executor.DeletePendingOrders(reason);
            return;
         }

         case PROP_DIRECTIVE_LOCKDOWN:
         {
            bool first             = !m_lockdown_latched;
            m_lockdown_latched     = true;
            m_block_new_entries    = true;
            m_protection_requested = true;
            m_state_dirty          = true;

            if(first)
               PrintFormat("PropFirm Guard [LOCKDOWN]: %s", reason);

            if(!m_executor.IsFlat())
            {
               m_last_flatten_ok = m_executor.FlattenAll(reason);
               m_executor.DeletePendingOrders(reason);
            }
            else
               m_last_flatten_ok = true;

            //--- the switch request is idempotent: it will not post a second
            //--- message while its own latch is still pending (C3/C7)
            if(m_profile.disable_algo_on_breach)
               m_algo.RequestDisable();

            if(first)
               PersistState();           // a breach is worth an immediate flush
            return;
         }
      }
   }

   //--- helper: the raw verdict of one rule from the last pass
   int VerdictIndex(const ENUM_PROP_RULE rule) const
   {
      for(int i = 0; i < ArraySize(m_verdicts); i++)
         if(m_verdicts[i].rule == rule)
            return i;
      return -1;
   }

   //--- tier lookup used by LoadPreset() for the dollar-denominated firms
   static double TierValue(const double account_size,
                           const double small, const double medium, const double large)
   {
      if(account_size <= 50000.0)
         return small;
      if(account_size <= 100000.0)
         return medium;
      return large;
   }

public:
   CPropRulebook()
      : m_last_directive(PROP_DIRECTIVE_NONE), m_last_reason(""), m_last_pass_time(0),
        m_prev_directive(PROP_DIRECTIVE_NONE),
        m_anchor(0.0), m_initialized(false), m_lockdown_latched(false),
        m_block_new_entries(false), m_protection_requested(false),
        m_last_flatten_ok(true), m_last_save(0), m_state_dirty(false),
        m_init_error("") {}

   ~CPropRulebook() { Release(); }

   //+---------------------------------------------------------------+
   //| Validates the profile, checks the DLL permission the Algo      |
   //| Trading switch needs, restores persisted state, captures the   |
   //| initial-balance anchor if none was restored, and builds the    |
   //| rule table from the profile.                                   |
   //|                                                                |
   //| Returns false -- and does NOT guard anything -- when any of    |
   //| those steps fails. There is no partial success here on         |
   //| purpose: a guard that half-started is a guard that lies.       |
   //+---------------------------------------------------------------+
   bool Init(const PropFirmProfile &profile)
   {
      m_initialized = false;
      m_init_error  = "";

      //--- 1. C1 gate: enabled rules must carry usable thresholds
      string err = "";
      if(!profile.Validate(err))
      {
         m_init_error = "profile rejected: " + err;
         Print("CPropRulebook::Init failed -- " + m_init_error);
         return false;
      }
      m_profile = profile;

      //--- 1b. NETTING vs magic filtering. On a netting account there is one
      //--- position per symbol, shared by everything on the account, and its
      //--- POSITION_MAGIC only reflects the deal that last formed it -- it is
      //--- not an ownership tag. Filtering by magic there would make the guard
      //--- under-count exposure and skip positions it should close: a SILENT
      //--- protection failure, the exact class of bug this package exists to
      //--- remove. A prop-firm rulebook applies to the whole account anyway,
      //--- so the safe reading is to watch everything, loudly.
      //--- CUIDADO com a leitura: ACCOUNT_MARGIN_MODE_RETAIL_NETTING vale 0, e
      //--- AccountInfoInteger tambem devolve 0 quando os dados da conta ainda
      //--- nao carregaram. Sem checar prontidao, todo contexto sem conta (ex.:
      //--- a suite de testes, ou um EA anexado antes do terminal sincronizar)
      //--- seria lido como netting e teria o filtro desligado por engano.
      //--- ACCOUNT_LOGIN != 0 e o sinal de que ha conta de verdade carregada.
      bool conta_carregada = (AccountInfoInteger(ACCOUNT_LOGIN) != 0);
      if(conta_carregada && m_profile.restrict_to_magic &&
         (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)
            != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      {
         m_profile.restrict_to_magic = false;
         Print("CPropRulebook: this is a NETTING account, where one position per "
               "symbol is shared by every strategy and POSITION_MAGIC does not "
               "identify an owner. 'restrict_to_magic' was turned OFF: filtering by "
               "magic here would silently hide exposure from the guard. Every "
               "position on the account is now watched, which is what the firm's "
               "rulebook measures anyway.");
      }

      //--- 2. anchor candidate: the profile's, or the live balance
      double anchor = (m_profile.initial_balance > 0.0)
                      ? m_profile.initial_balance
                      : AccountInfoDouble(ACCOUNT_BALANCE);
      if(anchor <= 0.0)
      {
         m_init_error = "cannot determine an initial balance anchor (balance is 0)";
         Print("CPropRulebook::Init failed -- " + m_init_error);
         return false;
      }

      //--- 3. persisted state, BEFORE the rules are configured, because the
      //---    restored anchor is what they must be anchored to (C4/C9)
      m_store.Init(m_profile.state_file_name, m_profile.state_in_common_folder);
      bool restored = m_store.Load();
      if(restored)
      {
         double stored = m_store.GetDouble(PFD_KEY_ANCHOR, 0.0);
         if(stored > 0.0)
         {
            if(MathAbs(stored - anchor) > 0.01)
               PrintFormat("CPropRulebook: restoring the persisted anchor %.2f "
                           "(the profile suggested %.2f) -- the consumed drawdown "
                           "budget is NOT refilled by a restart.", stored, anchor);
            anchor = stored;
         }
         else
         {
            PrintFormat("CPropRulebook: state file has no usable anchor, starting fresh");
            restored = false;
         }
      }
      else
      {
         PrintFormat("CPropRulebook: no usable state restored (%s) -- fresh anchor %.2f",
                     m_store.LastError(), anchor);
      }

      m_anchor                  = anchor;
      m_profile.initial_balance = anchor;

      //--- 4. actuators. The Algo Trading switch checks its own permissions
      //---    and refuses to initialise when it cannot possibly work (M1).
      if(!m_algo.Init(m_profile.disable_algo_on_breach,
                      m_profile.algo_switch_max_attempts,
                      m_profile.algo_switch_verify_secs,
                      m_profile.notify_on_escalation))
      {
         m_init_error = "Algo Trading switch unavailable (see the message above)";
         Print("CPropRulebook::Init failed -- " + m_init_error);
         return false;
      }

      if(!m_executor.Init(m_profile.magic, m_profile.restrict_to_magic,
                          m_profile.close_rounds, m_profile.close_retries_per_position,
                          m_profile.close_deviation_points))
      {
         m_init_error = "protective executor rejected its parameters";
         return false;
      }

      //--- 5. observers
      m_clock.Configure(m_profile);

      if(!m_ledger.Init(GetPointer(m_clock), m_profile.max_days_tracked))
      {
         m_init_error = "daily profit ledger failed to initialise";
         return false;
      }

      if(!m_feed.Init(m_profile.news_currencies,
                      m_profile.news_lookback_minutes,
                      m_profile.news_lookahead_minutes,
                      m_profile.news_refresh_secs))
      {
         m_init_error = "economic calendar feed failed to initialise";
         return false;
      }

      if(!m_tracker.Init(m_anchor))
      {
         m_init_error = "excursion tracker failed to initialise";
         return false;
      }

      if(!m_builder.Init(m_profile, GetPointer(m_clock), GetPointer(m_ledger),
                         GetPointer(m_feed), GetPointer(m_tracker)))
      {
         m_init_error = "snapshot builder failed to initialise";
         return false;
      }

      //--- 6. the rule table (C1)
      if(!m_registry.Build(m_profile, err))
      {
         m_init_error = "rule table rejected: " + err;
         Print("CPropRulebook::Init failed -- " + m_init_error +
               ". Set the missing value, or switch that rule off.");
         return false;
      }

      //--- 7. per-component restore; any failure falls back to a clean start
      if(restored && !RestoreComponents())
      {
         Print("CPropRulebook: persisted state is inconsistent -- discarding it and "
               "starting from a fresh anchor rather than loading partial data.");
         m_store.Delete();
         m_ledger.ResetAll();
         m_tracker.ResetAll(m_anchor);
         m_clock.Reset();
         m_builder.Reset();
         m_algo.ClearLatch();

         //--- rules that had already restored before the failing one must be
         //--- rolled back too, or the table would mix restored and fresh state
         PropAccountSnapshot fresh;
         fresh.Clear();
         fresh.server_time     = TimeCurrent();
         fresh.initial_balance = m_anchor;
         m_coordinator.DriveFullReset(GetPointer(m_registry), fresh);

         m_lockdown_latched     = false;
         m_block_new_entries    = false;
         m_protection_requested = false;
      }

      m_initialized = true;
      m_state_dirty = true;
      PersistState();

      PrintFormat("CPropRulebook ready: firm='%s' anchor=%.2f rules=[%s] restored=%s",
                  m_profile.firm_name, m_anchor, m_registry.Inventory(),
                  (restored ? "yes" : "no"));
      return true;
   }

   //--- flushes state and drops the rule table; call it from OnDeinit()
   void Release()
   {
      if(m_initialized)
      {
         PersistState();
         m_initialized = false;
      }
      m_registry.Clear();
   }

   bool   IsInitialized() const { return m_initialized; }
   string InitError()     const { return m_init_error; }

   //+---------------------------------------------------------------+
   //| One complete non-cascading pass.                               |
   //+---------------------------------------------------------------+
   ENUM_PROP_DIRECTIVE Evaluate()
   {
      if(!m_initialized)
         return PROP_DIRECTIVE_NONE;

      datetime now = TimeCurrent();

      //--- C7: verify the outstanding Algo Trading request against reality
      //--- BEFORE anything else, because a pass that started with a pending
      //--- latch must not pretend the account is already protected
      m_algo.Update(now);

      //--- C2: exactly one observation for the whole pass
      if(!m_builder.Build(now, m_anchor, m_snap))
         return PROP_DIRECTIVE_NONE;

      //--- C5: the prop-day rollover, driven across the table OUTSIDE the
      //--- evaluation phase, rearming intraday latches only
      if(m_snap.is_new_prop_day)
      {
         m_coordinator.DriveIntradayReset(GetPointer(m_registry), m_snap);
         m_state_dirty = true;
         PrintFormat("PropFirm Guard: new prop day starting %s -- intraday rules rearmed",
                     TimeToString(m_snap.prop_day_start, TIME_DATE | TIME_MINUTES));
      }

      //--- two-phase resolution into at most one directive
      string reason = "";
      m_last_directive = m_coordinator.RunPass(GetPointer(m_registry), m_snap,
                                               m_verdicts, reason);
      m_last_reason    = reason;
      m_last_pass_time = now;

      ApplyDirective(m_last_directive, reason);
      MaybeSave(now);

      return m_last_directive;
   }

   //+---------------------------------------------------------------+
   //| Pre-trade gate. Call it immediately before OrderSend().        |
   //|                                                                |
   //| It refuses when the last pass is too old, because a guard that |
   //| has not looked at the account for two minutes cannot honestly  |
   //| clear a trade.                                                 |
   //+---------------------------------------------------------------+
   bool CanOpen(const string symbol, const double volume)
   {
      if(!m_initialized)
         return false;
      if(volume <= 0.0)
         return false;
      if(m_lockdown_latched)
         return false;
      if(m_block_new_entries)
         return false;

      if(m_last_pass_time == 0 ||
         ((long)TimeCurrent() - (long)m_last_pass_time) > m_profile.max_pass_age_secs)
      {
         PrintFormat("CPropRulebook::CanOpen(%s, %.2f) refused: no fresh evaluation "
                     "pass -- call Evaluate() from OnTick() before gating entries.",
                     symbol, volume);
         return false;
      }

      //--- any rule of the last pass still asking for a block wins, even if
      //--- another rule's directive outranked it in the resolution phase
      for(int i = 0; i < ArraySize(m_verdicts); i++)
      {
         if(!m_verdicts[i].evaluated || m_verdicts[i].abstained)
            continue;
         if(PropDirectiveRank(m_verdicts[i].directive) >=
            PropDirectiveRank(PROP_DIRECTIVE_BLOCK_NEW_ENTRIES))
            return false;
      }

      //--- an outstanding, unverified protective request also blocks (C7)
      if(!IsProtectionSettled())
         return false;

      return true;
   }

   //+---------------------------------------------------------------+
   //| Feeds executed deals into the ledger. Call it from the EA's    |
   //| OnTradeTransaction().                                          |
   //+---------------------------------------------------------------+
   void OnTradeTransaction(const MqlTradeTransaction &trans)
   {
      if(!m_initialized)
         return;
      if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
         return;
      if(trans.deal == 0)
         return;
      if(!HistoryDealSelect(trans.deal))
         return;

      long deal_type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      if(deal_type != DEAL_TYPE_BUY && deal_type != DEAL_TYPE_SELL)
         return;                        // balance operations are not trading days

      if(m_profile.restrict_to_magic &&
         (ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != m_profile.magic)
         return;

      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                    + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                    + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      double volume   = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
      datetime when   = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);

      m_ledger.RecordDeal(when, profit, volume);
      m_state_dirty = true;
   }

   //--- direct injection, for tests and for EAs that keep their own book
   bool RecordDeal(const datetime when, const double net_profit, const double volume)
   {
      if(!m_initialized)
         return false;
      m_state_dirty = true;
      return m_ledger.RecordDeal(when, net_profit, volume);
   }

   //+---------------------------------------------------------------+
   //| Last verdict of one rule. An unregistered rule yields a        |
   //| verdict with evaluated == false, never a fabricated "OK".      |
   //+---------------------------------------------------------------+
   PropRuleVerdict GetVerdict(const ENUM_PROP_RULE rule)
   {
      int idx = VerdictIndex(rule);
      if(idx >= 0)
         return m_verdicts[idx];

      PropRuleVerdict empty;
      empty.Clear();
      empty.rule = rule;
      return empty;
   }

   double GetHeadroom(const ENUM_PROP_RULE rule)
   {
      int idx = VerdictIndex(rule);
      return (idx >= 0) ? m_verdicts[idx].headroom : 0.0;
   }

   ENUM_PROP_DIRECTIVE LastDirective() const { return m_last_directive; }
   string              LastReason()    const { return m_last_reason; }
   double              Anchor()        const { return m_anchor; }
   int                 RuleCount()     const { return m_registry.Count(); }
   bool                IsLockedDown()  const { return m_lockdown_latched; }
   bool                LastFlattenOk() const { return m_last_flatten_ok; }
   bool                EntriesBlocked() const { return m_block_new_entries; }

   void GetSnapshot(PropAccountSnapshot &out) const { out = m_snap; }

   //--- component access for tests, panels and synthetic calendar injection
   CEconomicCalendarFeed *CalendarFeed()  { return GetPointer(m_feed); }
   CDailyProfitLedger    *Ledger()        { return GetPointer(m_ledger); }
   CPropSessionClock     *SessionClock()  { return GetPointer(m_clock); }
   CRuleRegistry         *Registry()      { return GetPointer(m_registry); }
   CTerminalAlgoSwitch   *AlgoSwitch()    { return GetPointer(m_algo); }

   //+---------------------------------------------------------------+
   //| Payout eligibility: the two rules that block a withdrawal      |
   //| rather than the account.                                       |
   //+---------------------------------------------------------------+
   bool IsPayoutEligible(string &reason)
   {
      reason = "";
      bool eligible = true;

      int idx = VerdictIndex(PROP_RULE_CONSISTENCY);
      if(idx >= 0 && m_verdicts[idx].evaluated && !m_verdicts[idx].abstained &&
         m_verdicts[idx].severity >= PROP_SEV_ADVISORY)
      {
         eligible = false;
         reason   = m_verdicts[idx].message;
      }

      idx = VerdictIndex(PROP_RULE_MIN_TRADING_DAYS);
      if(idx >= 0 && m_verdicts[idx].evaluated && !m_verdicts[idx].abstained &&
         m_verdicts[idx].severity >= PROP_SEV_ADVISORY)
      {
         eligible = false;
         reason   = (StringLen(reason) > 0)
                    ? (reason + " | " + m_verdicts[idx].message)
                    : m_verdicts[idx].message;
      }

      if(eligible)
         reason = "consistency and minimum-trading-days requirements are satisfied";

      return eligible;
   }

   //+---------------------------------------------------------------+
   //| C7/C8. The only honest answer to "is the account protected?".  |
   //| False while any requested action is still in flight or failed. |
   //+---------------------------------------------------------------+
   bool IsProtectionSettled()
   {
      if(!m_initialized)
         return false;
      if(!m_protection_requested)
         return true;

      if(!m_executor.IsFlat())
         return false;

      if(m_profile.disable_algo_on_breach && !m_algo.IsSettled())
         return false;

      return true;
   }

   //+---------------------------------------------------------------+
   //| Manual, audited flatten. Same retcode-checked path a rule      |
   //| breach uses, so a manual panic button cannot report a success  |
   //| the automatic path would have caught as a failure.             |
   //+---------------------------------------------------------------+
   bool ForceFlatten(const string reason)
   {
      if(!m_initialized)
         return false;

      m_protection_requested = true;
      m_block_new_entries    = true;
      m_state_dirty          = true;

      PrintFormat("PropFirm Guard [manual flatten]: %s", reason);
      m_last_flatten_ok = m_executor.FlattenAll("manual: " + reason);
      m_executor.DeletePendingOrders("manual: " + reason);

      PersistState();
      return m_last_flatten_ok;
   }

   //+---------------------------------------------------------------+
   //| C4. The single operation allowed to move the anchor and clear  |
   //| an account-level breach latch. Everything else in the package  |
   //| treats the anchor as read-only.                                |
   //+---------------------------------------------------------------+
   void ResetChallenge(const double new_initial_balance)
   {
      if(!m_initialized)
         return;

      double anchor = (new_initial_balance > 0.0)
                      ? new_initial_balance
                      : AccountInfoDouble(ACCOUNT_BALANCE);
      if(anchor <= 0.0)
      {
         Print("CPropRulebook::ResetChallenge refused: no usable balance to anchor to");
         return;
      }

      m_anchor                  = anchor;
      m_profile.initial_balance = anchor;

      //--- a fresh observation carrying the NEW anchor, so every rule's
      //--- Reset() re-anchors to the same number
      datetime now = TimeCurrent();
      m_builder.Reset();
      m_builder.Build(now, m_anchor, m_snap);

      m_coordinator.DriveFullReset(GetPointer(m_registry), m_snap);

      m_ledger.ResetAll();
      m_tracker.ResetAll(m_anchor);
      m_clock.Reset();
      m_algo.ClearLatch();

      m_lockdown_latched     = false;
      m_block_new_entries    = false;
      m_protection_requested = false;
      m_last_flatten_ok      = true;
      m_last_directive       = PROP_DIRECTIVE_NONE;
      m_prev_directive       = PROP_DIRECTIVE_NONE;
      m_last_reason          = "";
      ArrayFree(m_verdicts);

      m_state_dirty = true;
      PersistState();

      PrintFormat("PropFirm Guard: challenge reset, new anchor %.2f, every rule "
                  "re-armed and every latch cleared.", m_anchor);
   }

   //+---------------------------------------------------------------+
   //| One-line telemetry for the journal or a screenshot.            |
   //+---------------------------------------------------------------+
   string StatusReport()
   {
      if(!m_initialized)
         return "PFD: not initialised (" + m_init_error + ")";

      string s = StringFormat("PFD eq=%.2f bal=%.2f anchor=%.2f dir=%s",
                              m_snap.equity, m_snap.balance, m_anchor,
                              PropDirectiveName(m_last_directive));

      for(int i = 0; i < ArraySize(m_verdicts); i++)
      {
         if(!m_verdicts[i].evaluated)
            continue;
         s += " | " + m_verdicts[i].ToString();
      }

      s += " | " + m_algo.StateText();
      s += StringFormat(" | settled=%s pos=%d",
                        (IsProtectionSettled() ? "yes" : "no"), m_snap.positions_total);
      return s;
   }

   //+---------------------------------------------------------------+
   //| Fills a profile with the researched threshold set of a known   |
   //| firm family, scaled to account_size, so the caller starts from |
   //| real numbers instead of zeros.                                 |
   //|                                                                |
   //| HONESTY NOTE, and it belongs in the code rather than only in   |
   //| the article: prop-firm rulebooks change, differ per programme  |
   //| and per account tier, and no preset can be authoritative.      |
   //| Percentage-based limits below are scaled from account_size;    |
   //| dollar-denominated ones use the published tier figures. Check  |
   //| every number against your own contract before trading it --    |
   //| the presets exist so nobody starts from 0.0 (which is what     |
   //| makes a naive guard fire on its first tick), not so that       |
   //| anybody skips reading their rules.                             |
   //+---------------------------------------------------------------+
   static bool LoadPreset(PropFirmProfile &profile,
                          const ENUM_PROP_FIRM_PRESET preset,
                          const double account_size)
   {
      double size = (account_size > 0.0) ? account_size : AccountInfoDouble(ACCOUNT_BALANCE);
      if(size <= 0.0)
      {
         Print("CPropRulebook::LoadPreset failed: account_size must be positive");
         return false;
      }

      profile.Clear();
      profile.account_size    = size;
      profile.initial_balance = size;

      switch(preset)
      {
         //--- Static profile: a STATIC 10% overall loss limit measured from the
         //--- starting balance, a 5% daily loss limit, a 10% phase-one
         //--- target, and a daily reset at midnight in the firm's timezone.
         case PROP_PRESET_STATIC_DD:
         {
            profile.firm_name                 = "Static drawdown (fixed floor)";

            profile.use_static_dd             = true;
            profile.static_dd_amount          = 0.10 * size;

            profile.use_daily_loss            = true;
            profile.daily_loss_amount         = 0.05 * size;

            profile.use_profit_target         = true;
            profile.profit_target_amount      = 0.10 * size;
            profile.flatten_on_profit_target  = false;

            profile.daily_reset_hour          = 0;      // midnight, firm-local
            profile.timezone_offset_hours     = 0;      // set to your broker's offset

            //--- news restriction applies on the standard (non-swing) product
            profile.use_news_window           = true;
            profile.news_block_minutes_before = 5;
            profile.news_block_minutes_after  = 5;
            profile.news_exempt_hours         = 5;

            //--- no consistency rule and no minimum trading days on this
            //--- family; the threshold is left present but switched off
            profile.consistency_max_share     = 0.30;
            profile.use_consistency           = false;
            profile.use_min_trading_days      = false;

            //--- weekend holding is permitted on the swing product, so this
            //--- one is off by default. Switch it on if yours is not.
            profile.use_weekend_flat          = false;
            break;
         }

         //--- Trailing profile: TRAILING drawdown that ratchets with the peak
         //--- and LOCKS once balance reaches start + trail (a 50k account
         //--- locks its floor at 50k when balance touches 52k), plus a
         //--- per-tier daily loss limit and a 17:00 session boundary.
         case PROP_PRESET_TRAILING_LOCKED:
         {
            profile.firm_name                 = "Trailing drawdown (ratchets, then locks)";

            profile.use_trailing_dd           = true;
            profile.trailing_dd_amount        = TierValue(size, 2000.0, 3000.0, 4500.0);
            //--- the punitive variant is the safe default: guarding tighter
            //--- than the contract cannot fail a challenge, guarding looser
            //--- can. Switch to PROP_TRAIL_END_OF_DAY if your programme only
            //--- trails on the closed balance at rollover.
            profile.trailing_mode             = PROP_TRAIL_INTRADAY;
            profile.trailing_lock_enabled     = true;
            profile.trailing_lock_level       = 0.0;    // = anchor + trail

            profile.use_daily_loss            = true;
            profile.daily_loss_amount         = TierValue(size, 1000.0, 2000.0, 3000.0);

            profile.use_profit_target         = true;
            profile.profit_target_amount      = TierValue(size, 3000.0, 6000.0, 9000.0);
            profile.flatten_on_profit_target  = false;

            profile.daily_reset_hour          = 17;     // session boundary, firm-local
            profile.timezone_offset_hours     = 0;

            profile.use_consistency           = true;
            profile.consistency_max_share     = 0.30;

            profile.use_min_trading_days      = true;
            profile.min_trading_days          = 5;
            profile.min_qualifying_volume     = 0.01;

            profile.use_weekend_flat          = true;
            profile.weekend_cutoff_dow        = 5;      // Friday
            profile.weekend_cutoff_hour       = 20;
            profile.weekend_cutoff_minute     = 0;

            profile.use_news_window           = false;
            break;
         }

         //--- Trailing profile, variant: the same mechanic, typically without a
         //--- separate daily loss cap.
         case PROP_PRESET_TRAILING_NO_DAILY:
         {
            profile.firm_name                 = "Trailing drawdown (no daily cap)";

            profile.use_trailing_dd           = true;
            profile.trailing_dd_amount        = TierValue(size, 2500.0, 3000.0, 5000.0);
            profile.trailing_mode             = PROP_TRAIL_INTRADAY;
            profile.trailing_lock_enabled     = true;
            profile.trailing_lock_level       = 0.0;

            //--- no daily loss limit in this family; set it yourself if your
            //--- programme has one rather than leaving a zero behind
            profile.use_daily_loss            = false;
            profile.daily_loss_amount         = 0.0;

            profile.use_profit_target         = true;
            profile.profit_target_amount      = TierValue(size, 3000.0, 6000.0, 9000.0);

            profile.daily_reset_hour          = 17;
            profile.timezone_offset_hours     = 0;

            profile.use_consistency           = true;
            profile.consistency_max_share     = 0.30;

            profile.use_min_trading_days      = true;
            profile.min_trading_days          = 5;
            profile.min_qualifying_volume     = 0.01;

            profile.use_weekend_flat          = true;
            profile.weekend_cutoff_dow        = 5;
            profile.weekend_cutoff_hour       = 20;
            profile.weekend_cutoff_minute     = 0;

            profile.use_news_window           = false;
            break;
         }

         //--- Static profile with payouts: static drawdown plus the payout rule
         //--- set (consistency and minimum trading days both active).
         case PROP_PRESET_STATIC_WITH_PAYOUT:
         {
            profile.firm_name                 = "Static drawdown (with payout rules)";

            profile.use_static_dd             = true;
            profile.static_dd_amount          = 0.10 * size;

            profile.use_daily_loss            = true;
            profile.daily_loss_amount         = 0.05 * size;

            profile.use_profit_target         = true;
            profile.profit_target_amount      = 0.10 * size;

            profile.daily_reset_hour          = 0;
            profile.timezone_offset_hours     = 0;

            profile.use_consistency           = true;
            profile.consistency_max_share     = 0.30;

            profile.use_min_trading_days      = true;
            profile.min_trading_days          = 5;
            profile.min_qualifying_volume     = 0.01;

            profile.use_news_window           = true;
            profile.news_block_minutes_before = 5;
            profile.news_block_minutes_after  = 5;
            profile.news_exempt_hours         = 5;

            profile.use_weekend_flat          = true;
            profile.weekend_cutoff_dow        = 5;
            profile.weekend_cutoff_hour       = 20;
            profile.weekend_cutoff_minute     = 0;
            break;
         }

         //--- CUSTOM stays exactly as Clear() left it: every rule off, every
         //--- threshold zero, nothing registered. That is the C1-safe state.
         default:
            profile.firm_name = "Custom";
            break;
      }

      return true;
   }
};
//+------------------------------------------------------------------+
