//+------------------------------------------------------------------+
//|                                        CEconomicCalendarFeed.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Reads high-impact events from MQL5's native economic|
//|               calendar (CalendarValueHistory / MqlCalendarValue / |
//|               MqlCalendarEvent) into a plain in-memory event list,|
//|               and can be populated synthetically instead, so the  |
//|               news rule can be tested deterministically and can   |
//|               still be reasoned about where no live calendar      |
//|               exists.                                             |
//| Failure mode: This feed is one half of a news-window rule family  |
//|               that hand-rolled guards typically skip entirely.    |
//|               Its most important property is what it does when    |
//|               the calendar is NOT reachable (Strategy Tester, a   |
//|               terminal with no MQL5 community connection, a       |
//|               permissions error): it reports itself unavailable   |
//|               so CNewsWindowRule ABSTAINS. A feed that returned   |
//|               "no events" on failure would silently switch the    |
//|               news protection off; a feed that returned "assume   |
//|               an event" would block every entry forever. Neither  |
//|               is acceptable, so unavailability is a third state.  |
//| Dependencies: none                                                |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| One high-impact event reduced to what the rule needs.            |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

struct PropCalendarEvent
{
   datetime time;
   string   name;
   string   currency;

   PropCalendarEvent()
   {
      time     = 0;
      name     = "";
      currency = "";
   }
};

//+------------------------------------------------------------------+
//| Native-calendar reader with an explicit unavailable state.       |
//+------------------------------------------------------------------+
class CEconomicCalendarFeed
{
private:
   PropCalendarEvent m_events[];
   string            m_currency_filter;   // CSV, "" = accept every currency
   int               m_lookback_minutes;
   int               m_lookahead_minutes;
   int               m_refresh_seconds;

   bool              m_synthetic;
   bool              m_available;
   bool              m_probed;
   datetime          m_last_refresh;
   int               m_last_error;
   bool              m_ready;

   //--- case-insensitive CSV membership test
   bool CurrencyAccepted(const string currency) const
   {
      if(StringLen(m_currency_filter) == 0)
         return true;
      if(StringLen(currency) == 0)
         return false;

      string want = m_currency_filter;
      string have = currency;
      StringToUpper(want);
      StringToUpper(have);

      string parts[];
      int n = StringSplit(want, (ushort)',', parts);
      for(int i = 0; i < n; i++)
      {
         string p = parts[i];
         StringTrimLeft(p);
         StringTrimRight(p);
         if(p == have)
            return true;
      }
      return false;
   }

   void SortByTime()
   {
      int n = ArraySize(m_events);
      for(int i = 1; i < n; i++)
      {
         PropCalendarEvent key = m_events[i];
         int j = i - 1;
         while(j >= 0 && m_events[j].time > key.time)
         {
            m_events[j + 1] = m_events[j];
            j--;
         }
         m_events[j + 1] = key;
      }
   }

   bool Push(const datetime when, const string name, const string currency)
   {
      int n = ArraySize(m_events);
      if(ArrayResize(m_events, n + 1) != n + 1)
         return false;
      m_events[n].time     = when;
      m_events[n].name     = name;
      m_events[n].currency = currency;
      return true;
   }

   //+---------------------------------------------------------------+
   //| One-off availability probe. A live calendar always has SOME    |
   //| event in a two-week window, so an empty wide window (or any    |
   //| runtime error) is treated as "this terminal has no calendar".  |
   //+---------------------------------------------------------------+
   void Probe(const datetime now)
   {
      m_probed = true;

      MqlCalendarValue probe[];
      ResetLastError();
      int count = CalendarValueHistory(probe, now - 7 * 86400, now + 7 * 86400, NULL, NULL);
      m_last_error = GetLastError();

      if(count > 0)
      {
         m_available = true;
         return;
      }

      m_available = false;
      PrintFormat("CEconomicCalendarFeed: native calendar unavailable (values=%d, error=%d) -- "
                  "the news rule will abstain instead of blocking.", count, m_last_error);
   }

public:
   CEconomicCalendarFeed()
      : m_currency_filter(""), m_lookback_minutes(120), m_lookahead_minutes(1440),
        m_refresh_seconds(300), m_synthetic(false), m_available(false),
        m_probed(false), m_last_refresh(0), m_last_error(0), m_ready(false) {}

   //+---------------------------------------------------------------+
   //| currency_filter: CSV such as "USD,EUR"; "" accepts every       |
   //| currency. The windows bound how far the feed looks around the  |
   //| current moment -- they are not the blackout window, which      |
   //| belongs to CNewsWindowRule.                                    |
   //+---------------------------------------------------------------+
   bool Init(const string currency_filter,
             const int lookback_minutes,
             const int lookahead_minutes,
             const int refresh_seconds)
   {
      if(lookback_minutes < 0 || lookahead_minutes <= 0)
      {
         Print("CEconomicCalendarFeed::Init failed: invalid lookback/lookahead window");
         return false;
      }
      if(refresh_seconds <= 0)
      {
         Print("CEconomicCalendarFeed::Init failed: refresh_seconds must be positive");
         return false;
      }

      m_currency_filter   = currency_filter;
      m_lookback_minutes  = lookback_minutes;
      m_lookahead_minutes = lookahead_minutes;
      m_refresh_seconds   = refresh_seconds;
      m_last_refresh      = 0;
      m_probed            = false;
      m_available         = false;
      ArrayFree(m_events);
      m_ready             = true;
      return true;
   }

   bool IsReady()     const { return m_ready; }
   bool IsAvailable() const { return m_available; }
   bool IsSynthetic() const { return m_synthetic; }
   int  LastError()   const { return m_last_error; }
   int  EventCount()  const { return ArraySize(m_events); }

   //+---------------------------------------------------------------+
   //| Test / tester mode: the feed stops calling the terminal and    |
   //| serves whatever AddSyntheticEvent() was given. Availability    |
   //| becomes true only once at least one synthetic event exists,    |
   //| so an empty synthetic feed still abstains rather than          |
   //| pretending the calendar is clean.                              |
   //+---------------------------------------------------------------+
   void EnableSyntheticMode(const bool on)
   {
      m_synthetic = on;
      if(on)
      {
         ArrayFree(m_events);
         m_available = false;
      }
      else
      {
         m_probed    = false;
         m_available = false;
      }
   }

   bool AddSyntheticEvent(const datetime when, const string name, const string currency)
   {
      if(!Push(when, name, currency))
         return false;
      SortByTime();
      m_available = true;
      return true;
   }

   void ClearEvents()
   {
      ArrayFree(m_events);
      if(m_synthetic)
         m_available = false;
   }

   //+---------------------------------------------------------------+
   //| Pulls the high-impact events around 'now' from the terminal.   |
   //| Throttled to refresh_seconds; returns true when the event list |
   //| can be trusted for this pass. Contains no Sleep() and is safe  |
   //| to call from OnTick through the snapshot builder.              |
   //+---------------------------------------------------------------+
   bool Refresh(const datetime now)
   {
      if(!m_ready)
         return false;

      if(m_synthetic)
         return m_available;

      if(!m_probed)
         Probe(now);

      if(!m_available)
         return false;

      if(m_last_refresh != 0 && (now - m_last_refresh) < m_refresh_seconds)
         return true;

      m_last_refresh = now;

      datetime from = (datetime)((long)now - (long)m_lookback_minutes * 60);
      datetime to   = (datetime)((long)now + (long)m_lookahead_minutes * 60);

      MqlCalendarValue values[];
      ResetLastError();
      int count = CalendarValueHistory(values, from, to, NULL, NULL);
      m_last_error = GetLastError();

      if(count <= 0)
      {
         //--- a window that small can legitimately be empty; keep the
         //--- previously probed availability and simply clear the list
         ArrayFree(m_events);
         return true;
      }

      ArrayFree(m_events);

      for(int i = 0; i < count; i++)
      {
         MqlCalendarEvent event;
         if(!CalendarEventById(values[i].event_id, event))
            continue;

         if(event.importance != CALENDAR_IMPORTANCE_HIGH)
            continue;

         string currency = "";
         MqlCalendarCountry country;
         if(CalendarCountryById(event.country_id, country))
            currency = country.currency;

         if(!CurrencyAccepted(currency))
            continue;

         if(!Push(values[i].time, event.name, currency))
            break;
      }

      SortByTime();
      return true;
   }

   //+---------------------------------------------------------------+
   //| First event at or after 'now'.                                 |
   //+---------------------------------------------------------------+
   bool NextEvent(const datetime now, datetime &when, string &name, string &currency) const
   {
      for(int i = 0; i < ArraySize(m_events); i++)
      {
         if(m_events[i].time >= now)
         {
            when     = m_events[i].time;
            name     = m_events[i].name;
            currency = m_events[i].currency;
            return true;
         }
      }
      return false;
   }

   //+---------------------------------------------------------------+
   //| Last event strictly before 'now'.                              |
   //+---------------------------------------------------------------+
   bool LastEvent(const datetime now, datetime &when, string &name, string &currency) const
   {
      bool found = false;
      for(int i = 0; i < ArraySize(m_events); i++)
      {
         if(m_events[i].time < now)
         {
            when     = m_events[i].time;
            name     = m_events[i].name;
            currency = m_events[i].currency;
            found    = true;
         }
         else
            break;   // list is sorted ascending
      }
      return found;
   }

   bool EventAt(const int i, PropCalendarEvent &out) const
   {
      if(i < 0 || i >= ArraySize(m_events))
         return false;
      out = m_events[i];
      return true;
   }
};
//+------------------------------------------------------------------+
