//+------------------------------------------------------------------+
//|                                          CStaticDrawdownRule.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Evaluates equity against a floor anchored           |
//|               permanently to the initial balance captured at      |
//|               challenge start (the classic "maximum overall       |
//|               loss": 10% of the starting balance, a level that    |
//|               never moves for the life of the account).           |
//| Failure mode: A floor named "total max drawdown" that recomputes  |
//|               its reference from the CURRENT balance every time   |
//|               it fires walks downward with the account, so the    |
//|               same amount of money can be lost again and again    |
//|               without the protection ever ending the challenge.   |
//|               Here the anchor is captured once, at Configure() or |
//|               Reset(), and this class exposes no operation that   |
//|               can lower it. ResetIntraday() is deliberately a no- |
//|               op: a new prop day is not a new challenge. The      |
//|               anchor and the breach latch serialize, so a VPS     |
//|               restart cannot re-anchor at the depleted balance.   |
//| Dependencies: IPropRule.mqh                                       |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+
#include "IPropRule.mqh"

//+------------------------------------------------------------------+
//| Static maximum drawdown.                                         |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

class CStaticDrawdownRule : public IPropRule
{
private:
   double m_anchor;        // challenge starting balance, immutable outside Reset()
   double m_dd_amount;     // account currency allowed below the anchor
   bool   m_latched;       // account-level breach latch: only Reset() clears it

public:
   CStaticDrawdownRule()
      : IPropRule(PROP_RULE_STATIC_DD),
        m_anchor(0.0), m_dd_amount(0.0), m_latched(false) {}

   //--- the floor, in account currency. Constant for the whole challenge.
   double Floor() const { return m_anchor - m_dd_amount; }
   double Anchor() const { return m_anchor; }
   bool   IsLatched() const { return m_latched; }

   virtual bool Configure(const PropFirmProfile &profile, string &err)
   {
      m_configured = false;

      if(!profile.use_static_dd)
      {
         err = "static drawdown is disabled";
         return false;
      }
      if(profile.static_dd_amount <= 0.0)
      {
         err = "static_dd_amount is enabled but unset (0.0)";
         return false;
      }
      if(profile.initial_balance <= 0.0)
      {
         err = "static drawdown needs a positive initial_balance anchor";
         return false;
      }

      m_anchor       = profile.initial_balance;
      m_dd_amount    = profile.static_dd_amount;
      m_buffer_ratio = profile.safety_buffer_ratio;
      m_latched      = false;
      m_configured   = true;
      return true;
   }

   virtual void Evaluate(const PropAccountSnapshot &snap, PropRuleVerdict &out)
   {
      double floor_level = Floor();
      double headroom    = snap.equity - floor_level;
      double consumed    = m_anchor - snap.equity;

      //--- once breached, the account is dead for this challenge. The rule
      //--- keeps saying so on every later pass instead of forgetting, and
      //--- keeps the SAME anchor, so a recovery does not buy a second life.
      if(m_latched || snap.equity <= floor_level)
      {
         bool first = !m_latched;
         m_latched  = true;

         Report(out, snap, PROP_SEV_BREACH, PROP_DIRECTIVE_LOCKDOWN,
                snap.equity, floor_level, headroom, "ccy",
                StringFormat("%s: equity %.2f at or below the static floor %.2f "
                             "(anchor %.2f - %.2f)%s",
                             Name(), snap.equity, floor_level, m_anchor, m_dd_amount,
                             (first ? "" : " [latched]")),
                true);
         return;
      }

      ENUM_PROP_SEVERITY severity = BufferSeverity(consumed, m_dd_amount);

      Report(out, snap, severity, PROP_DIRECTIVE_NONE,
             snap.equity, floor_level, headroom, "ccy",
             StringFormat("%s: %.2f of %.2f consumed, %.2f left to the floor %.2f",
                          Name(), MathMax(0.0, consumed), m_dd_amount, headroom, floor_level));
   }

   //+---------------------------------------------------------------+
   //| C4. The only way the anchor moves, and the only way the latch  |
   //| clears. Reached from CPropRulebook::ResetChallenge() and   |
   //| the restore-rollback branch inside Init() -- never from a      |
   //| routine trigger.                                                |
   //+---------------------------------------------------------------+
   virtual void Reset(const PropAccountSnapshot &snap)
   {
      if(snap.initial_balance > 0.0)
         m_anchor = snap.initial_balance;
      m_latched = false;
   }

   //+---------------------------------------------------------------+
   //| C4/C5. A prop-day rollover must not touch an account-level     |
   //| rule. Intentionally empty, and intentionally NOT inherited     |
   //| from a shared "reset everything" routine.                      |
   //+---------------------------------------------------------------+
   virtual void ResetIntraday(const PropAccountSnapshot &snap)
   {
      //--- nothing: the static floor does not know what a day is
   }

   virtual string Serialize() const
   {
      return StringFormat("%.2f,%.2f,%d", m_anchor, m_dd_amount, (m_latched ? 1 : 0));
   }

   virtual bool Deserialize(const string state)
   {
      string f[];
      if(StringSplit(state, (ushort)',', f) != 3)
         return false;

      double anchor = StringToDouble(f[0]);
      if(anchor <= 0.0)
         return false;

      //--- state is restored; the THRESHOLD is not. f[1] is kept in the file
      //--- for auditing only: if the trader edited the input between runs,
      //--- the current profile must win, never a stale file value.
      m_anchor  = anchor;
      m_latched = ((int)StringToInteger(f[2]) == 1);
      return true;
   }
};
//+------------------------------------------------------------------+
