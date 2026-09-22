//+------------------------------------------------------------------+
//|                                              CNewsWindowRule.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Evaluates whether the current moment falls inside   |
//|               the blackout window around a high-impact economic   |
//|               event -- typically 5 minutes before and 5 minutes   |
//|               after -- and whether any open position is exposed   |
//|               to that window without qualifying for the           |
//|               "opened well in advance" exemption most firms grant |
//|               (commonly positions opened 5 or more hours before   |
//|               the release).                                       |
//| Failure mode: News-window blackout: a rule family hand-rolled     |
//|               guards typically omit entirely.                     |
//|                                                                   |
//|               The rule is a pure function of the snapshot's       |
//|               minutes-to-event and minutes-since-event fields; it |
//|               never touches the calendar API itself, which is     |
//|               what makes it testable with synthetic events. When  |
//|               the feed reports itself unavailable (Strategy       |
//|               Tester, no calendar connection) the rule ABSTAINS.  |
//|               Abstaining is the only defensible behaviour: a      |
//|               guard that blocked every entry whenever it could    |
//|               not see the calendar would disable the trading      |
//|               system it is supposed to protect, and one that      |
//|               silently passed would give false assurance.         |
//| Dependencies: IPropRule.mqh                                       |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+
#include "IPropRule.mqh"

//+------------------------------------------------------------------+
//| High-impact news blackout window.                                |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

class CNewsWindowRule : public IPropRule
{
private:
   int m_minutes_before;
   int m_minutes_after;
   int m_exempt_hours;    // a position older than this, relative to the event, is exempt

   bool InsideWindow(const PropAccountSnapshot &snap) const
   {
      if(snap.has_next_event &&
         snap.minutes_to_next_event >= 0 &&
         snap.minutes_to_next_event <= m_minutes_before)
         return true;

      if(snap.has_last_event &&
         snap.minutes_since_last_event >= 0 &&
         snap.minutes_since_last_event <= m_minutes_after)
         return true;

      return false;
   }

   //--- event time the current window belongs to
   datetime WindowEvent(const PropAccountSnapshot &snap) const
   {
      if(snap.has_next_event &&
         snap.minutes_to_next_event >= 0 &&
         snap.minutes_to_next_event <= m_minutes_before)
         return snap.next_event_time;
      return snap.last_event_time;
   }

   string WindowEventName(const PropAccountSnapshot &snap) const
   {
      if(snap.has_next_event &&
         snap.minutes_to_next_event >= 0 &&
         snap.minutes_to_next_event <= m_minutes_before)
         return snap.next_event_name;
      return snap.last_event_name;
   }

public:
   CNewsWindowRule()
      : IPropRule(PROP_RULE_NEWS_WINDOW),
        m_minutes_before(0), m_minutes_after(0), m_exempt_hours(0) {}

   int MinutesBefore() const { return m_minutes_before; }
   int MinutesAfter()  const { return m_minutes_after; }
   int ExemptHours()   const { return m_exempt_hours; }

   //+---------------------------------------------------------------+
   //| A position is exempt when it was opened at least exempt_hours  |
   //| before the event. Public so a consuming EA can answer the same |
   //| question about a single ticket before deciding to hold it.     |
   //+---------------------------------------------------------------+
   bool IsPositionExempt(const datetime opened, const datetime event_time) const
   {
      if(m_exempt_hours <= 0)
         return false;
      if(opened == 0 || event_time == 0)
         return false;
      return ((long)event_time - (long)opened) >= (long)m_exempt_hours * 3600;
   }

   virtual bool Configure(const PropFirmProfile &profile, string &err)
   {
      m_configured = false;

      if(!profile.use_news_window)
      {
         err = "news window is disabled";
         return false;
      }
      if(profile.news_block_minutes_before <= 0 && profile.news_block_minutes_after <= 0)
      {
         err = "news window is enabled but both blackout sides are 0";
         return false;
      }

      m_minutes_before = profile.news_block_minutes_before;
      m_minutes_after  = profile.news_block_minutes_after;
      m_exempt_hours   = profile.news_exempt_hours;
      m_buffer_ratio   = profile.safety_buffer_ratio;
      m_configured     = true;
      return true;
   }

   virtual void Evaluate(const PropAccountSnapshot &snap, PropRuleVerdict &out)
   {
      //--- no calendar, no opinion
      if(!snap.news_available)
      {
         Abstain(out, snap,
                 StringFormat("%s: economic calendar unavailable on this terminal -- "
                              "abstaining instead of blocking", Name()));
         out.unit = "minutes";
         m_last   = out;
         return;
      }

      if(!InsideWindow(snap))
      {
         double minutes_left = (snap.has_next_event && snap.minutes_to_next_event >= 0)
                               ? (double)(snap.minutes_to_next_event - m_minutes_before)
                               : 0.0;

         string text = snap.has_next_event
                       ? StringFormat("%s: clear, next high-impact event '%s' in %d min",
                                      Name(), snap.next_event_name, snap.minutes_to_next_event)
                       : StringFormat("%s: clear, no high-impact event in the feed window", Name());

         ENUM_PROP_SEVERITY severity = PROP_SEV_OK;
         if(snap.has_next_event && minutes_left >= 0.0 && minutes_left <= 15.0)
            severity = PROP_SEV_WARNING;

         Report(out, snap, severity, PROP_DIRECTIVE_NONE,
                (double)snap.minutes_to_next_event, (double)m_minutes_before,
                minutes_left, "minutes", text);
         return;
      }

      //--- inside the blackout window
      datetime event_time = WindowEvent(snap);
      string   event_name = WindowEventName(snap);

      bool has_non_exempt = snap.HasExposure() &&
                            !IsPositionExempt(snap.newest_position_time, event_time);

      if(has_non_exempt)
      {
         //--- holding through the release with a recently opened position is
         //--- the violation itself, so the exposure has to go
         Report(out, snap, PROP_SEV_BREACH, PROP_DIRECTIVE_FLATTEN,
                0.0, (double)m_minutes_before, 0.0, "minutes",
                StringFormat("%s: inside the blackout window of '%s' (%s) with %d open "
                             "position(s), newest opened %s -- not exempt (%d h rule)",
                             Name(), event_name,
                             TimeToString(event_time, TIME_DATE | TIME_MINUTES),
                             snap.positions_total,
                             TimeToString(snap.newest_position_time, TIME_DATE | TIME_MINUTES),
                             m_exempt_hours));
         return;
      }

      Report(out, snap, PROP_SEV_WARNING, PROP_DIRECTIVE_BLOCK_NEW_ENTRIES,
             0.0, (double)m_minutes_before, 0.0, "minutes",
             StringFormat("%s: inside the blackout window of '%s' (%s), new entries "
                          "blocked; %d open position(s) exempt under the %d h rule",
                          Name(), event_name,
                          TimeToString(event_time, TIME_DATE | TIME_MINUTES),
                          snap.positions_total, m_exempt_hours));
   }

   //--- stateless: the window is derived from the snapshot every pass
   virtual void Reset(const PropAccountSnapshot &snap)         {}
   virtual void ResetIntraday(const PropAccountSnapshot &snap) {}

   virtual string Serialize() const               { return "0"; }
   virtual bool   Deserialize(const string state) { return (state == "0"); }
};
//+------------------------------------------------------------------+
