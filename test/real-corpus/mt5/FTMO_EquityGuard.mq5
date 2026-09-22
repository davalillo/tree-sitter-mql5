//+------------------------------------------------------------------+
//|                                             FTMO_EquityGuard.mq5 |
//|        Prop-Firm Equity Guard — daily & max drawdown protection  |
//|                                                                  |
//|  Attach this utility EA to ONE chart. It monitors the whole      |
//|  account and protects prop-firm style limits (FTMO and similar): |
//|                                                                  |
//|   1. DAILY loss limit  — measured from the day-start snapshot    |
//|   2. MAX overall loss  — measured from the initial account size  |
//|                                                                  |
//|  When a limit (minus your safety buffer) is hit, the guard:      |
//|   - closes ALL open positions and deletes ALL pending orders     |
//|   - sets the global variable "DDGUARD_HALT" to 1.0 so that any   |
//|     other EA on the account can stop trading too. In your own    |
//|     EAs simply check:                                            |
//|        if(GlobalVariableGet("DDGUARD_HALT") > 0.0) return;       |
//|                                                                  |
//|  Trading stays blocked until the next trading day (daily breach) |
//|  or permanently (max breach), matching prop-firm logic.          |
//+------------------------------------------------------------------+
#property copyright "Cristian Ciunae"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//--- inputs
input double InpInitialBalance   = 100000.0; // Initial account size (challenge size)
input double InpDailyLossPct     = 5.0;      // Prop-firm daily loss limit, %
input double InpMaxLossPct       = 10.0;     // Prop-firm max overall loss limit, %
input double InpBufferPct        = 1.0;      // Safety buffer, % (halt this much BEFORE the real limit)
input int    InpDayStartHour     = 0;        // Trading-day rollover hour (server time, FTMO: midnight CE(S)T)
input bool   InpUseEquityForDay  = true;     // Day-start snapshot: true = max(balance, equity), false = balance
input bool   InpCloseOnBreach    = true;     // Close all positions/orders on breach
input string InpHaltFlagName     = "DDGUARD_HALT"; // Global variable name other EAs should check

//--- state
CTrade   trade;
double   g_dayStartLevel  = 0.0;   // snapshot at the start of the trading day
datetime g_currentDay     = 0;     // day being tracked (rounded to rollover)
bool     g_dailyBreached  = false;
bool     g_maxBreached    = false;

//+------------------------------------------------------------------+
//| Returns the current trading-day anchor (server time)             |
//+------------------------------------------------------------------+
datetime TradingDayAnchor()
  {
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   dt.hour = InpDayStartHour;
   dt.min  = 0;
   dt.sec  = 0;
   datetime anchor = StructToTime(dt);
   if(anchor > now)               // before today's rollover -> still previous trading day
      anchor -= 86400;
   return anchor;
  }
//+------------------------------------------------------------------+
//| Take the day-start snapshot                                      |
//+------------------------------------------------------------------+
void SnapshotDayStart()
  {
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStartLevel = InpUseEquityForDay ? MathMax(bal, eq) : bal;
   g_dailyBreached = false;                       // daily block resets each new day
   PrintFormat("[EquityGuard] New trading day. Day-start level: %.2f", g_dayStartLevel);
  }
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpInitialBalance <= 0)
     {
      Print("[EquityGuard] InpInitialBalance must be > 0");
      return(INIT_PARAMETERS_INCORRECT);
     }
   g_currentDay = TradingDayAnchor();
   SnapshotDayStart();
   GlobalVariableSet(InpHaltFlagName, 0.0);
   PrintFormat("[EquityGuard] Active. Daily limit %.1f%% | Max limit %.1f%% | Buffer %.1f%%",
               InpDailyLossPct, InpMaxLossPct, InpBufferPct);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // Keep the halt flag if a MAX breach happened (permanent), clear otherwise
   if(!g_maxBreached)
      GlobalVariableSet(InpHaltFlagName, 0.0);
  }
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- day rollover
   datetime anchor = TradingDayAnchor();
   if(anchor != g_currentDay)
     {
      g_currentDay = anchor;
      SnapshotDayStart();
      if(!g_maxBreached)
         GlobalVariableSet(InpHaltFlagName, 0.0);  // re-allow trading on a new day
     }

   if(g_maxBreached)
      return;                                      // permanent stop, nothing more to do

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   //--- 1) MAX overall drawdown (from initial account size)
   double maxStopLevel = InpInitialBalance * (1.0 - (InpMaxLossPct - InpBufferPct) / 100.0);
   if(equity <= maxStopLevel)
     {
      g_maxBreached = true;
      Halt(StringFormat("MAX drawdown protection hit. Equity %.2f <= %.2f", equity, maxStopLevel));
      return;
     }

   //--- 2) DAILY drawdown (from day-start snapshot)
   if(!g_dailyBreached)
     {
      double dailyStopLevel = g_dayStartLevel * (1.0 - (InpDailyLossPct - InpBufferPct) / 100.0);
      if(equity <= dailyStopLevel)
        {
         g_dailyBreached = true;
         Halt(StringFormat("DAILY drawdown protection hit. Equity %.2f <= %.2f", equity, dailyStopLevel));
        }
     }
  }
//+------------------------------------------------------------------+
//| Stop trading account-wide                                        |
//+------------------------------------------------------------------+
void Halt(const string reason)
  {
   Print("[EquityGuard] *** TRADING HALTED *** ", reason);
   GlobalVariableSet(InpHaltFlagName, 1.0);

   if(!InpCloseOnBreach)
      return;

   //--- close all open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         if(!trade.PositionClose(ticket))
            PrintFormat("[EquityGuard] Failed to close position #%I64u (retcode %d)",
                        ticket, trade.ResultRetcode());
        }
     }
   //--- delete all pending orders
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
        {
         if(!trade.OrderDelete(ticket))
            PrintFormat("[EquityGuard] Failed to delete order #%I64u (retcode %d)",
                        ticket, trade.ResultRetcode());
        }
     }
  }
//+------------------------------------------------------------------+
