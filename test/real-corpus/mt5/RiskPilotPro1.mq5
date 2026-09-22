//+------------------------------------------------------------------+
//|                                                  RiskPilotPro.mq5 |
//|                                        Copyright 2026, Ali Akbar  |
//|                            https://www.mql5.com/en/users/alifx9   |
//+------------------------------------------------------------------+
#property copyright "Ali Akbar"
#property link      "https://www.mql5.com/en/users/alifx9"
#property version   "1.00"
#property description "Interactive risk management and execution panel: drag-to-size lot calculation, one-click trading, break-even/trailing automation, daily loss guard and basket risk view."
#property strict

#include <Trade\Trade.mqh>

//--- input parameters
input group "=== Risk Settings ==="
input double InpRiskPercent            = 1.0;        // Risk per trade, % of balance
input double InpRewardRatio            = 2.0;        // Reward:Risk ratio for auto TP
input int    InpMagicNumber            = 20260907;   // Magic number for EA trades

input group "=== ATR Stop Loss ==="
input bool   InpUseATRForReset         = true;       // Use ATR distance when resetting SL line
input int    InpATRPeriod              = 14;         // ATR period
input double InpATRMultiplier          = 1.5;        // ATR multiplier for stop distance

input group "=== Break-Even & Trailing ==="
input bool   InpEnableBreakEven        = true;       // Enable automatic break-even
input double InpBreakEvenTriggerPips   = 20.0;       // Move to break-even after this many pips profit
input double InpBreakEvenOffsetPips    = 2.0;        // Lock this many pips beyond entry
input bool   InpEnableTrailing         = true;       // Enable automatic trailing stop
input double InpTrailingStartPips      = 30.0;       // Start trailing after this many pips profit
input double InpTrailingStepPips       = 10.0;       // Trailing distance behind price

input group "=== Daily Loss Guard (Prop-Firm Style) ==="
input bool   InpEnableDailyGuard       = true;       // Enable daily loss limit guard
input double InpDailyLossLimitPercent  = 5.0;        // Max daily loss, % of day's starting balance
input bool   InpEnableMaxDrawdownGuard = true;       // Enable overall drawdown guard
input double InpMaxDrawdownPercent     = 10.0;       // Max drawdown from balance high watermark, %

input group "=== Basket Risk ==="
input double InpMaxBasketRiskPercent   = 3.0;        // Warn if combined open risk exceeds this % of balance

//--- object names
string OBJ_ENTRY_LINE    = "RPP_Entry";
string OBJ_SL_LINE       = "RPP_SL";
string OBJ_TP_LINE       = "RPP_TP";
string OBJ_RISK_ZONE     = "RPP_RiskZone";
string OBJ_REWARD_ZONE   = "RPP_RewardZone";
string OBJ_BTN_BUY       = "RPP_BtnBuy";
string OBJ_BTN_SELL      = "RPP_BtnSell";
string OBJ_BTN_RESET     = "RPP_BtnReset";
//--- OBJ_LABEL cannot render embedded newlines, so the info/warning
//--- panels are each built from a stack of single-line label objects
#define INFO_LINE_COUNT    7
#define WARNING_LINE_COUNT 2
#define LABEL_LINE_HEIGHT  16
string OBJ_INFO_LABEL[INFO_LINE_COUNT];
string OBJ_WARNING_LABEL[WARNING_LINE_COUNT];

CTrade trade;

//--- state
double   g_dayStartBalance  = 0.0;
datetime g_dayStartTime     = 0;
double   g_balanceHighWater = 0.0;
bool     g_tradingBlocked   = false;
string   g_blockReason      = "";

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);

   g_balanceHighWater = AccountInfoDouble(ACCOUNT_BALANCE);
   ResetDailyTracking();

   CreatePanel();
   PlaceLinesAtATRDistance();
   UpdatePanel();

   EventSetTimer(30);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   RemovePanel();
}

//+------------------------------------------------------------------+
//| Reset the daily balance tracker at the start of a new day          |
//+------------------------------------------------------------------+
void ResetDailyTracking()
{
   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   g_dayStartTime = StructToTime(dt);

   g_tradingBlocked = false;
   g_blockReason = "";
}

//+------------------------------------------------------------------+
//| Check whether a new trading day has started                       |
//+------------------------------------------------------------------+
void CheckNewDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime todayStart = StructToTime(dt);

   if(todayStart != g_dayStartTime)
      ResetDailyTracking();
}

//+------------------------------------------------------------------+
//| Pip size helper (handles 3/5-digit brokers)                       |
//+------------------------------------------------------------------+
double PipSize(const string symbol)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   return (digits == 3 || digits == 5) ? point * 10.0 : point;
}

//+------------------------------------------------------------------+
//| Create all chart objects for the panel                            |
//+------------------------------------------------------------------+
void CreatePanel()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pip = PipSize(_Symbol);

   CreateHLine(OBJ_ENTRY_LINE, ask,            clrDodgerBlue, "Entry (drag me)");
   CreateHLine(OBJ_SL_LINE,    ask - 20 * pip, clrRed,        "Stop Loss (drag me)");
   CreateHLine(OBJ_TP_LINE,    ask + 40 * pip, clrLimeGreen,  "Take Profit (drag me)");

   CreateButton(OBJ_BTN_BUY,   20,  20, 70, 26, "BUY",   clrWhite, C'0,140,0');
   CreateButton(OBJ_BTN_SELL,  100, 20, 70, 26, "SELL",  clrWhite, C'140,0,0');
   CreateButton(OBJ_BTN_RESET, 180, 20, 70, 26, "RESET", clrWhite, clrDimGray);

   int y = 55;
   for(int i = 0; i < INFO_LINE_COUNT; i++)
     {
      OBJ_INFO_LABEL[i] = "RPP_Info" + IntegerToString(i);
      CreateLabel(OBJ_INFO_LABEL[i], 20, y, "", clrWhite);
      y += LABEL_LINE_HEIGHT;
     }

   y += 8; // small gap before the warning block
   for(int i = 0; i < WARNING_LINE_COUNT; i++)
     {
      OBJ_WARNING_LABEL[i] = "RPP_Warning" + IntegerToString(i);
      CreateLabel(OBJ_WARNING_LABEL[i], 20, y, "", clrOrange);
      y += LABEL_LINE_HEIGHT;
     }
}

void CreateHLine(const string name, const double price, const color clr, const string tooltip)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
}

void CreateButton(const string name, const int x, const int y, const int w, const int h,
                   const string text, const color txtClr, const color bgClr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtClr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void CreateLabel(const string name, const int x, const int y, const string text, const color clr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Remove all panel objects                                          |
//+------------------------------------------------------------------+
void RemovePanel()
{
   ObjectDelete(0, OBJ_ENTRY_LINE);
   ObjectDelete(0, OBJ_SL_LINE);
   ObjectDelete(0, OBJ_TP_LINE);
   ObjectDelete(0, OBJ_RISK_ZONE);
   ObjectDelete(0, OBJ_REWARD_ZONE);
   ObjectDelete(0, OBJ_BTN_BUY);
   ObjectDelete(0, OBJ_BTN_SELL);
   ObjectDelete(0, OBJ_BTN_RESET);

   for(int i = 0; i < INFO_LINE_COUNT; i++)
      ObjectDelete(0, OBJ_INFO_LABEL[i]);
   for(int i = 0; i < WARNING_LINE_COUNT; i++)
      ObjectDelete(0, OBJ_WARNING_LABEL[i]);
}

//+------------------------------------------------------------------+
//| Place Entry/SL/TP lines using ATR distance                        |
//+------------------------------------------------------------------+
void PlaceLinesAtATRDistance()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double slDistance = 20 * PipSize(_Symbol);

   if(InpUseATRForReset)
     {
      int handle = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
      double atrBuf[];
      if(handle != INVALID_HANDLE)
        {
         if(CopyBuffer(handle, 0, 0, 1, atrBuf) > 0)
            slDistance = atrBuf[0] * InpATRMultiplier;
         IndicatorRelease(handle);
        }
     }

   double entry = ask;
   double sl    = ask - slDistance;
   double tp    = ask + slDistance * InpRewardRatio;

   ObjectSetDouble(0, OBJ_ENTRY_LINE, OBJPROP_PRICE, entry);
   ObjectSetDouble(0, OBJ_SL_LINE,    OBJPROP_PRICE, sl);
   ObjectSetDouble(0, OBJ_TP_LINE,    OBJPROP_PRICE, tp);
}

//+------------------------------------------------------------------+
//| Draw the red risk zone and green reward zone rectangles           |
//+------------------------------------------------------------------+
void DrawZones()
{
   double entry = ObjectGetDouble(0, OBJ_ENTRY_LINE, OBJPROP_PRICE);
   double sl    = ObjectGetDouble(0, OBJ_SL_LINE,    OBJPROP_PRICE);
   double tp    = ObjectGetDouble(0, OBJ_TP_LINE,    OBJPROP_PRICE);

   datetime t1 = TimeCurrent();
   datetime t2 = t1 + PeriodSeconds(PERIOD_CURRENT) * 20;

   DrawRectangle(OBJ_RISK_ZONE,   t1, entry, t2, sl, C'80,20,20');
   DrawRectangle(OBJ_REWARD_ZONE, t1, entry, t2, tp, C'20,60,20');
}

void DrawRectangle(const string name, const datetime t1, const double p1,
                    const datetime t2, const double p2, const color clr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   else
     {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Calculate lot size for the given risk amount and stop distance    |
//+------------------------------------------------------------------+
double CalcLotSize(const double riskMoney, const double slDistance)
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0 || slDistance <= 0.0)
      return 0.0;

   double valuePerPriceUnit = tickValue / tickSize;
   double rawLot = riskMoney / (slDistance * valuePerPriceUnit);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double lot = MathFloor(rawLot / lotStep) * lotStep;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   return lot;
}

//+------------------------------------------------------------------+
//| Sum the money risk currently open across all EA-managed positions |
//+------------------------------------------------------------------+
double CalcBasketRisk()
{
   double totalRisk = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      string symbol    = PositionGetString(POSITION_SYMBOL);
      double volume     = PositionGetDouble(POSITION_VOLUME);
      double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl         = PositionGetDouble(POSITION_SL);
      if(sl <= 0.0) continue; // no stop loss set, cannot size this position's risk

      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0.0) continue;

      double distance = MathAbs(openPrice - sl);
      totalRisk += distance * (tickValue / tickSize) * volume;
     }

   return totalRisk;
}

//+------------------------------------------------------------------+
//| Refresh the information label with current calculation            |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   double entry = ObjectGetDouble(0, OBJ_ENTRY_LINE, OBJPROP_PRICE);
   double sl    = ObjectGetDouble(0, OBJ_SL_LINE,    OBJPROP_PRICE);
   double tp    = ObjectGetDouble(0, OBJ_TP_LINE,    OBJPROP_PRICE);

   double slDistance = MathAbs(entry - sl);
   double tpDistance = MathAbs(tp - entry);
   double rr = (slDistance > 0.0) ? tpDistance / slDistance : 0.0;

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPercent / 100.0);
   double lot       = CalcLotSize(riskMoney, slDistance);

   double marginNeeded = 0.0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, entry, marginNeeded)) marginNeeded = 0.0;
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   double basketRisk    = CalcBasketRisk() + riskMoney;
   double basketRiskPct = (balance > 0.0) ? (basketRisk / balance) * 100.0 : 0.0;

   double dayPL        = AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartBalance;
   double dayPLPercent = (g_dayStartBalance > 0.0) ? (dayPL / g_dayStartBalance) * 100.0 : 0.0;

   string infoLines[INFO_LINE_COUNT];
   infoLines[0] = StringFormat("Symbol: %s", _Symbol);
   infoLines[1] = StringFormat("Risk: %.2f%% = %.2f %s", InpRiskPercent, riskMoney, AccountInfoString(ACCOUNT_CURRENCY));
   infoLines[2] = StringFormat("Stop distance: %.1f pips   R:R  1:%.2f", slDistance / PipSize(_Symbol), rr);
   infoLines[3] = StringFormat("Lot size: %.2f", lot);
   infoLines[4] = StringFormat("Margin required: %.2f (free: %.2f)", marginNeeded, freeMargin);
   infoLines[5] = StringFormat("Basket risk if filled: %.2f%%", basketRiskPct);
   infoLines[6] = StringFormat("Today P/L: %.2f (%.2f%%)", dayPL, dayPLPercent);

   for(int i = 0; i < INFO_LINE_COUNT; i++)
      ObjectSetString(0, OBJ_INFO_LABEL[i], OBJPROP_TEXT, infoLines[i]);

   string warningLines[WARNING_LINE_COUNT];
   warningLines[0] = (basketRiskPct > InpMaxBasketRiskPercent)
                        ? StringFormat("Basket risk %.2f%% exceeds limit %.2f%%", basketRiskPct, InpMaxBasketRiskPercent)
                        : "";
   warningLines[1] = g_tradingBlocked ? ("TRADING BLOCKED: " + g_blockReason) : "";

   for(int i = 0; i < WARNING_LINE_COUNT; i++)
      ObjectSetString(0, OBJ_WARNING_LABEL[i], OBJPROP_TEXT, warningLines[i]);

   DrawZones();
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Execute a market order using the current panel lines               |
//+------------------------------------------------------------------+
void ExecuteTrade(const bool isBuy)
{
   if(g_tradingBlocked)
     {
      Alert("RiskPilot Pro: trading is blocked - ", g_blockReason);
      return;
     }

   double entry = ObjectGetDouble(0, OBJ_ENTRY_LINE, OBJPROP_PRICE);
   double sl    = ObjectGetDouble(0, OBJ_SL_LINE,    OBJPROP_PRICE);

   double slDistance = MathAbs(entry - sl);
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney  = balance * (InpRiskPercent / 100.0);
   double lot        = CalcLotSize(riskMoney, slDistance);

   if(lot <= 0.0)
     {
      Alert("RiskPilot Pro: calculated lot size is zero, trade not sent.");
      return;
     }

   double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // reproject SL/TP as a distance from the live price, so the trade
   // keeps the same risk even if price moved since the lines were set
   double liveSL = isBuy ? price - slDistance : price + slDistance;
   double liveTP = isBuy ? price + slDistance * InpRewardRatio : price - slDistance * InpRewardRatio;

   bool result = isBuy ? trade.Buy(lot, _Symbol, price, liveSL, liveTP, "RiskPilot Pro")
                        : trade.Sell(lot, _Symbol, price, liveSL, liveTP, "RiskPilot Pro");

   if(!result)
      Alert("RiskPilot Pro: order failed - ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Manage break-even and trailing stop for EA-managed positions      |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   double pip = PipSize(_Symbol);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      long   type      = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL     = PositionGetDouble(POSITION_SL);
      double curTP     = PositionGetDouble(POSITION_TP);
      double price     = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                       : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double profitPips = (type == POSITION_TYPE_BUY) ? (price - openPrice) / pip
                                                        : (openPrice - price) / pip;

      double newSL = curSL;

      //--- break-even: lock a small profit once trigger distance is reached
      if(InpEnableBreakEven && profitPips >= InpBreakEvenTriggerPips)
        {
         double beLevel = (type == POSITION_TYPE_BUY) ? openPrice + InpBreakEvenOffsetPips * pip
                                                        : openPrice - InpBreakEvenOffsetPips * pip;
         bool needsUpdate = (type == POSITION_TYPE_BUY) ? (newSL < beLevel)
                                                          : (newSL > beLevel || newSL == 0.0);
         if(needsUpdate) newSL = beLevel;
        }

      //--- trailing stop: follow price once trailing start distance is reached
      if(InpEnableTrailing && profitPips >= InpTrailingStartPips)
        {
         double trailLevel = (type == POSITION_TYPE_BUY) ? price - InpTrailingStepPips * pip
                                                            : price + InpTrailingStepPips * pip;
         bool improves = (type == POSITION_TYPE_BUY) ? (trailLevel > newSL)
                                                        : (trailLevel < newSL || newSL == 0.0);
         if(improves) newSL = trailLevel;
        }

      if(newSL != curSL && newSL != 0.0)
         trade.PositionModify(ticket, NormalizeDouble(newSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)), curTP);
     }
}

//+------------------------------------------------------------------+
//| Enforce the daily loss limit and overall drawdown guard            |
//+------------------------------------------------------------------+
void EnforceGuards()
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(balance > g_balanceHighWater)
      g_balanceHighWater = balance;

   if(g_tradingBlocked) return;

   if(InpEnableDailyGuard && g_dayStartBalance > 0.0)
     {
      double dayLossPercent = (g_dayStartBalance - equity) / g_dayStartBalance * 100.0;
      if(dayLossPercent >= InpDailyLossLimitPercent)
        {
         g_tradingBlocked = true;
         g_blockReason = StringFormat("daily loss limit reached (%.2f%%)", dayLossPercent);
         CloseAllManagedPositions();
        }
     }

   if(!g_tradingBlocked && InpEnableMaxDrawdownGuard && g_balanceHighWater > 0.0)
     {
      double drawdownPercent = (g_balanceHighWater - equity) / g_balanceHighWater * 100.0;
      if(drawdownPercent >= InpMaxDrawdownPercent)
        {
         g_tradingBlocked = true;
         g_blockReason = StringFormat("max drawdown reached (%.2f%%)", drawdownPercent);
         CloseAllManagedPositions();
        }
     }
}

//+------------------------------------------------------------------+
//| Close every position opened by this EA (used when a guard trips)  |
//+------------------------------------------------------------------+
void CloseAllManagedPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      trade.PositionClose(ticket);
     }
   Alert("RiskPilot Pro: ", g_blockReason, " - all managed positions closed.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckNewDay();
   ManageOpenPositions();
   EnforceGuards();
}

//+------------------------------------------------------------------+
//| Timer function - keeps the panel numbers fresh even without ticks |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdatePanel();
}

//+------------------------------------------------------------------+
//| ChartEvent handler - dragging lines and pressing panel buttons     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_DRAG)
     {
      if(sparam == OBJ_ENTRY_LINE || sparam == OBJ_SL_LINE || sparam == OBJ_TP_LINE)
         UpdatePanel();
      return;
     }

   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(sparam == OBJ_BTN_BUY)
        {
         ExecuteTrade(true);
         ObjectSetInteger(0, OBJ_BTN_BUY, OBJPROP_STATE, false);
        }
      else if(sparam == OBJ_BTN_SELL)
        {
         ExecuteTrade(false);
         ObjectSetInteger(0, OBJ_BTN_SELL, OBJPROP_STATE, false);
        }
      else if(sparam == OBJ_BTN_RESET)
        {
         PlaceLinesAtATRDistance();
         UpdatePanel();
         ObjectSetInteger(0, OBJ_BTN_RESET, OBJPROP_STATE, false);
        }
      ChartRedraw(0);
     }
}
//+------------------------------------------------------------------+
