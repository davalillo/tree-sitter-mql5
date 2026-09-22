//+------------------------------------------------------------------+
//|                                              CSetupLedger.mqh     |
//|                                          Copyright 2026, Ali Rajput|
//|                                                                    |
//| A per-setup-type performance ledger for MQL5 Expert Advisors.      |
//|                                                                    |
//| Most EAs fire on several genuinely different setup types but are   |
//| judged by one equity curve. This class scores each setup type      |
//| separately, rebuilds itself from the account's own deal history    |
//| on every init, and reports a Wilson score lower bound so you can   |
//| tell a real edge from a small sample.                              |
//|                                                                    |
//| Design notes:                                                      |
//|   - Setup type is encoded in the MAGIC NUMBER, not the position    |
//|     comment. Brokers overwrite comments ("so:", "[sl]", "[tp]");   |
//|     they never touch the magic number.                             |
//|   - Trades are aggregated by position, not per deal. A partially   |
//|     closed position produces several OUT deals, and counting each  |
//|     one turns a single winner into three wins.                     |
//|   - Net result is PROFIT + SWAP + COMMISSION. Using DEAL_PROFIT    |
//|     alone inflates the win rate on commission-heavy scalping.      |
//|   - History is the database. The ledger is rebuilt from            |
//|     HistorySelect() on init, so a deleted stats file costs         |
//|     nothing and manually closed trades are still counted. At       |
//|     runtime, closes are folded in one position at a time so the    |
//|     cost stays flat instead of growing with account history.       |
//+------------------------------------------------------------------+
#ifndef __CSETUP_LEDGER_MQH__
#define __CSETUP_LEDGER_MQH__

#define SETUP_LEDGER_MAX 16

//+------------------------------------------------------------------+
//| Per-setup accumulated statistics                                  |
//+------------------------------------------------------------------+
struct SetupStat
{
   string name;
   int    wins;
   int    losses;
   double netProfit;
};

//+------------------------------------------------------------------+
class CSetupLedger
{
private:
   SetupStat m_stats[SETUP_LEDGER_MAX];
   int       m_count;
   long      m_magicBase;

   void      Record(const int setupId, const double net);

public:
            CSetupLedger(void) { m_count = 0; m_magicBase = 0; }

   //--- setup registration -----------------------------------------
   void      Init(const long magicBase);
   int       Register(const string name);
   int       Count(void) const { return m_count; }
   string    Name(const int setupId) const;

   //--- magic number encoding --------------------------------------
   long      MagicFor(const int setupId) const;
   int       SetupFromMagic(const long magic) const;

   //--- data -------------------------------------------------------
   void      Reset(void);
   void      RebuildFromHistory(void);
   bool      ProcessClosedPosition(const long positionId, const int setupId,
                                   double &net);

   //--- queries ----------------------------------------------------
   int       Wins(const int setupId)   const;
   int       Losses(const int setupId) const;
   int       Total(const int setupId)  const;
   double    NetProfit(const int setupId) const;
   double    RawWinRate(const int setupId) const;
   double    WilsonLower(const int setupId, const double z = 1.96) const;

   //--- helpers ----------------------------------------------------
   static double BreakevenWinRate(const double rewardRatio)
     { return (rewardRatio <= 0.0) ? 1.0 : 1.0 / (1.0 + rewardRatio); }

   bool      IsTrusted(const int setupId, const double rewardRatio,
                       const double z = 1.96) const;

   string    Report(const double rewardRatio) const;
};

//+------------------------------------------------------------------+
void CSetupLedger::Init(const long magicBase)
  {
   m_magicBase = magicBase;
   m_count     = 0;
   Reset();
  }

//+------------------------------------------------------------------+
//| Register a setup type. Returns its id, or -1 if the table is full.|
//| IMPORTANT: register setups in the SAME ORDER every run. The id is |
//| baked into the magic number of every trade already on record, so  |
//| reordering silently reassigns historical trades.                  |
//+------------------------------------------------------------------+
int CSetupLedger::Register(const string name)
  {
   if(m_count >= SETUP_LEDGER_MAX)
     {
      Print("CSetupLedger: setup table full, cannot register ", name);
      return -1;
     }

   int id = m_count;
   m_stats[id].name      = name;
   m_stats[id].wins      = 0;
   m_stats[id].losses    = 0;
   m_stats[id].netProfit = 0.0;
   m_count++;
   return id;
  }

//+------------------------------------------------------------------+
string CSetupLedger::Name(const int setupId) const
  {
   if(setupId < 0 || setupId >= m_count)
      return "?";
   return m_stats[setupId].name;
  }

//+------------------------------------------------------------------+
long CSetupLedger::MagicFor(const int setupId) const
  {
   return m_magicBase + (long)setupId;
  }

//+------------------------------------------------------------------+
//| Decode a magic number back to a setup id. Returns -1 when the     |
//| magic does not belong to this EA.                                 |
//+------------------------------------------------------------------+
int CSetupLedger::SetupFromMagic(const long magic) const
  {
   long offset = magic - m_magicBase;
   if(offset < 0 || offset >= (long)m_count)
      return -1;
   return (int)offset;
  }

//+------------------------------------------------------------------+
void CSetupLedger::Reset(void)
  {
   for(int i = 0; i < SETUP_LEDGER_MAX; i++)
     {
      m_stats[i].wins      = 0;
      m_stats[i].losses    = 0;
      m_stats[i].netProfit = 0.0;
     }
  }

//+------------------------------------------------------------------+
void CSetupLedger::Record(const int setupId, const double net)
  {
   if(setupId < 0 || setupId >= m_count)
      return;

   if(net > 0.0)
      m_stats[setupId].wins++;
   else
      m_stats[setupId].losses++;

   m_stats[setupId].netProfit += net;
  }

//+------------------------------------------------------------------+
//| Score one closed position and fold it into the ledger.            |
//|                                                                    |
//| Every deal belonging to the position is summed, so a partially     |
//| closed trade collapses back into a single result instead of        |
//| counting as several.                                               |
//|                                                                    |
//| Pass setupId = -1 to recover the setup from the entry deal's       |
//| magic number. Returns false if the position is still open or does  |
//| not belong to this EA.                                             |
//+------------------------------------------------------------------+
bool CSetupLedger::ProcessClosedPosition(const long positionId,
                                         const int setupId,
                                         double &net)
  {
   net = 0.0;
   if(positionId == 0)
      return false;
   if(!HistorySelectByPosition(positionId))
      return false;

   int  sid    = setupId;
   bool closed = false;

   int dealsInPos = HistoryDealsTotal();
   for(int j = 0; j < dealsInPos; j++)
     {
      ulong dd = HistoryDealGetTicket(j);
      if(dd == 0)
         continue;

      net += HistoryDealGetDouble(dd, DEAL_PROFIT)
           + HistoryDealGetDouble(dd, DEAL_SWAP)
           + HistoryDealGetDouble(dd, DEAL_COMMISSION);

      long entry = HistoryDealGetInteger(dd, DEAL_ENTRY);

      if(entry == DEAL_ENTRY_IN && sid < 0)
         sid = SetupFromMagic(HistoryDealGetInteger(dd, DEAL_MAGIC));

      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
         closed = true;
     }

   if(!closed || sid < 0)
      return false;

   Record(sid, net);
   return true;
  }

//+------------------------------------------------------------------+
//| Rebuild the whole ledger from the account's deal history.         |
//|                                                                    |
//| Pass 1 finds every position this EA opened, via the entry deal's  |
//| magic number.                                                      |
//| Pass 2 scores each of them.                                        |
//+------------------------------------------------------------------+
void CSetupLedger::RebuildFromHistory(void)
  {
   Reset();

   if(!HistorySelect(0, TimeCurrent()))
     {
      Print("CSetupLedger: HistorySelect() failed, ledger left empty.");
      return;
     }

   long posIds[];
   int  posSetup[];
   int  n = 0;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;

      // Only the entry deal tells us which setup opened this position.
      if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;

      int sid = SetupFromMagic(HistoryDealGetInteger(d, DEAL_MAGIC));
      if(sid < 0)
         continue;

      long pid = HistoryDealGetInteger(d, DEAL_POSITION_ID);
      if(pid == 0)
         continue;

      ArrayResize(posIds,   n + 1);
      ArrayResize(posSetup, n + 1);
      posIds[n]   = pid;
      posSetup[n] = sid;
      n++;
     }

   for(int k = 0; k < n; k++)
     {
      double net = 0.0;
      ProcessClosedPosition(posIds[k], posSetup[k], net);
     }

   // Leave the global history selection in a sane state for the caller.
   HistorySelect(0, TimeCurrent());
  }

//+------------------------------------------------------------------+
int CSetupLedger::Wins(const int setupId) const
  {
   if(setupId < 0 || setupId >= m_count) return 0;
   return m_stats[setupId].wins;
  }

int CSetupLedger::Losses(const int setupId) const
  {
   if(setupId < 0 || setupId >= m_count) return 0;
   return m_stats[setupId].losses;
  }

int CSetupLedger::Total(const int setupId) const
  {
   return Wins(setupId) + Losses(setupId);
  }

double CSetupLedger::NetProfit(const int setupId) const
  {
   if(setupId < 0 || setupId >= m_count) return 0.0;
   return m_stats[setupId].netProfit;
  }

//+------------------------------------------------------------------+
double CSetupLedger::RawWinRate(const int setupId) const
  {
   int t = Total(setupId);
   if(t <= 0) return 0.0;
   return (double)Wins(setupId) / (double)t;
  }

//+------------------------------------------------------------------+
//| Wilson score interval, lower bound.                               |
//|                                                                    |
//| Three wins out of three is a 100% raw win rate and means nothing.  |
//| The Wilson lower bound answers a better question: what is the      |
//| worst true win rate still consistent with this record at the given |
//| confidence level? Small samples get pushed down hard. Large        |
//| samples barely move.                                               |
//+------------------------------------------------------------------+
double CSetupLedger::WilsonLower(const int setupId, const double z) const
  {
   int total = Total(setupId);
   if(total <= 0)
      return 0.0;

   double p  = (double)Wins(setupId) / (double)total;
   double z2 = z * z;

   double centre = p + z2 / (2.0 * total);
   double margin = z * MathSqrt(p * (1.0 - p) / total + z2 / (4.0 * total * total));
   double denom  = 1.0 + z2 / total;

   double lower = (centre - margin) / denom;
   return (lower < 0.0) ? 0.0 : lower;
  }

//+------------------------------------------------------------------+
//| A setup is trusted when even its pessimistic win rate clears the   |
//| breakeven win rate implied by the reward-to-risk ratio.            |
//+------------------------------------------------------------------+
bool CSetupLedger::IsTrusted(const int setupId, const double rewardRatio,
                             const double z) const
  {
   return WilsonLower(setupId, z) > BreakevenWinRate(rewardRatio);
  }

//+------------------------------------------------------------------+
string CSetupLedger::Report(const double rewardRatio) const
  {
   double breakeven = BreakevenWinRate(rewardRatio);

   string s = StringFormat("Per-setup ledger  (breakeven win rate at 1:%.1f = %.1f%%)\n",
                           rewardRatio, breakeven * 100.0);
   s += "---------------------------------------------------------------------\n";

   for(int i = 0; i < m_count; i++)
     {
      int t = Total(i);
      s += StringFormat("%-18s %3d/%-3d  raw %5.1f%%  wilson %5.1f%%  net %9.2f  %s\n",
                        m_stats[i].name,
                        Wins(i), Losses(i),
                        RawWinRate(i) * 100.0,
                        WilsonLower(i) * 100.0,
                        m_stats[i].netProfit,
                        (t == 0) ? "no data"
                                 : (IsTrusted(i, rewardRatio) ? "trusted" : "not yet trusted"));
     }
   return s;
  }

#endif // __CSETUP_LEDGER_MQH__
