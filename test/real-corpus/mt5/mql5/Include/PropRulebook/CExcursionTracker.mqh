//+------------------------------------------------------------------+
//|                                            CExcursionTracker.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Measures maximum favourable and maximum adverse     |
//|               excursion of balance and equity against the         |
//|               challenge anchor, and tracks the running peaks and  |
//|               troughs those figures come from.                    |
//| Failure mode: A guard named "Trailing Profit Max" or "Trailing    |
//|               MFE" that computes a drop-from-peak -- which is a   |
//|               drawdown formula -- and then routes the result to a |
//|               profit action will fire a profit protection on a    |
//|               pure loss. The fix here is structural rather than   |
//|               arithmetic: this class measures and NOTHING else.   |
//|               It has no threshold, no enable flag, no verdict, no |
//|               directive, and it does not derive from IPropRule,   |
//|               so there is no code path through which a peak drop  |
//|               can be labelled profit. Profit is judged by         |
//|               CProfitTargetRule against the target level;         |
//|               drawdown is judged by the drawdown rules against    |
//|               their floors. Neither of them reads this class.     |
//| Dependencies: none                                                |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Excursion measurement. Read by CPropSnapshotBuilder for reporting |
//| only; every figure it publishes is diagnostic.                    |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

class CExcursionTracker
{
private:
   double m_anchor;         // challenge anchor both excursions are measured from
   double m_peak_balance;
   double m_peak_equity;
   double m_trough_balance;
   double m_trough_equity;
   bool   m_seeded;

public:
   CExcursionTracker()
      : m_anchor(0.0), m_peak_balance(0.0), m_peak_equity(0.0),
        m_trough_balance(0.0), m_trough_equity(0.0), m_seeded(false) {}

   //+---------------------------------------------------------------+
   //| anchor is the challenge starting balance. Excursions are       |
   //| relative to it, so the numbers stay meaningful across a        |
   //| terminal restart.                                              |
   //+---------------------------------------------------------------+
   bool Init(const double anchor)
   {
      if(anchor <= 0.0)
      {
         Print("CExcursionTracker::Init failed: anchor must be positive");
         return false;
      }
      m_anchor         = anchor;
      m_peak_balance   = anchor;
      m_peak_equity    = anchor;
      m_trough_balance = anchor;
      m_trough_equity  = anchor;
      m_seeded         = true;
      return true;
   }

   bool IsReady() const { return m_seeded; }

   //--- called once per pass by the snapshot builder, with the same
   //--- balance/equity pair every rule of that pass will read
   void Update(const double balance, const double equity)
   {
      if(!m_seeded)
         return;

      if(balance > m_peak_balance)   m_peak_balance   = balance;
      if(balance < m_trough_balance) m_trough_balance = balance;
      if(equity  > m_peak_equity)    m_peak_equity    = equity;
      if(equity  < m_trough_equity)  m_trough_equity  = equity;
   }

   double Anchor()        const { return m_anchor; }
   double PeakBalance()   const { return m_peak_balance; }
   double PeakEquity()    const { return m_peak_equity; }
   double TroughBalance() const { return m_trough_balance; }
   double TroughEquity()  const { return m_trough_equity; }

   //--- MFE: the best the account ever was, above the anchor. Never negative.
   double MfeBalance() const { return MathMax(0.0, m_peak_balance - m_anchor); }
   double MfeEquity()  const { return MathMax(0.0, m_peak_equity  - m_anchor); }

   //--- MAE: the worst the account ever was, below the anchor, reported
   //--- as a positive magnitude. Never negative.
   double MaeBalance() const { return MathMax(0.0, m_anchor - m_trough_balance); }
   double MaeEquity()  const { return MathMax(0.0, m_anchor - m_trough_equity); }

   //--- full reset, driven only by CPropRulebook::ResetChallenge()
   void ResetAll(const double anchor)
   {
      if(anchor > 0.0)
         Init(anchor);
   }

   //--- persistence (C9)
   string Serialize() const
   {
      return StringFormat("%.2f,%.2f,%.2f,%.2f,%.2f,%d",
                          m_anchor, m_peak_balance, m_peak_equity,
                          m_trough_balance, m_trough_equity, (m_seeded ? 1 : 0));
   }

   bool Deserialize(const string state)
   {
      string f[];
      if(StringSplit(state, (ushort)',', f) != 6)
         return false;

      double anchor = StringToDouble(f[0]);
      if(anchor <= 0.0)
         return false;

      m_anchor         = anchor;
      m_peak_balance   = StringToDouble(f[1]);
      m_peak_equity    = StringToDouble(f[2]);
      m_trough_balance = StringToDouble(f[3]);
      m_trough_equity  = StringToDouble(f[4]);
      m_seeded         = ((int)StringToInteger(f[5]) == 1);
      return true;
   }
};
//+------------------------------------------------------------------+
