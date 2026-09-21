//+------------------------------------------------------------------+
//|                                      OneClickTradeManager.mq5    |
//|  Risk-based position sizing with one-click entry.                 |
//|                                                                   |
//|  The panel works out the lot from your risk percent and the stop  |
//|  distance, then opens the trade with the stop and target already  |
//|  attached. It never opens a trade on its own: every order comes   |
//|  from a button you press, and every rule is an input.             |
//+------------------------------------------------------------------+
#property copyright "Brain Grain"
#property link      "https://www.mql5.com/en/users/amul1"
#property version   "1.00"
#property description "Position-size calculator and one-click entry panel. The lot is worked out from your risk percent and the stop distance, so the risk is the same whatever symbol you trade."
#property description "BUY and SELL open at market with the stop loss and take profit already attached. Stop by fixed points or ATR; target as a multiple of the stop."
#property description "Never trades by itself. Rounds the lot DOWN to the volume step, respects the broker stop level, and handles netting accounts."

#include <Trade\Trade.mqh>

//--- risk -----------------------------------------------------------
input group             "Risk"
input double   InpRiskPercent    = 1.0;    // Risk per trade (% of balance)
input double   InpMaxLot         = 0.0;    // Hard lot cap (0 = broker maximum)
input int      InpMaxSpreadPts   = 0;      // Refuse entry above this spread in points (0 = off)

//--- stop and target ------------------------------------------------
input group             "Stop and target"
input bool     InpUseATR         = false;  // Size the stop from ATR instead of fixed points
input int      InpATRPeriod      = 14;     // ATR period
input double   InpATRMult        = 1.5;    // ATR multiplier
input int      InpSLPoints       = 200;    // Fixed stop distance (points) when ATR is off
input double   InpRR             = 2.0;    // Take profit as a multiple of the stop (0 = no TP)

//--- order ----------------------------------------------------------
input group             "Order"
input ulong    InpMagic          = 990201; // Magic number for this panel's orders
input int      InpSlippagePts    = 20;     // Maximum slippage (points)

//--- panel ----------------------------------------------------------
input group             "Panel"
input int      InpPanelX         = 12;     // Panel X (pixels from the corner)
input int      InpPanelY         = 22;     // Panel Y (pixels from the corner)
input int      InpFontSize       = 9;      // Panel font size
input color    InpTextColor      = clrGainsboro;
input color    InpAccentColor    = clrGold;
input color    InpPanelBg        = C'22,26,34';

//--- self test ------------------------------------------------------
input group             "Self test"
input bool     InpSelfTest       = false;  // Strategy Tester only: exercise the panel and report

//--- objects --------------------------------------------------------
#define PFX      "OCTM_"
#define BTN_BUY  PFX "btn_buy"
#define BTN_SELL PFX "btn_sell"

CTrade   trade;
int      atrHandle   = INVALID_HANDLE;
string   lastMessage = "";
color    lastMsgColor;
bool     isNetting   = false;
int      testStep    = 0;
int      testPass    = 0;
int      testFail    = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   isNetting = ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)
                == ACCOUNT_MARGIN_MODE_RETAIL_NETTING);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePts);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(InpUseATR)
     {
      atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
      if(atrHandle == INVALID_HANDLE)
         Print("OCTM: could not create the ATR handle — falling back to fixed points");
     }

   BuildPanel();
   EventSetTimer(1);
   Say("ready", InpAccentColor);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0, PFX);
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   Refresh();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   Refresh();
   if(InpSelfTest && MQLInfoInteger(MQL_TESTER))
      RunSelfTest();
  }

//+------------------------------------------------------------------+
//| Every order starts here — a human pressing a button.             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == BTN_BUY)       DoEntry(ORDER_TYPE_BUY);
   else if(sparam == BTN_SELL) DoEntry(ORDER_TYPE_SELL);
   else return;

   // A button that stays pressed looks broken; release it immediately.
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   Refresh();
  }

//+------------------------------------------------------------------+
//| Stop distance in points, from ATR or the fixed input.            |
//+------------------------------------------------------------------+
int StopPoints()
  {
   if(InpUseATR && atrHandle != INVALID_HANDLE)
     {
      double buf[];
      if(CopyBuffer(atrHandle, 0, 0, 1, buf) == 1 && buf[0] > 0.0)
        {
         int pts = (int)MathRound(buf[0] * InpATRMult / _Point);
         if(pts > 0)
            return(pts);
        }
     }
   return(InpSLPoints);
  }

//+------------------------------------------------------------------+
//| The broker will not accept a stop closer than this.              |
//+------------------------------------------------------------------+
int MinStopPoints()
  {
   long stops  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return((int)MathMax(MathMax(stops, freeze), spread) + 1);
  }

//+------------------------------------------------------------------+
//| Lot size so that `stop` points of loss equals the risk percent.  |
//| Clamped by the broker's step/min/max, the input cap and margin.  |
//+------------------------------------------------------------------+
double RiskLot(const int stopPts, string &why)
  {
   why = "";
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double step      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(tickValue <= 0.0 || tickSize <= 0.0 || step <= 0.0 || stopPts <= 0)
     {
      why = "symbol data unavailable";
      return(0.0);
     }

   double riskMoney  = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double lossPerLot = (stopPts * _Point / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
     {
      why = "cannot price the stop";
      return(0.0);
     }

   double lot = riskMoney / lossPerLot;
   lot = MathFloor(lot / step) * step;                       // never round risk UP

   if(InpMaxLot > 0.0)
      lot = MathMin(lot, InpMaxLot);
   lot = MathMin(lot, maxLot);

   // The volume limit is a separate ceiling from the maximum lot, and brokers
   // do enforce it.
   double volLimit = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);
   if(volLimit > 0.0)
      lot = MathMin(lot, volLimit);

   if(lot < minLot)
     {
      why = StringFormat("risk %.2f%% is smaller than one minimum lot", InpRiskPercent);
      return(0.0);
     }

   // Margin last: a lot we cannot afford is worse than a smaller one.
   double margin = 0.0;
   double price  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, price, margin) && margin > 0.0)
     {
      double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9;
      if(margin > free)
        {
         double affordable = MathFloor((lot * free / margin) / step) * step;
         if(affordable < minLot)
           {
            why = "not enough free margin";
            return(0.0);
           }
         lot = affordable;
         why = "reduced to fit free margin";
        }
     }
   return(NormalizeDouble(lot, 2));
  }

//+------------------------------------------------------------------+
void DoEntry(const ENUM_ORDER_TYPE type)
  {
   if(InpMaxSpreadPts > 0 && (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPts)
     {
      Say("spread too wide — no entry", clrTomato);
      return;
     }

   // On a netting account an opposite deal reduces the position instead of
   // opening one, and the stop cannot attach to what is left. Say so rather
   // than send an order that half-works.
   if(isNetting && PositionSelect(_Symbol))
     {
      long ptype = PositionGetInteger(POSITION_TYPE);
      bool opposite = (type == ORDER_TYPE_BUY  && ptype == POSITION_TYPE_SELL)
                   || (type == ORDER_TYPE_SELL && ptype == POSITION_TYPE_BUY);
      if(opposite)
        {
         Say("netting: close the open position first", clrTomato);
         return;
        }
     }

   int stopPts = StopPoints();
   int minPts  = MinStopPoints();
   if(stopPts < minPts)
     {
      stopPts = minPts;
      Say("stop widened to the broker minimum", clrOrange);
     }

   string why;
   double lot = RiskLot(stopPts, why);
   if(lot <= 0.0)
     {
      Say(why == "" ? "lot came out zero" : why, clrTomato);
      return;
     }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    dig = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double price = (type == ORDER_TYPE_BUY) ? ask : bid;
   double sl, tp = 0.0;
   if(type == ORDER_TYPE_BUY)
     {
      sl = NormalizeDouble(price - stopPts * _Point, dig);
      if(InpRR > 0.0)
         tp = NormalizeDouble(price + stopPts * InpRR * _Point, dig);
     }
   else
     {
      sl = NormalizeDouble(price + stopPts * _Point, dig);
      if(InpRR > 0.0)
         tp = NormalizeDouble(price - stopPts * InpRR * _Point, dig);
     }

   bool ok = (type == ORDER_TYPE_BUY)
             ? trade.Buy(lot, _Symbol, 0.0, sl, tp, "OCTM")
             : trade.Sell(lot, _Symbol, 0.0, sl, tp, "OCTM");

   if(ok)
      Say(StringFormat("%s %.2f lots, stop %d pts%s",
                       (type == ORDER_TYPE_BUY ? "bought" : "sold"), lot, stopPts,
                       (why == "" ? "" : " (" + why + ")")), clrLimeGreen);
   else
      Say(StringFormat("rejected: %s (%d)", trade.ResultRetcodeDescription(), trade.ResultRetcode()), clrTomato);
  }

//+------------------------------------------------------------------+
//| Panel                                                            |
//+------------------------------------------------------------------+
void Label(const string name, const int x, const int y, const string text,
           const color clr, const int size)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

//+------------------------------------------------------------------+
void Button(const string name, const int x, const int y, const int w, const int h,
            const string text, const color bg)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

//+------------------------------------------------------------------+
void BuildPanel()
  {
   int x = InpPanelX, y = InpPanelY;
   int rowH = InpFontSize + 9;

   string bgName = PFX "bg";
   if(ObjectFind(0, bgName) < 0)
     {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bgName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bgName, OBJPROP_COLOR, InpAccentColor);
      ObjectSetInteger(0, bgName, OBJPROP_WIDTH, 1);
     }

   int by = y + rowH * 5 + 6;
   int bw = 134, bh = 26;
   Button(BTN_BUY,  x,          by, bw, bh, "BUY",  C'22,101,52');
   Button(BTN_SELL, x + bw + 6, by, bw, bh, "SELL", C'136,32,42');

   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, x - 8);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, y - 8);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, bw * 2 + 6 + 16);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, (by + bh + 12) - (y - 8));
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, InpPanelBg);

   Refresh();
  }

//+------------------------------------------------------------------+
void Refresh()
  {
   int x = InpPanelX, y = InpPanelY;
   int rowH = InpFontSize + 9;

   int    stopPts = StopPoints();
   int    minPts  = MinStopPoints();
   int    usePts  = MathMax(stopPts, minPts);
   string why;
   double lot     = RiskLot(usePts, why);
   double risk    = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   int    spread  = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   double openVol = 0.0, openPL = 0.0;
   int    openN = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      openN++;
      openVol += PositionGetDouble(POSITION_VOLUME);
      openPL  += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }

   Label(PFX "l0", x, y, StringFormat("POSITION SIZE + ENTRY  %s", _Symbol), InpAccentColor, InpFontSize);
   Label(PFX "l1", x, y + rowH,
         StringFormat("Risk  %.2f%%  = %.2f %s", InpRiskPercent, risk, AccountInfoString(ACCOUNT_CURRENCY)),
         InpTextColor, InpFontSize);
   Label(PFX "l2", x, y + rowH * 2,
         StringFormat("Stop  %d pts%s   Target %s", usePts,
                      (InpUseATR ? StringFormat(" (ATR x%.1f)", InpATRMult) : ""),
                      (InpRR > 0.0 ? StringFormat("%.1fR", InpRR) : "off")),
         InpTextColor, InpFontSize);
   Label(PFX "l3", x, y + rowH * 3,
         (lot > 0.0 ? StringFormat("Lot   %.2f        Spread %d pts", lot, spread)
                    : StringFormat("Lot   -- (%s)", why)),
         (lot > 0.0 ? InpTextColor : clrTomato), InpFontSize);
   Label(PFX "l4", x, y + rowH * 4,
         StringFormat("Open  %d  %.2f lots   P/L %.2f", openN, openVol, openPL),
         (openPL >= 0.0 ? InpTextColor : clrTomato), InpFontSize);
   Label(PFX "l5", x, y + rowH * 5 - 2, lastMessage, lastMsgColor, InpFontSize);

   ChartRedraw();
  }

//+------------------------------------------------------------------+
void Say(const string text, const color clr)
  {
   lastMessage  = text;
   lastMsgColor = clr;
   if(MQLInfoInteger(MQL_TESTER))
      Print("OCTM: ", text);
  }

//+------------------------------------------------------------------+
//| Self test — Strategy Tester only. Exercises the calculator and   |
//| the entry path and prints a PASS/FAIL line for each check, so a  |
//| change that breaks one of them cannot pass quietly.              |
//+------------------------------------------------------------------+
void Check(const string name, const bool ok)
  {
   if(ok)
     {
      testPass++;
      PrintFormat("SELFTEST PASS  %s", name);
     }
   else
     {
      testFail++;
      PrintFormat("SELFTEST FAIL  %s", name);
     }
  }

//+------------------------------------------------------------------+
void RunSelfTest()
  {
   static datetime lastStep = 0;
   if(TimeCurrent() - lastStep < 60)      // one step a minute of tester time
      return;
   lastStep = TimeCurrent();

   switch(testStep)
     {
      case 0:
        {
         string why;
         double lot  = RiskLot(StopPoints(), why);
         double wide = RiskLot(StopPoints() * 2, why);
         double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         Check("lot sizing returns a tradeable volume", lot > 0.0);
         Check("a wider stop gives a smaller lot", wide > 0.0 && wide <= lot);
         Check("the lot sits on the broker volume step",
               MathAbs(lot / step - MathRound(lot / step)) < 0.0001);
         break;
        }
      case 1:
         DoEntry(ORDER_TYPE_BUY);
         Check("buy opened a position", PositionsTotal() > 0);
         break;
      case 2:
        {
         bool hasSL = false, hasTP = true;
         if(PositionSelect(_Symbol))
           {
            hasSL = (PositionGetDouble(POSITION_SL) > 0.0);
            if(InpRR > 0.0)
               hasTP = (PositionGetDouble(POSITION_TP) > 0.0);
           }
         Check("the position carries a stop loss", hasSL);
         Check("the position carries a take profit", hasTP);
         break;
        }
      case 3:
        {
         // The risk actually taken must match the risk asked for. This is the
         // whole promise of the tool, so it is asserted rather than assumed.
         bool sane = false;
         if(PositionSelect(_Symbol))
           {
            double vol   = PositionGetDouble(POSITION_VOLUME);
            double open  = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl    = PositionGetDouble(POSITION_SL);
            double tv    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
            double ts    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
            double loss  = MathAbs(open - sl) / ts * tv * vol;
            double asked = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
            sane = (loss <= asked * 1.05);
            PrintFormat("OCTM: risk if stopped %.2f vs risk asked %.2f", loss, asked);
           }
         Check("the open risk does not exceed the risk asked for", sane);
         break;
        }
      case 4:
         PrintFormat("SELFTEST DONE  %d passed, %d failed", testPass, testFail);
         break;
      default:
         return;
     }
   testStep++;
  }
//+------------------------------------------------------------------+
