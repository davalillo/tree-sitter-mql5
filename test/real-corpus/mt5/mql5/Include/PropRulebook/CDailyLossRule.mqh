//+------------------------------------------------------------------+
//|                                               CDailyLossRule.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Evaluates the loss accumulated since the configured |
//|               daily reset boundary against the daily loss limit,  |
//|               using the day-opening balance frozen into the       |
//|               snapshot rather than any notion of "today" of its   |
//|               own.                                                |
//| Failure mode: A guard that fires once, sets a latch, and never    |
//|               rearms it leaves daily loss protection disarmed for |
//|               the rest of the session after the first trigger.    |
//|               Here ResetIntraday() is the rearm, it is a separate |
//|               contract method from Reset(), and the coordinator   |
//|               drives it across the whole table at the prop-day    |
//|               boundary CPropSessionClock reports. The boundary is |
//|               the firm's configured reset hour, not server        |
//|               midnight; this rule never computes a date itself.   |
//|               The loss is measured against the day's OPENING      |
//|               BALANCE using current EQUITY, so open floating loss |
//|               counts, which is how the firms measure it.          |
//| Dependencies: IPropRule.mqh                                       |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+
#include "IPropRule.mqh"

//+------------------------------------------------------------------+
//| Daily loss limit.                                                |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

class CDailyLossRule : public IPropRule
{
private:
   double m_limit;         // account currency allowed to be lost in one prop day
   bool   m_latched;       // INTRADAY latch: rearmed by ResetIntraday(), not by Reset() alone
   int    m_latched_day;   // prop day the latch was set on, for the journal
   int    m_rearm_count;   // how many times the rule rearmed, proof that C5 is fixed

public:
   CDailyLossRule()
      : IPropRule(PROP_RULE_DAILY_LOSS),
        m_limit(0.0), m_latched(false), m_latched_day(0), m_rearm_count(0) {}

   double Limit()       const { return m_limit; }
   bool   IsLatched()   const { return m_latched; }
   int    RearmCount()  const { return m_rearm_count; }

   virtual bool Configure(const PropFirmProfile &profile, string &err)
   {
      m_configured = false;

      if(!profile.use_daily_loss)
      {
         err = "daily loss limit is disabled";
         return false;
      }
      if(profile.daily_loss_amount <= 0.0)
      {
         err = "daily_loss_amount is enabled but unset (0.0)";
         return false;
      }

      m_limit        = profile.daily_loss_amount;
      m_buffer_ratio = profile.safety_buffer_ratio;
      m_latched      = false;
      m_latched_day  = 0;
      m_configured   = true;
      return true;
   }

   virtual void Evaluate(const PropAccountSnapshot &snap, PropRuleVerdict &out)
   {
      double loss     = snap.DayLoss();          // day_start_balance - equity
      double headroom = m_limit - MathMax(0.0, loss);

      if(m_latched || loss >= m_limit)
      {
         bool first = !m_latched;
         if(first)
         {
            m_latched     = true;
            m_latched_day = snap.prop_day_index;
         }

         //--- while exposure is open the correct action is to close it; once
         //--- flat, the correct action is simply to stay out for the rest of
         //--- the prop day. Escalating to LOCKDOWN would be wrong: a daily
         //--- breach does not end the challenge, it ends the day.
         ENUM_PROP_DIRECTIVE directive = snap.HasExposure()
                                         ? PROP_DIRECTIVE_FLATTEN
                                         : PROP_DIRECTIVE_BLOCK_NEW_ENTRIES;

         Report(out, snap, PROP_SEV_BREACH, directive,
                loss, m_limit, headroom, "ccy",
                StringFormat("%s: %.2f lost since the %s boundary, limit %.2f%s",
                             Name(), loss, TimeToString(snap.prop_day_start, TIME_DATE | TIME_MINUTES),
                             m_limit, (first ? "" : " [latched for this prop day]")),
                true);
         return;
      }

      ENUM_PROP_SEVERITY severity = BufferSeverity(MathMax(0.0, loss), m_limit);

      Report(out, snap, severity, PROP_DIRECTIVE_NONE,
             loss, m_limit, headroom, "ccy",
             StringFormat("%s: day P/L %.2f, %.2f left before the %.2f limit",
                          Name(), -loss, headroom, m_limit));
   }

   //--- a fresh challenge clears everything this rule holds
   virtual void Reset(const PropAccountSnapshot &snap)
   {
      m_latched     = false;
      m_latched_day = 0;
   }

   //+---------------------------------------------------------------+
   //| C5, the fix itself. A new prop day rearms the daily protection |
   //| and NOTHING else -- it does not touch the account-level rules, |
   //| because it is their ResetIntraday() that decides that, not     |
   //| this one.                                                      |
   //+---------------------------------------------------------------+
   virtual void ResetIntraday(const PropAccountSnapshot &snap)
   {
      if(m_latched)
      {
         m_rearm_count++;
         PrintFormat("%s: rearmed at the %s prop-day boundary (breach was on day index %d)",
                     Name(), TimeToString(snap.prop_day_start, TIME_DATE | TIME_MINUTES),
                     m_latched_day);
      }
      m_latched     = false;
      m_latched_day = 0;
   }

   virtual string Serialize() const
   {
      return StringFormat("%d,%d,%d", (m_latched ? 1 : 0), m_latched_day, m_rearm_count);
   }

   virtual bool Deserialize(const string state)
   {
      string f[];
      if(StringSplit(state, (ushort)',', f) != 3)
         return false;
      m_latched     = ((int)StringToInteger(f[0]) == 1);
      m_latched_day = (int)StringToInteger(f[1]);
      m_rearm_count = (int)StringToInteger(f[2]);
      return true;
   }
};
//+------------------------------------------------------------------+
