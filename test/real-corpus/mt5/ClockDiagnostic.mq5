//+------------------------------------------------------------------+
//|                                            ClockDiagnostic.mq5   |
//|  TimeCurrent() is not a clock. It is the stamp of the LAST TICK. |
//|                                                                  |
//|  Two consequences that break robots in production:               |
//|                                                                  |
//|  1. IT FREEZES. With no tick, TimeCurrent() does not move. On an |
//|     illiquid instrument, at the end of the session, or with an   |
//|     unstable connection, it stops — and any rule based on it     |
//|     stops with it.                                               |
//|                                                                  |
//|  2. IT STEPS BACKWARDS. When switching symbol, reconnecting, or  |
//|     receiving a tick from another instrument, the value can GO   |
//|     BACK.                                                        |
//|                                                                  |
//|  The real case that cost me a whole protection: I compared the   |
//|  date of a daily decision with TimeCurrent() to reject a stale   |
//|  decision. The server clock stepped back to the previous day, the|
//|  comparison started to match, and the four EAs accepted          |
//|  YESTERDAY's decision as valid. The gate that should have failed |
//|  closed failed OPEN — and without a single error in the log.     |
//|                                                                  |
//|  THE RULE that stayed:                                           |
//|                                                                  |
//|     TimeLocal()    for timestamps, dates, day changes, expiry —  |
//|                    everything that must ALWAYS MOVE FORWARD.     |
//|     TimeCurrent()  for session hours and comparison with market  |
//|                    data — where the server time zone is what     |
//|                    counts.                                       |
//|                                                                  |
//|  This script measures the difference in your environment and     |
//|  reports both symptoms live. Leave it running for a few minutes  |
//|  with the market closed: that is when the divergence shows.      |
//+------------------------------------------------------------------+
#property copyright "Joao Prata Silva Yglesias"
#property link      "https://www.mql5.com/en/users/jotayglesias"
#property version   "1.00"
#property script_show_inputs

input int InpSeconds = 60;   // Observation length (seconds)
input int InpStep    = 2;    // Interval between readings (seconds)

void OnStart()
  {
   datetime serverBefore = TimeCurrent();
   datetime localBefore  = TimeLocal();

   PrintFormat("TimeCurrent() = %s   (stamp of the last tick)",
               TimeToString(serverBefore, TIME_DATE|TIME_SECONDS));
   PrintFormat("TimeLocal()   = %s   (machine clock)",
               TimeToString(localBefore, TIME_DATE|TIME_SECONDS));
   PrintFormat("initial difference: %d seconds (%.1f hours)",
               (int)(localBefore - serverBefore), (localBefore - serverBefore) / 3600.0);
   Print("");
   Print("observing... (freezes and step-backs are reported below)");
   Print("");

   int    frozen = 0, stepBacks = 0, readings = 0;
   int    longestFreeze = 0;
   datetime lastServer = serverBefore;

   for(int t = 0; t < InpSeconds; t += InpStep)
     {
      Sleep(InpStep * 1000);
      if(IsStopped()) break;

      datetime serverNow = TimeCurrent();
      readings++;

      if(serverNow < lastServer)
        {
         stepBacks++;
         PrintFormat(">>> STEP BACK: TimeCurrent() went back %d seconds (%s -> %s). "
                     "Every date comparison based on it has just lied.",
                     (int)(lastServer - serverNow),
                     TimeToString(lastServer, TIME_DATE|TIME_SECONDS),
                     TimeToString(serverNow, TIME_DATE|TIME_SECONDS));
        }
      else if(serverNow == lastServer)
        {
         frozen += InpStep;
         if(frozen > longestFreeze) longestFreeze = frozen;
        }
      else
        {
         frozen = 0;
        }

      lastServer = serverNow;
     }

   datetime serverAfter = TimeCurrent();
   datetime localAfter  = TimeLocal();

   Print("");
   Print("================================================");
   PrintFormat("%d readings in ~%d seconds", readings, InpSeconds);
   PrintFormat("TimeLocal()   advanced %d seconds", (int)(localAfter - localBefore));
   PrintFormat("TimeCurrent() advanced %d seconds", (int)(serverAfter - serverBefore));
   PrintFormat("longest freeze observed: %d seconds", longestFreeze);
   PrintFormat("step-backs observed: %d", stepBacks);
   Print("");

   if(stepBacks > 0)
      Print(">>> The server clock STEPPED BACKWARDS in this test. If any rule of "
            "yours compares dates with TimeCurrent(), it has already failed today.");
   else if(longestFreeze >= InpSeconds / 2)
      Print(">>> The server clock stayed FROZEN for most of the test. Without a "
            "tick it does not move — and it is no good for measuring elapsed time.");
   else
      Print(">>> No anomaly in this window. Run again with the market CLOSED: "
            "that is when the freeze shows up.");

   Print("");
   Print("RULE: TimeLocal() for timestamps, dates and day changes.");
   Print("      TimeCurrent() for session hours.");
   Print("================================================");
  }
//+------------------------------------------------------------------+
