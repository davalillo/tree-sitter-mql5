//+------------------------------------------------------------------+
//|                                          CMinTradingDaysRule.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Evaluates how many prop-firm calendar days carry a  |
//|               trade of at least the qualifying size against the   |
//|               minimum-trading-days requirement (3, 5 and 10 days  |
//|               are the common figures; a day normally counts only  |
//|               if it carried a trade of at least 0.01 lots).       |
//| Failure mode: Minimum trading days: a rule family hand-rolled     |
//|               guards typically omit entirely.                     |
//|                                                                   |
//|               This rule is the one place in the package where the |
//|               guard's answer is "you have not traded ENOUGH". It  |
//|               therefore never asks for a protective action of any |
//|               kind: it reports an advisory severity while the     |
//|               requirement is unmet and OK once it is met, and     |
//|               CPropRulebook::IsPayoutEligible() reads that.      |
//|               Emitting a directive here would be actively harmful |
//|               -- blocking entries is the exact opposite of what   |
//|               an account short of trading days needs.             |
//| Dependencies: IPropRule.mqh                                       |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+
#include "IPropRule.mqh"

//+------------------------------------------------------------------+
//| Minimum qualifying trading days.                                 |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

class CMinTradingDaysRule : public IPropRule
{
private:
   int    m_required_days;
   double m_min_volume;     // reported for the journal; the ledger applies it

public:
   CMinTradingDaysRule()
      : IPropRule(PROP_RULE_MIN_TRADING_DAYS),
        m_required_days(0), m_min_volume(0.0) {}

   int    RequiredDays() const { return m_required_days; }
   double MinVolume()    const { return m_min_volume; }

   virtual bool Configure(const PropFirmProfile &profile, string &err)
   {
      m_configured = false;

      if(!profile.use_min_trading_days)
      {
         err = "minimum trading days is disabled";
         return false;
      }
      if(profile.min_trading_days <= 0)
      {
         err = "min_trading_days is enabled but unset (0)";
         return false;
      }
      if(profile.min_qualifying_volume <= 0.0)
      {
         err = "min_qualifying_volume is enabled but unset (0.0)";
         return false;
      }

      m_required_days = profile.min_trading_days;
      m_min_volume    = profile.min_qualifying_volume;
      m_buffer_ratio  = profile.safety_buffer_ratio;
      m_configured    = true;
      return true;
   }

   virtual void Evaluate(const PropAccountSnapshot &snap, PropRuleVerdict &out)
   {
      int    done     = snap.qualifying_days;
      double headroom = (double)(m_required_days - done);   // days still needed

      if(done >= m_required_days)
      {
         Report(out, snap, PROP_SEV_OK, PROP_DIRECTIVE_NONE,
                (double)done, (double)m_required_days, 0.0, "days",
                StringFormat("%s: %d of %d qualifying days done (min %.2f lots per day)",
                             Name(), done, m_required_days, m_min_volume));
         return;
      }

      //--- ADVISORY, and PROP_DIRECTIVE_NONE on purpose: this is a payout
      //--- precondition, not a risk condition. Nothing must be closed and
      //--- nothing must be blocked because of it.
      Report(out, snap, PROP_SEV_ADVISORY, PROP_DIRECTIVE_NONE,
             (double)done, (double)m_required_days, headroom, "days",
             StringFormat("%s: %d of %d qualifying days done, %d still needed "
                          "(a day counts only with a trade of %.2f lots or more)",
                          Name(), done, m_required_days, m_required_days - done, m_min_volume));
   }

   //--- the day history lives in CDailyProfitLedger, so this rule keeps no
   //--- state that a reset could invalidate
   virtual void Reset(const PropAccountSnapshot &snap)         {}
   virtual void ResetIntraday(const PropAccountSnapshot &snap) {}

   virtual string Serialize() const               { return "0"; }
   virtual bool   Deserialize(const string state) { return (state == "0"); }
};
//+------------------------------------------------------------------+
