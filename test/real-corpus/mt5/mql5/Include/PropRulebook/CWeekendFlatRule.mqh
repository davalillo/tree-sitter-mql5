//+------------------------------------------------------------------+
//|                                             CWeekendFlatRule.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Evaluates whether the pre-weekend flat cutoff has   |
//|               been reached while exposure is still open, and asks |
//|               for a flatten only in that case.                    |
//| Failure mode: Weekend flat cutoff: a rule family hand-rolled      |
//|               guards typically omit entirely.                     |
//|                                                                   |
//|               Most firms require forex and index exposure to be   |
//|               flat before the weekend, and the reason matters as  |
//|               much as the rule: a Monday gap can consume the      |
//|               whole daily loss allowance before a single tick is  |
//|               tradeable, so a position carried over the weekend   |
//|               can fail a challenge while the terminal is closed.  |
//|                                                                   |
//|               The cutoff boundary itself comes from              |
//|               CPropSessionClock (server clock, since a broker's   |
//|               Friday close is a server-time event) and arrives    |
//|               pre-computed in the snapshot, so this rule stays a  |
//|               pure comparison. With no exposure open it produces  |
//|               a block on new entries and nothing else -- there is |
//|               nothing to flatten and the account is already       |
//|               compliant.                                          |
//| Dependencies: IPropRule.mqh                                       |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+
#include "IPropRule.mqh"

//+------------------------------------------------------------------+
//| Pre-weekend flat enforcement.                                    |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

class CWeekendFlatRule : public IPropRule
{
private:
   int  m_cutoff_dow;
   int  m_cutoff_hour;
   int  m_cutoff_minute;
   bool m_flatten_asked;   // this weekend's flatten was already requested

public:
   CWeekendFlatRule()
      : IPropRule(PROP_RULE_WEEKEND_FLAT),
        m_cutoff_dow(5), m_cutoff_hour(PROP_UNSET_HOUR), m_cutoff_minute(0),
        m_flatten_asked(false) {}

   string CutoffText() const
   {
      return StringFormat("dow %d %02d:%02d server", m_cutoff_dow, m_cutoff_hour, m_cutoff_minute);
   }

   virtual bool Configure(const PropFirmProfile &profile, string &err)
   {
      m_configured = false;

      if(!profile.use_weekend_flat)
      {
         err = "weekend flat rule is disabled";
         return false;
      }
      //--- PROP_UNSET_HOUR is the sentinel that separates "cutoff at
      //--- midnight" from "cutoff never configured" -- without it a zero
      //--- default would silently mean 00:00 and flatten every Sunday (C1)
      if(profile.weekend_cutoff_hour == PROP_UNSET_HOUR)
      {
         err = "weekend flat is enabled but weekend_cutoff_hour is unset";
         return false;
      }
      if(profile.weekend_cutoff_hour < 0 || profile.weekend_cutoff_hour > 23 ||
         profile.weekend_cutoff_minute < 0 || profile.weekend_cutoff_minute > 59 ||
         profile.weekend_cutoff_dow < 0 || profile.weekend_cutoff_dow > 6)
      {
         err = "weekend cutoff day/hour/minute out of range";
         return false;
      }

      m_cutoff_dow    = profile.weekend_cutoff_dow;
      m_cutoff_hour   = profile.weekend_cutoff_hour;
      m_cutoff_minute = profile.weekend_cutoff_minute;
      m_buffer_ratio  = profile.safety_buffer_ratio;
      m_flatten_asked = false;
      m_configured    = true;
      return true;
   }

   virtual void Evaluate(const PropAccountSnapshot &snap, PropRuleVerdict &out)
   {
      double minutes_left = (double)snap.minutes_to_weekend_cutoff;

      if(!snap.past_weekend_cutoff)
      {
         ENUM_PROP_SEVERITY severity = PROP_SEV_OK;
         if(minutes_left >= 0.0 && minutes_left <= 30.0 && snap.HasExposure())
            severity = PROP_SEV_WARNING;

         Report(out, snap, severity, PROP_DIRECTIVE_NONE,
                minutes_left, 0.0, minutes_left, "minutes",
                StringFormat("%s: %.0f min to the %s cutoff, %d position(s) open",
                             Name(), minutes_left, CutoffText(), snap.positions_total));
         return;
      }

      if(snap.HasExposure())
      {
         m_flatten_asked = true;
         Report(out, snap, PROP_SEV_BREACH, PROP_DIRECTIVE_FLATTEN,
                minutes_left, 0.0, 0.0, "minutes",
                StringFormat("%s: past the %s cutoff with %d position(s) and %.2f lots open "
                             "-- weekend gap risk",
                             Name(), CutoffText(), snap.positions_total, snap.open_volume),
                true);
         return;
      }

      //--- already flat: stay out until the cutoff window ends
      Report(out, snap, PROP_SEV_OK, PROP_DIRECTIVE_BLOCK_NEW_ENTRIES,
             minutes_left, 0.0, 0.0, "minutes",
             StringFormat("%s: past the %s cutoff and flat, new entries blocked",
                          Name(), CutoffText()));
   }

   virtual void Reset(const PropAccountSnapshot &snap)
   {
      m_flatten_asked = false;
   }

   //+---------------------------------------------------------------+
   //| The weekend flag is a per-day fact, so the prop-day rollover   |
   //| is exactly the right place to clear it -- and the only one.    |
   //+---------------------------------------------------------------+
   virtual void ResetIntraday(const PropAccountSnapshot &snap)
   {
      m_flatten_asked = false;
   }

   virtual string Serialize() const
   {
      return StringFormat("%d", (m_flatten_asked ? 1 : 0));
   }

   virtual bool Deserialize(const string state)
   {
      if(state != "0" && state != "1")
         return false;
      m_flatten_asked = (state == "1");
      return true;
   }
};
//+------------------------------------------------------------------+
