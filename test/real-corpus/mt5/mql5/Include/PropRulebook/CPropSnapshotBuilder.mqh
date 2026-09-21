//+------------------------------------------------------------------+
//|                                         CPropSnapshotBuilder.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Assembles the one frozen PropAccountSnapshot that   |
//|               every rule of a single evaluation pass reads:       |
//|               account figures, prop-day boundary and rollover,    |
//|               the day's opening balance, ledger aggregates,       |
//|               exposure, calendar proximity and excursion          |
//|               measurements -- each terminal function called       |
//|               exactly once per pass.                              |
//| Failure mode: This is the structural core of the cascade fix.     |
//|               When each of a dozen trigger checks re-reads        |
//|               AccountInfoDouble()/PositionsTotal() while earlier  |
//|               checks are still closing positions and clearing     |
//|               shared flags, later checks see a different account  |
//|               than earlier ones and fire on the consequences of   |
//|               the first firing. Here the account is observed      |
//|               once, and rules receive a const reference to that   |
//|               observation. The builder is also where the prop-day |
//|               rollover is detected and the day's opening balance  |
//|               is captured, so "which day are we in" has exactly   |
//|               one answer per pass.                                |
//| Dependencies: PropAccountSnapshot.mqh, PropFirmProfile.mqh,       |
//|               CPropSessionClock.mqh, CDailyProfitLedger.mqh,      |
//|               CEconomicCalendarFeed.mqh, CExcursionTracker.mqh    |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+
#include "PropAccountSnapshot.mqh"
#include "PropFirmProfile.mqh"
#include "CPropSessionClock.mqh"
#include "CDailyProfitLedger.mqh"
#include "CEconomicCalendarFeed.mqh"
#include "CExcursionTracker.mqh"

//+------------------------------------------------------------------+
//| The single writer of PropAccountSnapshot.                        |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

class CPropSnapshotBuilder
{
private:
   PropFirmProfile        m_profile;

   //--- collaborators owned by the facade, never by this class
   CPropSessionClock     *m_clock;
   CDailyProfitLedger    *m_ledger;
   CEconomicCalendarFeed *m_feed;
   CExcursionTracker     *m_tracker;

   //--- day baseline, captured at the boundary and held until the next
   double                 m_day_start_balance;
   double                 m_day_start_equity;
   int                    m_day_index;
   bool                   m_day_seeded;

   ulong                  m_pass_id;
   bool                   m_ready;

   //+---------------------------------------------------------------+
   //| Single sweep over open positions. Runs once per pass; the      |
   //| numbers it produces are the only exposure figures any rule     |
   //| will see this pass.                                            |
   //+---------------------------------------------------------------+
   void ScanExposure(PropAccountSnapshot &snap) const
   {
      int      count  = 0;
      double   volume = 0.0;
      datetime oldest = 0;
      datetime newest = 0;

      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(!PositionSelectByTicket(ticket))
            continue;
         if(m_profile.restrict_to_magic &&
            (ulong)PositionGetInteger(POSITION_MAGIC) != m_profile.magic)
            continue;

         datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
         count++;
         volume += PositionGetDouble(POSITION_VOLUME);

         if(oldest == 0 || opened < oldest) oldest = opened;
         if(newest == 0 || opened > newest) newest = opened;
      }

      int pendings = 0;
      int orders   = OrdersTotal();
      for(int i = orders - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0)
            continue;
         if(m_profile.restrict_to_magic &&
            (ulong)OrderGetInteger(ORDER_MAGIC) != m_profile.magic)
            continue;
         pendings++;
      }

      snap.positions_total      = count;
      snap.open_volume          = volume;
      snap.pending_orders       = pendings;
      snap.oldest_position_time = oldest;
      snap.newest_position_time = newest;
   }

   void FillCalendar(PropAccountSnapshot &snap, const datetime now) const
   {
      snap.news_available           = false;
      snap.has_next_event           = false;
      snap.has_last_event           = false;
      snap.minutes_to_next_event    = -1;
      snap.minutes_since_last_event = -1;

      if(m_feed == NULL || !m_feed.IsAvailable())
         return;

      snap.news_available = true;

      datetime when = 0;
      string   name = "";
      string   ccy  = "";

      if(m_feed.NextEvent(now, when, name, ccy))
      {
         snap.has_next_event        = true;
         snap.next_event_time       = when;
         snap.next_event_name       = name;
         snap.minutes_to_next_event = (int)(((long)when - (long)now) / 60);
      }

      if(m_feed.LastEvent(now, when, name, ccy))
      {
         snap.has_last_event           = true;
         snap.last_event_time          = when;
         snap.last_event_name          = name;
         snap.minutes_since_last_event = (int)(((long)now - (long)when) / 60);
      }
   }

public:
   CPropSnapshotBuilder()
      : m_clock(NULL), m_ledger(NULL), m_feed(NULL), m_tracker(NULL),
        m_day_start_balance(0.0), m_day_start_equity(0.0), m_day_index(0),
        m_day_seeded(false), m_pass_id(0), m_ready(false) {}

   //+---------------------------------------------------------------+
   //| Every collaborator is owned by CPropRulebook and must      |
   //| outlive this builder.                                          |
   //+---------------------------------------------------------------+
   bool Init(const PropFirmProfile &profile,
             CPropSessionClock *clock,
             CDailyProfitLedger *ledger,
             CEconomicCalendarFeed *feed,
             CExcursionTracker *tracker)
   {
      if(clock == NULL || ledger == NULL || feed == NULL || tracker == NULL)
      {
         Print("CPropSnapshotBuilder::Init failed: a collaborator pointer is NULL");
         return false;
      }

      m_profile = profile;
      m_clock   = clock;
      m_ledger  = ledger;
      m_feed    = feed;
      m_tracker = tracker;
      m_pass_id = 0;
      m_ready   = true;
      return true;
   }

   bool IsReady() const { return m_ready; }

   //+---------------------------------------------------------------+
   //| Builds the pass's single observation.                          |
   //|                                                                |
   //| anchor is the challenge initial balance owned and persisted by |
   //| the facade -- the builder never captures it itself, because a  |
   //| builder that re-captured the anchor on restart would refill    |
   //| the consumed drawdown budget (C4/C9).                          |
   //+---------------------------------------------------------------+
   bool Build(const datetime now, const double anchor, PropAccountSnapshot &snap)
   {
      if(!m_ready)
         return false;

      snap.Clear();

      m_pass_id++;
      snap.pass_id     = m_pass_id;
      snap.server_time = now;

      //--- account: read once, here, and nowhere else in the pass
      snap.balance      = AccountInfoDouble(ACCOUNT_BALANCE);
      snap.equity       = AccountInfoDouble(ACCOUNT_EQUITY);
      snap.credit       = AccountInfoDouble(ACCOUNT_CREDIT);
      snap.margin       = AccountInfoDouble(ACCOUNT_MARGIN);
      snap.free_margin  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      snap.margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      snap.floating_pl  = snap.equity - snap.balance - snap.credit;
      snap.initial_balance = anchor;

      //--- prop-day calendar
      snap.prop_day_index            = m_clock.PropDayIndex(now);
      snap.prop_day_start            = m_clock.PropDayStart(now);
      snap.is_new_prop_day           = m_clock.DetectRollover(now);
      snap.past_weekend_cutoff       = m_clock.IsPastWeekendCutoff(now);
      snap.minutes_to_weekend_cutoff = m_clock.MinutesToWeekendCutoff(now);

      //--- day baseline: captured at the boundary, then held constant so
      //--- the daily loss rule measures against a fixed reference all day
      if(!m_day_seeded || snap.is_new_prop_day || m_day_index != snap.prop_day_index)
      {
         m_day_start_balance = snap.balance;
         m_day_start_equity  = snap.equity;
         m_day_index         = snap.prop_day_index;
         m_day_seeded        = true;
      }
      snap.day_start_balance = m_day_start_balance;
      snap.day_start_equity  = m_day_start_equity;

      //--- ledger aggregates
      m_ledger.TouchDay(now);
      snap.realized_today           = m_ledger.RealizedOn(now);
      snap.total_realized_profit    = m_ledger.TotalRealized();
      snap.best_day_profit          = m_ledger.BestDayProfit();
      snap.best_day_share           = m_ledger.BestDayShare();
      snap.projected_best_day_share = m_ledger.ProjectedBestDayShare(now, snap.floating_pl);
      snap.qualifying_days          = m_ledger.QualifyingDays(m_profile.min_qualifying_volume);

      //--- exposure
      ScanExposure(snap);

      //--- calendar
      m_feed.Refresh(now);
      FillCalendar(snap, now);

      //--- excursion measurement (diagnostic only, C6)
      m_tracker.Update(snap.balance, snap.equity);
      snap.peak_balance  = m_tracker.PeakBalance();
      snap.peak_equity   = m_tracker.PeakEquity();
      snap.trough_equity = m_tracker.TroughEquity();
      snap.mfe_balance   = m_tracker.MfeBalance();
      snap.mae_balance   = m_tracker.MaeBalance();
      snap.mfe_equity    = m_tracker.MfeEquity();
      snap.mae_equity    = m_tracker.MaeEquity();

      //--- terminal permissions
      snap.terminal_trade_allowed = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
      snap.expert_trade_allowed   = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);

      return true;
   }

   ulong PassId() const { return m_pass_id; }

   //--- full reset, driven only by CPropRulebook::ResetChallenge()
   void Reset()
   {
      m_day_seeded        = false;
      m_day_start_balance = 0.0;
      m_day_start_equity  = 0.0;
      m_day_index         = 0;
   }

   //--- persistence (C9): the day baseline must survive a restart, or a
   //--- terminal that reboots mid-session would rebase the daily loss
   //--- measurement at the already-reduced balance
   string Serialize() const
   {
      return StringFormat("%.2f,%.2f,%d,%d",
                          m_day_start_balance, m_day_start_equity,
                          m_day_index, (m_day_seeded ? 1 : 0));
   }

   bool Deserialize(const string state)
   {
      string f[];
      if(StringSplit(state, (ushort)',', f) != 4)
         return false;
      double day_balance = StringToDouble(f[0]);
      bool   seeded      = ((int)StringToInteger(f[3]) == 1);

      //--- a seeded day whose opening balance is 0 would make the daily loss
      //--- rule measure "0 - equity", i.e. a permanent profit, and silently
      //--- disarm it. Reject the record instead and let the facade re-seed.
      if(seeded && day_balance <= 0.0)
         return false;

      m_day_start_balance = day_balance;
      m_day_start_equity  = StringToDouble(f[1]);
      m_day_index         = (int)StringToInteger(f[2]);
      m_day_seeded        = seeded;
      return true;
   }
};
//+------------------------------------------------------------------+
