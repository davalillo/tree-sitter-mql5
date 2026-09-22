//+------------------------------------------------------------------+
//|                                           CDailyProfitLedger.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Records realized profit and qualifying-trade facts  |
//|               against each prop-firm calendar day, and answers    |
//|               the three aggregate questions the payout rules ask: |
//|               how much was realized in total, which single day    |
//|               was the best, and how many days carried a trade big |
//|               enough to count. It stores facts only -- it owns no |
//|               threshold and produces no verdict.                  |
//| Failure mode: P2 -- attribution uses CPropSessionClock's          |
//|               configurable prop-day index, never server midnight, |
//|               so a deal closed at 16:55 and one closed at 17:05   |
//|               land on different days when the firm's reset hour   |
//|               says they should.                                   |
//|               P5 -- ProjectedBestDayShare() answers "what would   |
//|               the best-day share become if today's open profit    |
//|               were realized right now", which is what lets        |
//|               CRuleCoordinator refuse a profit-target flatten     |
//|               that would manufacture a consistency violation.     |
//|               C9 -- the whole ledger serializes, so a VPS restart |
//|               does not reset the payout arithmetic.               |
//| Dependencies: CPropSessionClock.mqh                               |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+
#include "CPropSessionClock.mqh"

//+------------------------------------------------------------------+
//| One prop-firm calendar day.                                      |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

struct PropDayRecord
{
   int      day_index;       // CPropSessionClock::PropDayIndex()
   datetime day_start;       // server time of that day's boundary
   double   realized;        // net realized P/L (profit + swap + commission)
   double   largest_volume;  // biggest single trade volume booked that day
   double   total_volume;
   int      deal_count;

   PropDayRecord()
   {
      day_index      = 0;
      day_start      = 0;
      realized       = 0.0;
      largest_volume = 0.0;
      total_volume   = 0.0;
      deal_count     = 0;
   }
};

//+------------------------------------------------------------------+
//| Per-day ledger, bounded to max_days records (oldest dropped).    |
//+------------------------------------------------------------------+
class CDailyProfitLedger
{
private:
   CPropSessionClock *m_clock;      // not owned
   PropDayRecord      m_days[];
   int                m_max_days;
   bool               m_ready;

   //--- index of the record for that day, or -1
   int Find(const int day_index) const
   {
      for(int i = ArraySize(m_days) - 1; i >= 0; i--)
         if(m_days[i].day_index == day_index)
            return i;
      return -1;
   }

   //--- appends a record, dropping the oldest one when full
   int Append(const int day_index, const datetime day_start)
   {
      int n = ArraySize(m_days);

      if(n >= m_max_days && m_max_days > 0)
      {
         for(int i = 1; i < n; i++)
            m_days[i - 1] = m_days[i];
         n--;
         ArrayResize(m_days, n);
      }

      if(ArrayResize(m_days, n + 1) != n + 1)
         return -1;

      m_days[n].day_index      = day_index;
      m_days[n].day_start      = day_start;
      m_days[n].realized       = 0.0;
      m_days[n].largest_volume = 0.0;
      m_days[n].total_volume   = 0.0;
      m_days[n].deal_count     = 0;
      return n;
   }

   int Resolve(const datetime when)
   {
      if(m_clock == NULL)
         return -1;
      int idx = m_clock.PropDayIndex(when);
      int pos = Find(idx);
      if(pos >= 0)
         return pos;
      return Append(idx, m_clock.PropDayStart(when));
   }

public:
   CDailyProfitLedger() : m_clock(NULL), m_max_days(120), m_ready(false) {}

   //+---------------------------------------------------------------+
   //| clock is owned by the facade and must outlive this ledger.     |
   //+---------------------------------------------------------------+
   bool Init(CPropSessionClock *clock, const int max_days)
   {
      if(clock == NULL)
      {
         Print("CDailyProfitLedger::Init failed: null session clock");
         return false;
      }
      if(max_days < 2)
      {
         Print("CDailyProfitLedger::Init failed: max_days must be at least 2");
         return false;
      }
      m_clock    = clock;
      m_max_days = max_days;
      ArrayFree(m_days);
      m_ready    = true;
      return true;
   }

   bool IsReady() const { return m_ready; }

   //+---------------------------------------------------------------+
   //| Books one executed deal. net_profit already includes swap and  |
   //| commission; volume is the deal volume in lots and is used for  |
   //| the qualifying-day test only (an entry deal carries volume but |
   //| no profit, an exit deal carries both).                         |
   //+---------------------------------------------------------------+
   bool RecordDeal(const datetime deal_time, const double net_profit, const double volume)
   {
      if(!m_ready)
         return false;

      int pos = Resolve(deal_time);
      if(pos < 0)
         return false;

      m_days[pos].realized     += net_profit;
      m_days[pos].total_volume += volume;
      m_days[pos].deal_count++;

      if(volume > m_days[pos].largest_volume)
         m_days[pos].largest_volume = volume;

      return true;
   }

   //--- makes sure the current day exists in the ledger even before
   //--- the first deal of that day, so panels show a 0.00 row
   bool TouchDay(const datetime when) { return (Resolve(when) >= 0); }

   int  DayCount() const { return ArraySize(m_days); }

   bool DayAt(const int i, PropDayRecord &out) const
   {
      if(i < 0 || i >= ArraySize(m_days))
         return false;
      out = m_days[i];
      return true;
   }

   double RealizedOn(const datetime when) const
   {
      if(m_clock == NULL)
         return 0.0;
      int pos = Find(m_clock.PropDayIndex(when));
      return (pos >= 0) ? m_days[pos].realized : 0.0;
   }

   double TotalRealized() const
   {
      double sum = 0.0;
      for(int i = 0; i < ArraySize(m_days); i++)
         sum += m_days[i].realized;
      return sum;
   }

   //--- best PROFITABLE day; losing days never win this contest
   double BestDayProfit() const
   {
      double best = 0.0;
      for(int i = 0; i < ArraySize(m_days); i++)
         if(m_days[i].realized > best)
            best = m_days[i].realized;
      return best;
   }

   //+---------------------------------------------------------------+
   //| best single day / total profit, as a 0..1 share. Returns 0     |
   //| when total profit is not positive, because "the best day is    |
   //| 300% of a negative total" is arithmetic, not a rule breach.    |
   //+---------------------------------------------------------------+
   double BestDayShare() const
   {
      double total = TotalRealized();
      if(total <= 0.0)
         return 0.0;
      return BestDayProfit() / total;
   }

   //+---------------------------------------------------------------+
   //| P5. The share the account WOULD show if extra_profit were      |
   //| realized on the prop day containing 'when' right now.          |
   //| CPropSnapshotBuilder calls this with the current floating P/L  |
   //| while assembling the frozen snapshot; the coordinator only     |
   //| reads the resulting verdict before allowing a profit-target    |
   //| flatten.                                                        |
   //+---------------------------------------------------------------+
   double ProjectedBestDayShare(const datetime when, const double extra_profit) const
   {
      if(m_clock == NULL)
         return 0.0;

      int today_idx = m_clock.PropDayIndex(when);
      int pos       = Find(today_idx);

      double total = 0.0;
      double best  = 0.0;

      for(int i = 0; i < ArraySize(m_days); i++)
      {
         double value = m_days[i].realized;
         if(i == pos)
            value += extra_profit;
         total += value;
         if(value > best)
            best = value;
      }

      //--- today has no record yet: the projected day is a new one
      if(pos < 0)
      {
         total += extra_profit;
         if(extra_profit > best)
            best = extra_profit;
      }

      if(total <= 0.0)
         return 0.0;
      return best / total;
   }

   //+---------------------------------------------------------------+
   //| Days carrying at least one trade of min_volume lots or more.   |
   //| A day with only a 0.005-lot trade against a 0.01 minimum does  |
   //| not count, which is exactly how the firms count it.            |
   //+---------------------------------------------------------------+
   int QualifyingDays(const double min_volume) const
   {
      int n = 0;
      for(int i = 0; i < ArraySize(m_days); i++)
         if(m_days[i].largest_volume >= min_volume)
            n++;
      return n;
   }

   void ResetAll()
   {
      ArrayFree(m_days);
   }

   //+---------------------------------------------------------------+
   //| Persistence (C9). One record per ';', fields per ','. Neither  |
   //| separator nor '=' nor a newline can appear in the payload, so  |
   //| the key/value store can hold it on a single line.              |
   //+---------------------------------------------------------------+
   string Serialize() const
   {
      string out = "";
      for(int i = 0; i < ArraySize(m_days); i++)
      {
         if(i > 0)
            out += ";";
         out += StringFormat("%d,%d,%.2f,%.2f,%.2f,%d",
                             m_days[i].day_index,
                             (int)m_days[i].day_start,
                             m_days[i].realized,
                             m_days[i].largest_volume,
                             m_days[i].total_volume,
                             m_days[i].deal_count);
      }
      return out;
   }

   bool Deserialize(const string state)
   {
      ArrayFree(m_days);

      if(StringLen(state) == 0)
         return true;

      string records[];
      int rc = StringSplit(state, (ushort)';', records);
      if(rc <= 0)
         return false;

      for(int i = 0; i < rc; i++)
      {
         if(StringLen(records[i]) == 0)
            continue;

         string f[];
         if(StringSplit(records[i], (ushort)',', f) != 6)
         {
            ArrayFree(m_days);
            return false;
         }

         int n = ArraySize(m_days);
         if(ArrayResize(m_days, n + 1) != n + 1)
         {
            ArrayFree(m_days);
            return false;
         }

         m_days[n].day_index      = (int)StringToInteger(f[0]);
         m_days[n].day_start      = (datetime)StringToInteger(f[1]);
         m_days[n].realized       = StringToDouble(f[2]);
         m_days[n].largest_volume = StringToDouble(f[3]);
         m_days[n].total_volume   = StringToDouble(f[4]);
         m_days[n].deal_count     = (int)StringToInteger(f[5]);
      }
      return true;
   }
};
//+------------------------------------------------------------------+
