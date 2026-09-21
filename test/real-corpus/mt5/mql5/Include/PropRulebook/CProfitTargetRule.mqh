//+------------------------------------------------------------------+
//|                                            CProfitTargetRule.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Evaluates progress toward the challenge profit      |
//|               target against the TARGET LEVEL itself, and         |
//|               optionally asks for a flatten once that level is    |
//|               reached.                                            |
//| Failure mode: A guard named "Trailing Profit Max" or "Trailing    |
//|               MFE" that computes a drop from the equity peak -- a |
//|               drawdown formula -- and routes the result to the    |
//|               profit action will trigger a "profit reached"       |
//|               response on an account that has only ever lost      |
//|               money. This rule contains no peak, reads no peak,   |
//|               and cannot be fed one: its only comparison is       |
//|                                                                   |
//|                   equity  >=  anchor + target_amount              |
//|                                                                   |
//|               Peak measurement lives in CExcursionTracker, which  |
//|               produces no verdict at all, so the two concepts     |
//|               cannot be crossed again by accident. The flatten    |
//|               this rule asks for is only a REQUEST.               |
//|               CRuleCoordinator downgrades it to an advisory when  |
//|               taking it would push the best-day share past the    |
//|               consistency threshold.                              |
//| Dependencies: IPropRule.mqh                                       |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+
#include "IPropRule.mqh"

//+------------------------------------------------------------------+
//| Profit target.                                                   |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

class CProfitTargetRule : public IPropRule
{
private:
   double m_anchor;         // challenge starting balance
   double m_target_amount;  // account currency above the anchor
   bool   m_flatten;        // ask for a flatten when the target is reached
   bool   m_reached;        // latch: the target was reached at least once

public:
   CProfitTargetRule()
      : IPropRule(PROP_RULE_PROFIT_TARGET),
        m_anchor(0.0), m_target_amount(0.0), m_flatten(false), m_reached(false) {}

   double TargetLevel() const { return m_anchor + m_target_amount; }
   bool   IsReached()   const { return m_reached; }

   virtual bool Configure(const PropFirmProfile &profile, string &err)
   {
      m_configured = false;

      if(!profile.use_profit_target)
      {
         err = "profit target is disabled";
         return false;
      }
      if(profile.profit_target_amount <= 0.0)
      {
         err = "profit_target_amount is enabled but unset (0.0)";
         return false;
      }
      if(profile.initial_balance <= 0.0)
      {
         err = "profit target needs a positive initial_balance anchor";
         return false;
      }

      m_anchor        = profile.initial_balance;
      m_target_amount = profile.profit_target_amount;
      m_flatten       = profile.flatten_on_profit_target;
      m_buffer_ratio  = profile.safety_buffer_ratio;
      m_reached       = false;
      m_configured    = true;
      return true;
   }

   virtual void Evaluate(const PropAccountSnapshot &snap, PropRuleVerdict &out)
   {
      double level    = TargetLevel();
      double progress = snap.equity - m_anchor;      // NOT a drop from any peak
      double headroom = level - snap.equity;         // still to go, in account currency

      if(m_reached || snap.equity >= level)
      {
         bool first = !m_reached;
         m_reached  = true;

         //--- reaching a target is good news; the only debatable part is
         //--- whether to bank it, which is what m_flatten controls and what
         //--- the coordinator may still veto on consistency grounds (P5).
         ENUM_PROP_DIRECTIVE directive = PROP_DIRECTIVE_ADVISORY;
         if(m_flatten && snap.HasExposure())
            directive = PROP_DIRECTIVE_FLATTEN;

         Report(out, snap, PROP_SEV_INFO, directive,
                snap.equity, level, headroom, "ccy",
                StringFormat("%s: equity %.2f reached the target level %.2f "
                             "(anchor %.2f + %.2f)%s",
                             Name(), snap.equity, level, m_anchor, m_target_amount,
                             (first ? "" : " [already reached]")),
                true);
         return;
      }

      Report(out, snap, PROP_SEV_INFO, PROP_DIRECTIVE_NONE,
             snap.equity, level, headroom, "ccy",
             StringFormat("%s: %.2f of %.2f made, %.2f to go",
                          Name(), progress, m_target_amount, headroom));
   }

   virtual void Reset(const PropAccountSnapshot &snap)
   {
      if(snap.initial_balance > 0.0)
         m_anchor = snap.initial_balance;
      m_reached = false;
   }

   //--- a target is a challenge-level fact; a new day changes nothing
   virtual void ResetIntraday(const PropAccountSnapshot &snap)
   {
   }

   virtual string Serialize() const
   {
      return StringFormat("%.2f,%d", m_anchor, (m_reached ? 1 : 0));
   }

   virtual bool Deserialize(const string state)
   {
      string f[];
      if(StringSplit(state, (ushort)',', f) != 2)
         return false;

      double anchor = StringToDouble(f[0]);
      if(anchor <= 0.0)
         return false;

      m_anchor  = anchor;
      m_reached = ((int)StringToInteger(f[1]) == 1);
      return true;
   }
};
//+------------------------------------------------------------------+
