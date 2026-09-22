//+------------------------------------------------------------------+
//|                         Supertrend_MTF_Dragan.mq4                |
//|                         Copyright 2026, Dragan Joksimovic        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Dragan Joksimovic"
#property version   "1.00"
#property strict
#property description "MTF ATR Supertrend with trend lines, confirmed arrows and alerts."
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_color1 clrLimeGreen
#property indicator_color2 clrTomato
#property indicator_color3 clrDodgerBlue
#property indicator_color4 clrOrangeRed
#property indicator_width1 2
#property indicator_width2 2

//--- MTF and calculation inputs ------------------------------------
input ENUM_TIMEFRAMES InpTimeframe          = PERIOD_CURRENT; // Supertrend timeframe
input int             InpAtrPeriod          = 10;             // ATR period
input double          InpMultiplier         = 3.0;            // ATR multiplier
input int             InpMaxBarsToCalculate = 5000;           // Calculation history

//--- visual inputs -------------------------------------------------
input color           InpUpColor            = clrLimeGreen;   // Uptrend line
input color           InpDownColor          = clrTomato;      // Downtrend line
input int             InpLineWidth          = 2;              // Trend line width
input bool            InpShowArrows         = true;           // Show confirmed reversal arrows
input color           InpBuyArrowColor      = clrDodgerBlue;  // BUY arrow color
input color           InpSellArrowColor     = clrOrangeRed;   // SELL arrow color
input double          InpArrowOffsetPips    = 3.0;            // Arrow distance from candle

//--- alert inputs --------------------------------------------------
input bool            InpAlertPopup         = false;          // Pop-up alert
input bool            InpAlertPush          = false;          // Push notification
input bool            InpAlertEmail         = false;          // E-mail alert

//--- visible buffers -----------------------------------------------
double BufUp[];       // 0: Supertrend line during an uptrend
double BufDown[];     // 1: Supertrend line during a downtrend
double BufBuy[];      // 2: confirmed BUY reversal arrow
double BufSell[];     // 3: confirmed SELL reversal arrow
double BufState[];    // 4: hidden state: +1 up, -1 down

//--- selected-timeframe calculation arrays ------------------------
double g_tfUp[];
double g_tfDown[];
double g_tfState[];
double g_tfFinalUpper[];
double g_tfFinalLower[];

int      g_tf               = 0;
int      g_tfCalcBars       = 0;
datetime g_tfTime0          = 0;
datetime g_lastAlertTime    = 0;
double   g_pip              = 0.0;

//+------------------------------------------------------------------+
string TfName(int tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
   }
   return "TF" + IntegerToString(tf);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpAtrPeriod < 1)
   {
      Print("Supertrend: InpAtrPeriod must be at least 1.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpMultiplier <= 0.0)
   {
      Print("Supertrend: InpMultiplier must be greater than zero.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpMaxBarsToCalculate < InpAtrPeriod + 5)
   {
      Print("Supertrend: InpMaxBarsToCalculate is too small.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_tf = (int)InpTimeframe;
   if(g_tf == 0)
      g_tf = Period();

   // Same MTF rule as the channel indicator: do not use a TF lower
   // than the chart because one chart bar cannot display it correctly.
   if(g_tf < Period())
   {
      Print("Supertrend: selected timeframe ", TfName(g_tf),
            " is lower than the chart; using ", TfName(Period()), ".");
      g_tf = Period();
   }

   g_pip = ((_Digits == 3 || _Digits == 5) ? 10 : 1) * _Point;

   SetIndexBuffer(0, BufUp);
   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, InpLineWidth, InpUpColor);
   SetIndexLabel(0, "Supertrend Up");

   SetIndexBuffer(1, BufDown);
   SetIndexStyle(1, DRAW_LINE, STYLE_SOLID, InpLineWidth, InpDownColor);
   SetIndexLabel(1, "Supertrend Down");

   SetIndexBuffer(2, BufBuy);
   SetIndexStyle(2, InpShowArrows ? DRAW_ARROW : DRAW_NONE, STYLE_SOLID, 1, InpBuyArrowColor);
   SetIndexArrow(2, 233);
   SetIndexLabel(2, "Supertrend BUY");

   SetIndexBuffer(3, BufSell);
   SetIndexStyle(3, InpShowArrows ? DRAW_ARROW : DRAW_NONE, STYLE_SOLID, 1, InpSellArrowColor);
   SetIndexArrow(3, 234);
   SetIndexLabel(3, "Supertrend SELL");

   SetIndexBuffer(4, BufState);
   SetIndexStyle(4, DRAW_NONE);
   SetIndexLabel(4, "Supertrend state (+1 / -1)");

   ArraySetAsSeries(BufUp, true);
   ArraySetAsSeries(BufDown, true);
   ArraySetAsSeries(BufBuy, true);
   ArraySetAsSeries(BufSell, true);
   ArraySetAsSeries(BufState, true);

   for(int b = 0; b < 5; b++)
      SetIndexEmptyValue(b, EMPTY_VALUE);

   IndicatorDigits(_Digits);
   IndicatorShortName(StringFormat("Supertrend MTF (%d, %.2f, %s)",
                                   InpAtrPeriod, InpMultiplier, TfName(g_tf)));

   g_tfCalcBars    = 0;
   g_tfTime0       = 0;
   g_lastAlertTime = 0;
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   if(rates_total < 2)
      return 0;

   int availableTfBars = iBars(_Symbol, g_tf);
   if(availableTfBars < InpAtrPeriod + 3)
      return 0;

   int calcBars = availableTfBars;
   if(calcBars > InpMaxBarsToCalculate)
      calcBars = InpMaxBarsToCalculate;

   datetime tfTime0 = iTime(_Symbol, g_tf, 0);
   if(tfTime0 <= 0)
      return 0;

   bool fullRebuild = (prev_calculated <= 0 || prev_calculated > rates_total ||
                       g_tfCalcBars != calcBars || g_tfTime0 != tfTime0);

   if(fullRebuild)
      CalculateAllTfBars(calcBars);
   else
      UpdateCurrentTfBar();

   g_tfTime0 = tfTime0;

   int limit;
   if(prev_calculated <= 0 || prev_calculated > rates_total)
   {
      limit = rates_total - 1;
   }
   else
   {
      // Refresh all chart bars belonging to the forming MTF bar and
      // a few bars behind it so the latest confirmed arrow is updated.
      int tfStart = iBarShift(_Symbol, Period(), tfTime0, false);
      if(tfStart < 0) tfStart = 0;
      limit = tfStart + 2;

      int newChartBars = rates_total - prev_calculated;
      if(newChartBars > limit)
         limit = newChartBars;
      if(limit > rates_total - 1)
         limit = rates_total - 1;
   }

   for(int i = limit; i >= 0; i--)
   {
      int shift = iBarShift(_Symbol, g_tf, time[i], false);
      if(shift < 0 || shift >= g_tfCalcBars || g_tfState[shift] == 0.0)
      {
         SetEmpty(i);
         continue;
      }

      BufUp[i]    = g_tfUp[shift];
      BufDown[i]  = g_tfDown[shift];
      BufState[i] = g_tfState[shift];
      BufBuy[i]   = EMPTY_VALUE;
      BufSell[i]  = EMPTY_VALUE;

      // Put a reversal arrow on the last chart candle of a CLOSED
      // selected-timeframe candle. The current MTF candle gets no arrow.
      if(InpShowArrows && shift >= 1 && i >= 1 && shift + 1 < g_tfCalcBars)
      {
         int newerShift = iBarShift(_Symbol, g_tf, time[i - 1], false);
         if(newerShift != shift)
         {
            if(g_tfState[shift] == 1.0 && g_tfState[shift + 1] == -1.0)
               BufBuy[i] = low[i] - InpArrowOffsetPips * g_pip;
            else if(g_tfState[shift] == -1.0 && g_tfState[shift + 1] == 1.0)
               BufSell[i] = high[i] + InpArrowOffsetPips * g_pip;
         }
      }
   }

   if(prev_calculated <= 0 || prev_calculated > rates_total)
   {
      int alertShift = iBarShift(_Symbol, g_tf, time[1], false);
      if(alertShift >= 0)
         g_lastAlertTime = iTime(_Symbol, g_tf, alertShift);
   }
   else if(InpAlertPopup || InpAlertPush || InpAlertEmail)
      CheckAlerts(time);

   return rates_total;
}

//+------------------------------------------------------------------+
//| Full selected-timeframe Supertrend calculation.                  |
//| Arrays use series indexing: shift 0 is the forming MTF candle.    |
//+------------------------------------------------------------------+
void CalculateAllTfBars(int calcBars)
{
   g_tfCalcBars = calcBars;

   ArrayResize(g_tfUp, calcBars);
   ArrayResize(g_tfDown, calcBars);
   ArrayResize(g_tfState, calcBars);
   ArrayResize(g_tfFinalUpper, calcBars);
   ArrayResize(g_tfFinalLower, calcBars);

   ArraySetAsSeries(g_tfUp, true);
   ArraySetAsSeries(g_tfDown, true);
   ArraySetAsSeries(g_tfState, true);
   ArraySetAsSeries(g_tfFinalUpper, true);
   ArraySetAsSeries(g_tfFinalLower, true);

   ArrayInitialize(g_tfUp, EMPTY_VALUE);
   ArrayInitialize(g_tfDown, EMPTY_VALUE);
   ArrayInitialize(g_tfState, 0.0);
   ArrayInitialize(g_tfFinalUpper, EMPTY_VALUE);
   ArrayInitialize(g_tfFinalLower, EMPTY_VALUE);

   int oldestValid = calcBars - InpAtrPeriod;

   // Process chronologically: oldest valid shift down to the current bar.
   for(int i = oldestValid; i >= 0; i--)
   {
      double h   = iHigh(_Symbol, g_tf, i);
      double l   = iLow(_Symbol, g_tf, i);
      double c   = iClose(_Symbol, g_tf, i);
      double atr = iATR(_Symbol, g_tf, InpAtrPeriod, i);

      if(h <= 0.0 || l <= 0.0 || c <= 0.0 || atr <= 0.0)
         continue;

      double hl2 = (h + l) / 2.0;
      double basicUpper = hl2 + InpMultiplier * atr;
      double basicLower = hl2 - InpMultiplier * atr;

      if(i == oldestValid)
      {
         g_tfFinalUpper[i] = basicUpper;
         g_tfFinalLower[i] = basicLower;
         g_tfState[i]      = (c >= hl2 ? 1.0 : -1.0);
      }
      else
      {
         double previousClose = iClose(_Symbol, g_tf, i + 1);

         if(basicUpper < g_tfFinalUpper[i + 1] || previousClose > g_tfFinalUpper[i + 1])
            g_tfFinalUpper[i] = basicUpper;
         else
            g_tfFinalUpper[i] = g_tfFinalUpper[i + 1];

         if(basicLower > g_tfFinalLower[i + 1] || previousClose < g_tfFinalLower[i + 1])
            g_tfFinalLower[i] = basicLower;
         else
            g_tfFinalLower[i] = g_tfFinalLower[i + 1];

         double previousState = g_tfState[i + 1];
         if(previousState == 1.0 && c < g_tfFinalLower[i])
            g_tfState[i] = -1.0;
         else if(previousState == -1.0 && c > g_tfFinalUpper[i])
            g_tfState[i] = 1.0;
         else
            g_tfState[i] = previousState;
      }

      if(g_tfState[i] == 1.0)
         g_tfUp[i] = g_tfFinalLower[i];
      else if(g_tfState[i] == -1.0)
         g_tfDown[i] = g_tfFinalUpper[i];
   }
}

//+------------------------------------------------------------------+
//| Only the forming MTF candle changes on a normal tick.             |
//| Recalculate shift 0 from the already calculated shift 1.          |
//+------------------------------------------------------------------+
void UpdateCurrentTfBar()
{
   if(g_tfCalcBars < InpAtrPeriod + 2)
      return;

   int i = 0;
   double h   = iHigh(_Symbol, g_tf, i);
   double l   = iLow(_Symbol, g_tf, i);
   double c   = iClose(_Symbol, g_tf, i);
   double atr = iATR(_Symbol, g_tf, InpAtrPeriod, i);

   if(h <= 0.0 || l <= 0.0 || c <= 0.0 || atr <= 0.0)
      return;

   double hl2 = (h + l) / 2.0;
   double basicUpper = hl2 + InpMultiplier * atr;
   double basicLower = hl2 - InpMultiplier * atr;
   double previousClose = iClose(_Symbol, g_tf, 1);

   if(basicUpper < g_tfFinalUpper[1] || previousClose > g_tfFinalUpper[1])
      g_tfFinalUpper[0] = basicUpper;
   else
      g_tfFinalUpper[0] = g_tfFinalUpper[1];

   if(basicLower > g_tfFinalLower[1] || previousClose < g_tfFinalLower[1])
      g_tfFinalLower[0] = basicLower;
   else
      g_tfFinalLower[0] = g_tfFinalLower[1];

   if(g_tfState[1] == 1.0 && c < g_tfFinalLower[0])
      g_tfState[0] = -1.0;
   else if(g_tfState[1] == -1.0 && c > g_tfFinalUpper[0])
      g_tfState[0] = 1.0;
   else
      g_tfState[0] = g_tfState[1];

   g_tfUp[0]   = EMPTY_VALUE;
   g_tfDown[0] = EMPTY_VALUE;
   if(g_tfState[0] == 1.0)
      g_tfUp[0] = g_tfFinalLower[0];
   else if(g_tfState[0] == -1.0)
      g_tfDown[0] = g_tfFinalUpper[0];
}

//+------------------------------------------------------------------+
void SetEmpty(int i)
{
   BufUp[i]    = EMPTY_VALUE;
   BufDown[i]  = EMPTY_VALUE;
   BufBuy[i]   = EMPTY_VALUE;
   BufSell[i]  = EMPTY_VALUE;
   BufState[i] = EMPTY_VALUE;
}

//+------------------------------------------------------------------+
void CheckAlerts(const datetime &time[])
{
   int shift = iBarShift(_Symbol, g_tf, time[1], false);
   if(shift < 1 || shift + 1 >= g_tfCalcBars)
      return;

   bool buy = (g_tfState[shift] == 1.0 && g_tfState[shift + 1] == -1.0);
   bool sell = (g_tfState[shift] == -1.0 && g_tfState[shift + 1] == 1.0);
   if(!buy && !sell)
      return;

   datetime tfTime = iTime(_Symbol, g_tf, shift);
   if(tfTime <= 0 || tfTime == g_lastAlertTime)
      return;
   g_lastAlertTime = tfTime;

   string message = _Symbol + " " + TfName(g_tf) + " Supertrend: " +
                    (buy ? "BUY reversal" : "SELL reversal");
   if(InpAlertPopup) Alert(message);
   if(InpAlertPush)  SendNotification(message);
   if(InpAlertEmail) SendMail("Supertrend " + _Symbol, message);
}
//+------------------------------------------------------------------+
