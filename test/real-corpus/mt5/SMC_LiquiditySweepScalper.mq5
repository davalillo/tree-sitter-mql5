//+------------------------------------------------------------------+
//|                                 SMC_LiquiditySweepScalper.mq5    |
//|                                                                    |
//| PHASE 1 (MVP) of a Smart Money Concepts style scalper.             |
//|                                                                    |
//| Logic sequence per setup:                                          |
//|   1. Track the most recent unswept swing high and swing low        |
//|      (confirmed causally with a fractal-style lookback — no        |
//|      repainting).                                                  |
//|   2. Liquidity sweep: a closed bar wicks beyond that swing level    |
//|      but closes back on the other side of it (a stop-hunt).        |
//|   3. The sweep bar's body becomes the "Order Block" zone.           |
//|   4. Confirmation: a following bar must close back through the     |
//|      OB zone in the trade direction (a small Break of Structure)   |
//|      within InpMaxConfirmationBars bars, otherwise the setup        |
//|      expires with no trade.                                        |
//|   5. On confirmation: enter at market, SL beyond the sweep          |
//|      extreme, TP at a fixed multiple of the SL distance, sized by  |
//|      risk % of balance.                                            |
//|                                                                    |
//| What makes this different from a typical SMC indicator: every      |
//| trade this EA takes is tagged on the chart with the HISTORICAL      |
//| win rate of that setup type (bullish vs bearish) measured from      |
//| this EA's own closed trades so far, and the tag is updated with     |
//| WIN/LOSS once the trade closes. It's a running scorecard, not       |
//| just a box.                                                         |
//|                                                                    |
//| Known Phase 1 simplifications (by design, to keep this a testable  |
//| MVP):                                                               |
//|   - Only the single most recent swing high/low is tracked, not a   |
//|     full structure map.                                            |
//|   - One trade at a time — no new setup is evaluated while a         |
//|     position from this EA is open.                                 |
//|   - Success rate is tied to this EA's own trade outcomes (TP vs    |
//|     SL/close), not a separate theoretical zone-revisit tracker.     |
//|   - Written for netting accounts / one manually-managed symbol.     |
//|     Don't run other manual or EA trades on the same symbol at the  |
//|     same time, or position tracking can get confused.               |
//|                                                                    |
//| PHASE 1.5 UPDATE — after multi-pair/multi-timeframe backtests came |
//| back net negative, three fixes were made:                          |
//|   1. Fixed-point thresholds (sweep size, SL buffer) were replaced   |
//|      with ATR-based ones, so they scale to each symbol's own       |
//|      volatility instead of using one number for Gold and EURUSD    |
//|      alike.                                                        |
//|   2. A higher-timeframe trend filter was added: a sweep is only     |
//|      traded when it agrees with the higher-timeframe direction      |
//|      (price vs. an EMA). Counter-trend sweeps are far more likely   |
//|      to be continuation, not reversal, and were the main source     |
//|      of losses.                                                     |
//|   3. Two quality gates were added before entry: the resulting SL    |
//|      distance must be a meaningful multiple of ATR (filters noise)  |
//|      and a meaningful multiple of the current spread (filters       |
//|      setups where cost alone would erode the edge), and the         |
//|      confirmation candle must have a real range relative to ATR     |
//|      (filters weak, low-momentum breaks).                           |
//|                                                                    |
//| Test thoroughly on a demo account before considering real money.   |
//+------------------------------------------------------------------+
#property copyright "Article demo EA"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

input group "=== Swing / Structure ==="
input int              InpSwingLookback       = 5;      // Bars each side to confirm a swing high/low
input int              InpMaxConfirmationBars = 3;       // Bars allowed for confirmation after a sweep before setup expires

input group "=== Volatility (ATR-based, scales per symbol) ==="
input int              InpATRPeriod           = 14;      // ATR period
input double           InpMinSweepATRMult     = 0.15;    // Minimum sweep distance beyond swing level, as a multiple of ATR
input double           InpSLBufferATRMult     = 0.10;    // Extra SL buffer beyond the sweep extreme, as a multiple of ATR
input double           InpMinSLToATRMult      = 0.50;    // Reject setup if resulting SL distance is smaller than this multiple of ATR
input double           InpMinSLToSpreadRatio  = 3.0;     // Reject setup if SL distance is less than (spread x this ratio)

input group "=== Higher-Timeframe Bias Filter ==="
input bool             InpUseTrendFilter      = true;        // Only trade in the direction of the higher-timeframe trend
input ENUM_TIMEFRAMES  InpTrendTimeframe      = PERIOD_H1;    // Higher timeframe used for trend bias
input int              InpTrendMAPeriod       = 50;           // EMA period on the trend timeframe

input group "=== Confirmation Quality ==="
input double           InpMinConfirmRangeATRMult = 0.30;   // Confirmation candle's range must be at least this multiple of ATR

input group "=== Trade Management ==="
input double           InpRiskPercent         = 1.0;      // Risk % of balance per trade
input double           InpRewardRatio         = 2.0;      // Take profit as a multiple of the stop loss distance
input int              InpMaxSpreadPoints     = 25;       // Skip entry if current spread exceeds this (points)
input int              InpSlippagePoints      = 10;       // Max allowed slippage (points)
input ulong            InpMagicNumber         = 552001;   // Magic number

input group "=== Session Filter (broker/server time) ==="
input bool             InpUseSessionFilter    = false;    // Restrict new setups to a server-time window
input int              InpSessionStartHour    = 7;        // Session start hour (0-23)
input int              InpSessionEndHour      = 20;       // Session end hour (0-23)

input group "=== Display ==="
input bool             InpDrawOnChart         = true;     // Draw order block zones + live win-rate on chart

// ---- swing state ----
double   g_lastSwingHighPrice = 0.0;
bool     g_lastSwingHighSwept = true;
double   g_lastSwingLowPrice  = 0.0;
bool     g_lastSwingLowSwept  = true;

// ---- pending setup state (awaiting confirmation) ----
bool     g_pendingActive      = false;
bool     g_pendingIsBuy       = false;
double   g_pendingObHigh      = 0.0;
double   g_pendingObLow       = 0.0;
double   g_pendingSweepExtreme= 0.0;
int      g_pendingBarsWaited  = 0;

// ---- active trade state ----
ulong    g_activeTicket       = 0;
bool     g_activeIsBuy        = false;
string   g_activeRectName     = "";
string   g_activeLabelName    = "";

// ---- scorecard ----
int g_bullTotal = 0, g_bullWins = 0;
int g_bearTotal = 0, g_bearWins = 0;

datetime g_lastBarTime = 0;

// ---- indicator handles ----
int g_atrHandle     = INVALID_HANDLE;
int g_trendMAHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == (long)InpMagicNumber)
     {
      g_activeTicket = (ulong)PositionGetInteger(POSITION_TICKET);
      g_activeIsBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
     }

   g_atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("Failed to create ATR indicator handle.");
      return(INIT_FAILED);
     }

   if(InpUseTrendFilter)
     {
      g_trendMAHandle = iMA(_Symbol, InpTrendTimeframe, InpTrendMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_trendMAHandle == INVALID_HANDLE)
        {
         Print("Failed to create trend EMA indicator handle.");
         return(INIT_FAILED);
        }
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   if(g_trendMAHandle != INVALID_HANDLE)
      IndicatorRelease(g_trendMAHandle);
   Comment("");
  }

//+------------------------------------------------------------------+
double GetPoint() { return SymbolInfoDouble(_Symbol, SYMBOL_POINT); }

//+------------------------------------------------------------------+
double ValuePerPoint(const string symbol)
  {
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(tickSize <= 0.0)
      return 0.0;
   return tickValue * (point / tickSize);
  }

//+------------------------------------------------------------------+
double NormalizeLot(double lot, const string symbol)
  {
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      return 0.0;

   lot = MathFloor(lot / step) * step;
   if(lot > maxLot)
      lot = maxLot;
   if(lot < minLot)
      lot = 0.0;
   return NormalizeDouble(lot, 2);
  }

//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime t = iTime(_Symbol, _Period, 0);
   if(t != g_lastBarTime)
     {
      g_lastBarTime = t;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
bool InSession()
  {
   if(!InpUseSessionFilter)
      return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(InpSessionStartHour <= InpSessionEndHour)
      return (dt.hour >= InpSessionStartHour && dt.hour < InpSessionEndHour);

   return (dt.hour >= InpSessionStartHour || dt.hour < InpSessionEndHour);
  }

//+------------------------------------------------------------------+
double GetATR()
  {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_atrHandle, 0, 1, 1, buf) < 1)
      return 0.0;
   return buf[0];
  }

//+------------------------------------------------------------------+
//| Higher-timeframe bias: only allow trades that agree with it       |
//+------------------------------------------------------------------+
bool TrendAllowsBuy()
  {
   if(!InpUseTrendFilter)
      return true;
   double ma[];
   ArraySetAsSeries(ma, true);
   if(CopyBuffer(g_trendMAHandle, 0, 0, 1, ma) < 1)
      return true; // fail-open if the indicator has no data yet
   double htfClose = iClose(_Symbol, InpTrendTimeframe, 0);
   return htfClose > ma[0];
  }

bool TrendAllowsSell()
  {
   if(!InpUseTrendFilter)
      return true;
   double ma[];
   ArraySetAsSeries(ma, true);
   if(CopyBuffer(g_trendMAHandle, 0, 0, 1, ma) < 1)
      return true;
   double htfClose = iClose(_Symbol, InpTrendTimeframe, 0);
   return htfClose < ma[0];
  }

//+------------------------------------------------------------------+
//| Confirm the most recent swing high/low using closed bars only     |
//+------------------------------------------------------------------+
void UpdateSwingPoints()
  {
   int need = InpSwingLookback * 2 + 5;

   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);

   if(CopyHigh(_Symbol, _Period, 0, need, highs) < need)
      return;
   if(CopyLow(_Symbol, _Period, 0, need, lows) < need)
      return;

   int pivot = InpSwingLookback + 1;

   bool isHigh = true;
   bool isLow  = true;
   for(int k = 1; k <= InpSwingLookback; k++)
     {
      if(highs[pivot - k] > highs[pivot] || highs[pivot + k] > highs[pivot])
         isHigh = false;
      if(lows[pivot - k] < lows[pivot] || lows[pivot + k] < lows[pivot])
         isLow = false;
     }

   if(isHigh)
     {
      g_lastSwingHighPrice = highs[pivot];
      g_lastSwingHighSwept = false;
     }
   if(isLow)
     {
      g_lastSwingLowPrice = lows[pivot];
      g_lastSwingLowSwept = false;
     }
  }

//+------------------------------------------------------------------+
//| Look for a fresh liquidity sweep and open a pending setup          |
//+------------------------------------------------------------------+
void CheckForNewSweep()
  {
   if(!InSession())
      return;

   double atr = GetATR();
   if(atr <= 0.0)
      return;

   double minSweepDist = InpMinSweepATRMult * atr;

   double high1  = iHigh(_Symbol, _Period, 1);
   double low1   = iLow(_Symbol, _Period, 1);
   double open1  = iOpen(_Symbol, _Period, 1);
   double close1 = iClose(_Symbol, _Period, 1);

   // Bearish sweep of buy-side liquidity (a market fact, independent of the trend filter)
   if(!g_lastSwingHighSwept && g_lastSwingHighPrice > 0.0
      && high1 > g_lastSwingHighPrice + minSweepDist
      && close1 < g_lastSwingHighPrice)
     {
      g_lastSwingHighSwept = true;
      if(TrendAllowsSell())
        {
         g_pendingActive       = true;
         g_pendingIsBuy        = false;
         g_pendingObHigh       = MathMax(open1, close1);
         g_pendingObLow        = MathMin(open1, close1);
         g_pendingSweepExtreme = high1;
         g_pendingBarsWaited   = 0;
        }
      return;
     }

   // Bullish sweep of sell-side liquidity
   if(!g_lastSwingLowSwept && g_lastSwingLowPrice > 0.0
      && low1 < g_lastSwingLowPrice - minSweepDist
      && close1 > g_lastSwingLowPrice)
     {
      g_lastSwingLowSwept = true;
      if(TrendAllowsBuy())
        {
         g_pendingActive       = true;
         g_pendingIsBuy        = true;
         g_pendingObHigh       = MathMax(open1, close1);
         g_pendingObLow        = MathMin(open1, close1);
         g_pendingSweepExtreme = low1;
         g_pendingBarsWaited   = 0;
        }
     }
  }

//+------------------------------------------------------------------+
//| Wait for a Break-of-Structure confirmation, then enter            |
//+------------------------------------------------------------------+
void CheckConfirmationAndEnter()
  {
   g_pendingBarsWaited++;
   if(g_pendingBarsWaited > InpMaxConfirmationBars)
     {
      g_pendingActive = false;
      return;
     }

   double close1 = iClose(_Symbol, _Period, 1);
   double high1  = iHigh(_Symbol, _Period, 1);
   double low1   = iLow(_Symbol, _Period, 1);

   bool confirmed = g_pendingIsBuy ? (close1 > g_pendingObHigh) : (close1 < g_pendingObLow);
   if(!confirmed)
      return;

   double atr = GetATR();
   if(atr <= 0.0)
     {
      g_pendingActive = false;
      return;
     }

   double confirmRange = high1 - low1;
   if(confirmRange < InpMinConfirmRangeATRMult * atr)
     {
      Print("Setup skipped: confirmation candle too weak relative to ATR (low-momentum break).");
      g_pendingActive = false;
      return;
     }

   double spreadPoints = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spreadPoints > InpMaxSpreadPoints)
     {
      PrintFormat("Setup skipped: spread %.0f points exceeds limit %d", spreadPoints, InpMaxSpreadPoints);
      g_pendingActive = false;
      return;
     }

   double point = GetPoint();
   double price = g_pendingIsBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slBuffer = InpSLBufferATRMult * atr;
   double sl = g_pendingIsBuy ? (g_pendingSweepExtreme - slBuffer) : (g_pendingSweepExtreme + slBuffer);

   double slDist = MathAbs(price - sl);

   if(slDist < InpMinSLToATRMult * atr)
     {
      Print("Setup skipped: stop loss distance too small relative to ATR (likely noise).");
      g_pendingActive = false;
      return;
     }
   if(slDist < spreadPoints * point * InpMinSLToSpreadRatio)
     {
      Print("Setup skipped: stop loss distance too small relative to spread (cost would dominate the edge).");
      g_pendingActive = false;
      return;
     }

   double slDistPoints = slDist / point;
   double tp = g_pendingIsBuy ? (price + slDist * InpRewardRatio) : (price - slDist * InpRewardRatio);

   double valuePerPoint = ValuePerPoint(_Symbol);
   if(valuePerPoint <= 0.0 || slDistPoints <= 0.0)
     {
      g_pendingActive = false;
      return;
     }

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;
   double lot        = NormalizeLot(riskAmount / (slDistPoints * valuePerPoint), _Symbol);

   if(lot <= 0.0)
     {
      Print("Setup skipped: calculated lot size is 0 (risk too small for this symbol's minimum lot).");
      g_pendingActive = false;
      return;
     }

   bool sent = g_pendingIsBuy ? trade.Buy(lot, _Symbol, price, sl, tp, "SMC-Scalper")
                              : trade.Sell(lot, _Symbol, price, sl, tp, "SMC-Scalper");

   if(sent)
     {
      if(PositionSelect(_Symbol))
         g_activeTicket = (ulong)PositionGetInteger(POSITION_TICKET);
      g_activeIsBuy = g_pendingIsBuy;

      DrawSetup(g_pendingIsBuy);
      PrintFormat("Entered %s at %.5f, SL %.5f, TP %.5f, lot %.2f",
                  g_pendingIsBuy ? "BUY" : "SELL", price, sl, tp, lot);
     }
   else
      PrintFormat("Order failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());

   g_pendingActive = false;
  }

//+------------------------------------------------------------------+
//| Check whether our open position has closed, and score it          |
//+------------------------------------------------------------------+
void ManageOpenPosition()
  {
   if(g_activeTicket == 0)
      return;
   if(PositionSelectByTicket(g_activeTicket))
      return; // still open

   double netProfit = 0.0;
   if(HistorySelectByPosition(g_activeTicket))
     {
      int deals = HistoryDealsTotal();
      for(int i = 0; i < deals; i++)
        {
         ulong dticket = HistoryDealGetTicket(i);
         netProfit += HistoryDealGetDouble(dticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(dticket, DEAL_SWAP)
                    + HistoryDealGetDouble(dticket, DEAL_COMMISSION);
        }
     }

   bool win = netProfit > 0.0;
   if(g_activeIsBuy)
     {
      g_bullTotal++;
      if(win) g_bullWins++;
     }
   else
     {
      g_bearTotal++;
      if(win) g_bearWins++;
     }

   PrintFormat("Setup closed: %s  net %.2f -> %s",
               g_activeIsBuy ? "BULLISH OB" : "BEARISH OB", netProfit, win ? "WIN" : "LOSS");
   PrintStats();
   UpdateSetupLabel(win);

   g_activeTicket    = 0;
   g_activeRectName  = "";
   g_activeLabelName = "";
  }

//+------------------------------------------------------------------+
void PrintStats()
  {
   double bullRate = (g_bullTotal > 0) ? 100.0 * g_bullWins / g_bullTotal : 0.0;
   double bearRate = (g_bearTotal > 0) ? 100.0 * g_bearWins / g_bearTotal : 0.0;

   string msg = StringFormat("Bullish OB setups: %d (%d wins, %.1f%%) | Bearish OB setups: %d (%d wins, %.1f%%)",
                              g_bullTotal, g_bullWins, bullRate, g_bearTotal, g_bearWins, bearRate);
   Print(msg);
   if(InpDrawOnChart)
      Comment(msg);
  }

//+------------------------------------------------------------------+
//| Draw the OB zone + a label showing the PRIOR historical win rate  |
//| for this setup type (before this trade's own outcome is known)    |
//+------------------------------------------------------------------+
void DrawSetup(bool isBuy)
  {
   if(!InpDrawOnChart)
      return;

   int total = isBuy ? g_bullTotal : g_bearTotal;
   int wins  = isBuy ? g_bullWins  : g_bearWins;
   double winRate = (total > 0) ? (100.0 * wins / total) : 0.0;

   string rectName  = StringFormat("SMC_OB_%d", (int)TimeCurrent());
   string labelName = rectName + "_lbl";

   datetime t1 = iTime(_Symbol, _Period, 1);
   datetime t2 = iTime(_Symbol, _Period, 0) + PeriodSeconds(_Period) * (InpMaxConfirmationBars + 1);
   color boxColor = isBuy ? clrLimeGreen : clrTomato;

   ObjectCreate(0, rectName, OBJ_RECTANGLE, 0, t1, g_pendingObHigh, t2, g_pendingObLow);
   ObjectSetInteger(0, rectName, OBJPROP_COLOR, boxColor);
   ObjectSetInteger(0, rectName, OBJPROP_FILL, true);
   ObjectSetInteger(0, rectName, OBJPROP_BACK, true);

   string text = StringFormat("%s OB | prior win-rate: %.0f%% (%d/%d)",
                               isBuy ? "Bullish" : "Bearish", winRate, wins, total);
   ObjectCreate(0, labelName, OBJ_TEXT, 0, t1, isBuy ? g_pendingObLow : g_pendingObHigh);
   ObjectSetString(0, labelName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);

   g_activeRectName  = rectName;
   g_activeLabelName = labelName;
  }

//+------------------------------------------------------------------+
void UpdateSetupLabel(bool win)
  {
   if(!InpDrawOnChart || g_activeLabelName == "")
      return;

   if(ObjectFind(0, g_activeLabelName) >= 0)
     {
      string current = ObjectGetString(0, g_activeLabelName, OBJPROP_TEXT);
      ObjectSetString(0, g_activeLabelName, OBJPROP_TEXT, current + (win ? "  -> WIN" : "  -> LOSS"));
     }
   if(g_activeRectName != "" && ObjectFind(0, g_activeRectName) >= 0)
      ObjectSetInteger(0, g_activeRectName, OBJPROP_COLOR, win ? clrLimeGreen : clrGray);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(!IsNewBar())
      return;

   ManageOpenPosition();
   if(g_activeTicket != 0)
      return;

   UpdateSwingPoints();

   if(g_pendingActive)
      CheckConfirmationAndEnter();
   else
      CheckForNewSweep();
  }
//+------------------------------------------------------------------+
