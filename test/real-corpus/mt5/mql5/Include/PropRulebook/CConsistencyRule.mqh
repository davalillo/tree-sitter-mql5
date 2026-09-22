//+------------------------------------------------------------------+
//|                                             CConsistencyRule.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Evaluates the best single prop day's profit as a    |
//|               share of total profit against the firm's payout     |
//|               consistency threshold (~30% is the most common      |
//|               figure; the observed range across firms is roughly  |
//|               20-45%), and publishes the PROJECTED share that     |
//|               would result if the currently open profit were      |
//|               realized right now.                                 |
//| Failure mode: Payout consistency: a rule family hand-rolled       |
//|               guards typically omit entirely. And worse than      |
//|               absent: a naive Close_Positions_On_Profit=true      |
//|               behaviour actively manufactures the violation this  |
//|               rule detects, by banking one disproportionate day.  |
//|               Two things fix that. First, this rule NEVER emits a |
//|               lockdown or a flatten: breaking a consistency rule  |
//|               blocks a payout, it does not kill the account, so   |
//|               the strongest thing it may ask for is               |
//|               PROP_DIRECTIVE_ADVISORY. Second, it fills           |
//|               verdict.projected with the post-flatten share, and  |
//|               CRuleCoordinator reads that field to downgrade a    |
//|               profit-target flatten that would create the         |
//|               violation.                                          |
//| Dependencies: IPropRule.mqh                                       |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+
#include "IPropRule.mqh"

//+------------------------------------------------------------------+
//| Payout consistency (advisory severity only, by construction).    |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

class CConsistencyRule : public IPropRule
{
private:
   double m_max_share;   // 0..1 ceiling for best_day / total_profit

public:
   CConsistencyRule()
      : IPropRule(PROP_RULE_CONSISTENCY), m_max_share(0.0) {}

   double MaxShare() const { return m_max_share; }

   //+---------------------------------------------------------------+
   //| Would banking 'extra' profit today break the threshold?        |
   //| Pure function of the snapshot, kept here so the arithmetic     |
   //| lives with the rule that owns the threshold. The coordinator   |
   //| normally uses verdict.projected instead of calling this, so it |
   //| never has to know this concrete type.                          |
   //+---------------------------------------------------------------+
   bool WouldViolate(const double projected_share) const
   {
      if(!m_configured || m_max_share <= 0.0)
         return false;
      return (projected_share > m_max_share);
   }

   virtual bool Configure(const PropFirmProfile &profile, string &err)
   {
      m_configured = false;

      if(!profile.use_consistency)
      {
         err = "consistency rule is disabled";
         return false;
      }
      if(profile.consistency_max_share <= 0.0 || profile.consistency_max_share >= 1.0)
      {
         err = "consistency_max_share is enabled but is not a share in (0,1)";
         return false;
      }

      m_max_share    = profile.consistency_max_share;
      m_buffer_ratio = profile.safety_buffer_ratio;
      m_configured   = true;
      return true;
   }

   virtual void Evaluate(const PropAccountSnapshot &snap, PropRuleVerdict &out)
   {
      //--- with no positive total profit there is no share to judge. This is
      //--- an abstain, not a pass: reporting "0% is fine" would be a lie the
      //--- moment the first profitable day lands.
      if(snap.total_realized_profit <= 0.0)
      {
         Abstain(out, snap,
                 StringFormat("%s: no positive realized profit yet (total %.2f), "
                              "consistency share is undefined",
                              Name(), snap.total_realized_profit));
         out.threshold = m_max_share;
         out.unit      = "share";
         out.projected = snap.projected_best_day_share;
         m_last        = out;
         return;
      }

      double share    = snap.best_day_share;
      double headroom = m_max_share - share;

      ENUM_PROP_SEVERITY  severity  = PROP_SEV_OK;
      ENUM_PROP_DIRECTIVE directive = PROP_DIRECTIVE_NONE;
      string              text;

      if(share > m_max_share)
      {
         //--- ADVISORY, never BREACH-with-lockdown: the account is healthy,
         //--- the payout is not.
         severity  = PROP_SEV_ADVISORY;
         directive = PROP_DIRECTIVE_ADVISORY;
         text = StringFormat("%s: best day %.2f is %.1f%% of the %.2f total profit, "
                             "above the %.1f%% payout ceiling -- trade more days to "
                             "rebalance before requesting a payout",
                             Name(), snap.best_day_profit, share * 100.0,
                             snap.total_realized_profit, m_max_share * 100.0);
      }
      else
      {
         if(share >= m_max_share * m_buffer_ratio)
            severity = PROP_SEV_WARNING;
         text = StringFormat("%s: best day %.2f is %.1f%% of %.2f total, ceiling %.1f%%",
                             Name(), snap.best_day_profit, share * 100.0,
                             snap.total_realized_profit, m_max_share * 100.0);
      }

      Report(out, snap, severity, directive,
             share, m_max_share, headroom, "share", text);

      //--- P5 hand-off: what the share becomes if today's floating profit is
      //--- banked now. The coordinator vetoes a profit-target flatten on it.
      out.projected = snap.projected_best_day_share;
      m_last        = out;
   }

   //--- the rule holds no state of its own: the ledger holds the history,
   //--- and neither a new challenge nor a new day changes the threshold
   virtual void Reset(const PropAccountSnapshot &snap)         {}
   virtual void ResetIntraday(const PropAccountSnapshot &snap) {}

   virtual string Serialize() const              { return "0"; }
   virtual bool   Deserialize(const string state) { return (state == "0"); }
};
//+------------------------------------------------------------------+
