//+------------------------------------------------------------------+
//|                                            CPropSessionClock.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Translates broker-server time into prop-firm        |
//|               calendar boundaries: which prop day a moment falls  |
//|               in, when that day started, whether the day just     |
//|               rolled over, and whether the pre-weekend flat       |
//|               cutoff has been reached. It is the ONLY place in    |
//|               the package that converts a timestamp into a        |
//|               calendar decision.                                  |
//| Failure mode: A hardcoded daily boundary at server midnight is    |
//|               wrong for every firm whose day rolls at 17:00 CT,   |
//|               00:00 CET or anything else, and offers no input to  |
//|               change it. Here the reset hour, reset minute and    |
//|               timezone offset are profile fields and this class   |
//|               is their single consumer. DetectRollover() is what  |
//|               lets the coordinator drive ResetIntraday() across   |
//|               the rule table exactly once per prop day.           |
//| Dependencies: PropFirmProfile.mqh                                 |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+
#include "PropFirmProfile.mqh"

//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

//| Time model used here, stated explicitly because getting it wrong  |
//| silently mis-attributes a whole day of profit and loss:           |
//|                                                                   |
//|   firm_local_time = server_time + timezone_offset_hours * 3600    |
//|                                                                   |
//| daily_reset_hour / daily_reset_minute are expressed in FIRM-LOCAL |
//| time. So the boundary lands on server clock hour                  |
//| (daily_reset_hour - timezone_offset_hours).                       |
//|                                                                   |
//|   offset  0, reset 00:00 -> boundary at 00:00 server (default)    |
//|   offset  0, reset 17:00 -> boundary at 17:00 server              |
//|   offset -2, reset 15:00 -> boundary at 17:00 server              |
//|   offset +1, reset 00:00 -> boundary at 23:00 server              |
//|                                                                   |
//| The weekend cutoff is deliberately NOT converted: a broker's      |
//| Friday close is a server-clock event, so weekend_cutoff_dow /     |
//| _hour / _minute are read as plain server time.                    |
//+------------------------------------------------------------------+
class CPropSessionClock
{
private:
   int      m_reset_hour;
   int      m_reset_minute;
   int      m_offset_hours;

   bool     m_use_weekend_cutoff;
   int      m_cut_dow;
   int      m_cut_hour;
   int      m_cut_minute;

   int      m_last_day_index;
   bool     m_has_day_index;
   bool     m_configured;

   //--- seconds-of-week key, week starting Sunday 00:00 server
   int      WeekKey(const datetime t) const
   {
      MqlDateTime st;
      TimeToStruct(t, st);
      return st.day_of_week * 86400 + st.hour * 3600 + st.min * 60 + st.sec;
   }

   int      CutoffKey() const
   {
      return m_cut_dow * 86400 + m_cut_hour * 3600 + m_cut_minute * 60;
   }

public:
   CPropSessionClock()
      : m_reset_hour(0), m_reset_minute(0), m_offset_hours(0),
        m_use_weekend_cutoff(false), m_cut_dow(5), m_cut_hour(PROP_UNSET_HOUR),
        m_cut_minute(0), m_last_day_index(0), m_has_day_index(false),
        m_configured(false) {}

   //+---------------------------------------------------------------+
   //| Reads the calendar slice of the profile. The profile is        |
   //| validated upstream, so the values arriving here are in range.  |
   //+---------------------------------------------------------------+
   void Configure(const PropFirmProfile &profile)
   {
      m_reset_hour         = profile.daily_reset_hour;
      m_reset_minute       = profile.daily_reset_minute;
      m_offset_hours       = profile.timezone_offset_hours;

      m_use_weekend_cutoff = profile.use_weekend_flat;
      m_cut_dow            = profile.weekend_cutoff_dow;
      m_cut_hour           = profile.weekend_cutoff_hour;
      m_cut_minute         = profile.weekend_cutoff_minute;

      m_configured         = true;
   }

   bool IsConfigured() const { return m_configured; }

   //+---------------------------------------------------------------+
   //| Server time at which the prop day containing t began.          |
   //+---------------------------------------------------------------+
   datetime PropDayStart(const datetime t) const
   {
      long offset_secs = (long)m_offset_hours * 3600;
      long local       = (long)t + offset_secs;

      MqlDateTime lt;
      TimeToStruct((datetime)local, lt);

      long sod        = (long)lt.hour * 3600 + (long)lt.min * 60 + (long)lt.sec;
      long midnight   = local - sod;
      long boundary   = midnight + (long)m_reset_hour * 3600 + (long)m_reset_minute * 60;

      if(local < boundary)
         boundary -= 86400;

      return (datetime)(boundary - offset_secs);
   }

   //+---------------------------------------------------------------+
   //| Integer identity of the prop day containing t. Two timestamps  |
   //| share a prop day if and only if this value matches, which is   |
   //| what CDailyProfitLedger keys its per-day records on.           |
   //+---------------------------------------------------------------+
   int PropDayIndex(const datetime t) const
   {
      long boundary_local = (long)PropDayStart(t) + (long)m_offset_hours * 3600;
      return (int)(boundary_local / 86400);
   }

   //--- seconds already elapsed inside the current prop day
   int SecondsIntoPropDay(const datetime t) const
   {
      return (int)((long)t - (long)PropDayStart(t));
   }

   //--- seconds left before the next prop-day boundary
   int SecondsToNextPropDay(const datetime t) const
   {
      return 86400 - SecondsIntoPropDay(t);
   }

   //+---------------------------------------------------------------+
   //| Stateful rollover detector. Returns true exactly once per prop |
   //| day: on the first call whose timestamp belongs to a day index  |
   //| different from the last one seen. The very first call after    |
   //| Configure() (or after a restore) returns false -- starting the |
   //| EA is not a rollover, and treating it as one would rearm       |
   //| intraday latches on every terminal restart.                    |
   //+---------------------------------------------------------------+
   bool DetectRollover(const datetime t)
   {
      int idx = PropDayIndex(t);

      if(!m_has_day_index)
      {
         m_last_day_index = idx;
         m_has_day_index  = true;
         return false;
      }

      if(idx == m_last_day_index)
         return false;

      m_last_day_index = idx;
      return true;
   }

   int  LastDayIndex() const { return m_last_day_index; }
   bool HasDayIndex()  const { return m_has_day_index; }

   //+---------------------------------------------------------------+
   //| Pre-weekend flat cutoff, in server time.                       |
   //+---------------------------------------------------------------+
   bool IsPastWeekendCutoff(const datetime t) const
   {
      if(!m_use_weekend_cutoff || m_cut_hour == PROP_UNSET_HOUR)
         return false;
      return (WeekKey(t) >= CutoffKey());
   }

   //--- minutes until the cutoff; negative once it has passed
   int MinutesToWeekendCutoff(const datetime t) const
   {
      if(!m_use_weekend_cutoff || m_cut_hour == PROP_UNSET_HOUR)
         return 0;
      return (CutoffKey() - WeekKey(t)) / 60;
   }

   //+---------------------------------------------------------------+
   //| Persistence (C9). The day index has to survive a restart, or a |
   //| terminal that reboots at 03:00 would treat 03:01 as a new prop |
   //| day and rearm the daily loss latch it just consumed.           |
   //+---------------------------------------------------------------+
   string Serialize() const
   {
      return StringFormat("%d|%d", (m_has_day_index ? 1 : 0), m_last_day_index);
   }

   bool Deserialize(const string state)
   {
      string parts[];
      if(StringSplit(state, (ushort)'|', parts) != 2)
         return false;
      m_has_day_index  = ((int)StringToInteger(parts[0]) == 1);
      m_last_day_index = (int)StringToInteger(parts[1]);
      return true;
   }

   void Reset()
   {
      m_last_day_index = 0;
      m_has_day_index  = false;
   }
};
//+------------------------------------------------------------------+
