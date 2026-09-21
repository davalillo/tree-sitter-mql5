//+------------------------------------------------------------------+
//|                                                  VSA_Candles.mq5 |
//|        Native Candlestick Painter & VSA SAR-Style Trend Dots     |
//+------------------------------------------------------------------+
#property copyright   "VSA"
#property link        "https://www.mql5.com"
#property version     "2.00"
#property indicator_chart_window
#property indicator_plots   2
#property indicator_buffers 7

//--- Plot 1: Native Colored Candles
#property indicator_label1  "VSA Native Candle"
#property indicator_type1   DRAW_COLOR_CANDLES
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1
#property indicator_color1  clrLimeGreen,clrCrimson,C'0,230,118',C'255,82,82',C'68,138,255',clrYellow

//--- Plot 2: VSA SAR-Style Trend Dots
#property indicator_label2  "VSA SAR Dots"
#property indicator_type2   DRAW_COLOR_ARROW
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2
#property indicator_color2  C'0,230,118',C'255,82,82' // 0: Bullish Buy Zone, 1: Bearish Sell Zone

//--- Indicator Buffers
double BuffOpen[];
double BuffHigh[];
double BuffLow[];
double BuffClose[];
double BuffCandleColor[];

double BuffSARDots[];
double BuffSARColor[];

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== Performance Limit ==="
input int                InpLimitBars            = 2000;         // Scan Limit (2k Bars)

input group "=== VSA SAR Trend Dot Settings ==="
input bool               InpShowSARDots          = true;         // Show SAR Trend Dots
input int                InpSARWidth             = 2;            // SAR Dot Size (1 to 5)
input double             InpSARAtrMultiplier     = 0.55;         // Distance Multiplier (ATR Offset)
input int                InpSARAtrPeriod         = 14;           // Volatility Lookback (ATR)
input double             InpSARAccelFactor       = 0.02;         // Step Acceleration Factor
input double             InpSARMaxAccel          = 0.20;         // Max Acceleration Factor

input group "=== VSA Sensitivity Multipliers ==="
input double             InpMultVolumeLow        = 0.5;          // Volume Low Mult
input double             InpMultVolumeHigh       = 1.5;          // Volume High Mult
input double             InpMultVolumeUltra      = 3.0;          // Volume Ultra Mult
input int                InpMALengthVolume       = 20;           // Volume MA Length

//+------------------------------------------------------------------+
//| Indicator Initialization                                         |
//+------------------------------------------------------------------+
int OnInit()
 {
// 1. Candles Buffers
  SetIndexBuffer(0, BuffOpen,        INDICATOR_DATA);
  SetIndexBuffer(1, BuffHigh,        INDICATOR_DATA);
  SetIndexBuffer(2, BuffLow,         INDICATOR_DATA);
  SetIndexBuffer(3, BuffClose,       INDICATOR_DATA);
  SetIndexBuffer(4, BuffCandleColor, INDICATOR_COLOR_INDEX);
// 2. SAR Trend Dots Buffers
  SetIndexBuffer(5, BuffSARDots,     INDICATOR_DATA);
  SetIndexBuffer(6, BuffSARColor,    INDICATOR_COLOR_INDEX);
  ArraySetAsSeries(BuffOpen,        true);
  ArraySetAsSeries(BuffHigh,        true);
  ArraySetAsSeries(BuffLow,         true);
  ArraySetAsSeries(BuffClose,       true);
  ArraySetAsSeries(BuffCandleColor, true);
  ArraySetAsSeries(BuffSARDots,     true);
  ArraySetAsSeries(BuffSARColor,    true);
  PlotIndexSetInteger(1, PLOT_ARROW, 159); // Solid Round Bullet Dot
  PlotIndexSetInteger(1, PLOT_LINE_WIDTH, InpSARWidth);
  IndicatorSetString(INDICATOR_SHORTNAME, "VSA Candles & SAR Dots");
  return(INIT_SUCCEEDED);
 }

//+------------------------------------------------------------------+
//| Helper: True Range / ATR Calculation                             |
//+------------------------------------------------------------------+
double CalculateATR(const double &high[], const double &low[], const double &close[], int index, int total)
 {
  double sumTR = 0.0;
  int count = 0;
  for(int k = 0; k < InpSARAtrPeriod && (index + k + 1) < total; k++)
   {
    int bar = index + k;
    double tr1 = high[bar] - low[bar];
    double tr2 = MathAbs(high[bar] - close[bar + 1]);
    double tr3 = MathAbs(low[bar] - close[bar + 1]);
    sumTR += MathMax(tr1, MathMax(tr2, tr3));
    count++;
   }
  return (count > 0) ? (sumTR / count) : ((high[index] - low[index]));
 }

//+------------------------------------------------------------------+
//| Main Iteration Function                                          |
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
  if(rates_total < 40)
    return 0;
  ArraySetAsSeries(time, true);
  ArraySetAsSeries(open, true);
  ArraySetAsSeries(high, true);
  ArraySetAsSeries(low, true);
  ArraySetAsSeries(close, true);
  ArraySetAsSeries(tick_volume, true);
  ArraySetAsSeries(volume, true);
  int limit = rates_total - prev_calculated;
  if(limit <= 0)
    limit = 1;
  if(prev_calculated == 0 || limit > InpLimitBars)
    limit = MathMin(rates_total - 1, InpLimitBars);
// Persistent State Tracking for SAR Dynamic Dots
  static int    trendDir   = 1;     // +1: Bullish Buy Zone, -1: Bearish Sell Zone
  static double trailingEP = 0.0;   // Extreme Price
  static double currentAF  = 0.02;  // Acceleration Factor
  static double sarVal     = 0.0;   // SAR Current Level
  for(int i = limit; i >= 0; i--)
   {
    BuffOpen[i]  = open[i];
    BuffHigh[i]  = high[i];
    BuffLow[i]   = low[i];
    BuffClose[i] = close[i];
    bool isBull = (close[i] >= open[i]);
    BuffCandleColor[i] = isBull ? 0 : 1; // Default theme colors
    // -------------------------------------------------------------
    // 1. VSA Detection Algorithm
    // -------------------------------------------------------------
    double curV = (volume[i] > 0) ? (double)volume[i] : (double)tick_volume[i];
    double sumV = 0.0;
    int countV = 0;
    for(int k = 0; k < InpMALengthVolume && (i + k) < rates_total; k++)
     {
      sumV += (volume[i + k] > 0) ? (double)volume[i + k] : (double)tick_volume[i + k];
      countV++;
     }
    double maV = (countV > 0) ? (sumV / countV) : curV;
    double sprd = high[i] - low[i];
    if(sprd <= 0.0)
      sprd = _Point;
    double body = MathAbs(close[i] - open[i]);
    double upWick = high[i] - MathMax(open[i], close[i]);
    double dnWick = MathMin(open[i], close[i]) - low[i];
    double bodyPct  = (body / sprd) * 100.0;
    double upWickPct = (upWick / sprd) * 100.0;
    double dnWickPct = (dnWick / sprd) * 100.0;
    bool isBullPin = (bodyPct <= 33.0 && dnWickPct >= 60.0);
    bool isBearPin = (bodyPct <= 33.0 && upWickPct >= 60.0);
    bool isDoji    = (bodyPct <= 10.0);
    bool isSpinTop = (upWickPct >= 34.0 && dnWickPct >= 34.0 && bodyPct < 30.0);
    bool isVolUltra = (curV > maV * InpMultVolumeUltra);
    bool isVolHigh  = (curV > maV * InpMultVolumeHigh);
    bool isVolLow   = (curV < maV * InpMultVolumeLow);
    bool isStrength = false;
    bool isWeakness = false;
    bool isNeutral  = false;
    // Signs of Strength (SOS)
    if((isBullPin && (isVolHigh || isVolUltra)) ||
       (!isBull && dnWickPct >= 25.0 && (isVolUltra || isVolHigh)) ||
       (!isBull && (isVolHigh || isVolUltra) && bodyPct < 30.0) ||
       (isBearPin && (isVolHigh || isVolUltra)) ||
       (!isBull && isVolUltra && close[i] > (low[i] + sprd * 0.4)) ||
       (isBullPin && i < rates_total - 2 && curV < (double)tick_volume[i + 1] && curV < (double)tick_volume[i + 2]) ||
       (!isBull && isVolLow && i < rates_total - 2 && curV < (double)tick_volume[i + 1] && curV < (double)tick_volume[i + 2]))
     {
      isStrength = true;
     }
    // Signs of Weakness (SOW)
    else
      if((isBearPin && (isVolHigh || isVolUltra)) ||
         (isBull && upWickPct >= 25.0 && (isVolUltra || isVolHigh)) ||
         (isBull && (isVolHigh || isVolUltra) && bodyPct < 30.0) ||
         (isBullPin && (isVolHigh || isVolUltra) && high[i] >= high[i + 1]) ||
         (isBull && isVolUltra && close[i] < (high[i] - sprd * 0.4)) ||
         (isBearPin && i < rates_total - 2 && curV < (double)tick_volume[i + 1] && curV < (double)tick_volume[i + 2]) ||
         (isBull && isVolLow && i < rates_total - 2 && curV < (double)tick_volume[i + 1] && curV < (double)tick_volume[i + 2]))
       {
        isWeakness = true;
       }
      else
        if(isDoji || isSpinTop)
         {
          isNeutral = true;
         }
    // Assign Native Candle Colors on Closed Bars
    if(i >= 1)
     {
      if(isStrength)
        BuffCandleColor[i] = 2; // Green
      else
        if(isWeakness)
          BuffCandleColor[i] = 3; // Red
        else
          if(isNeutral)
            BuffCandleColor[i] = 4; // Blue
          else
            if(isBullPin || isBearPin)
              BuffCandleColor[i] = 5; // Yellow
     }
    // -------------------------------------------------------------
    // 2. Adaptive VSA SAR-Style Trend Dots Calculation
    // -------------------------------------------------------------
    if(InpShowSARDots)
     {
      double atr = CalculateATR(high, low, close, i, rates_total);
      double atrPad = atr * InpSARAtrMultiplier;
      if(i == limit)
       {
        trendDir   = isBull ? 1 : -1;
        trailingEP = trendDir > 0 ? high[i] : low[i];
        sarVal     = trendDir > 0 ? (low[i] - atrPad) : (high[i] + atrPad);
        currentAF  = InpSARAccelFactor;
       }
      else
       {
        // Immediate Trend Reversal Triggers based on VSA Strength / Weakness
        if(trendDir > 0 && (isWeakness || close[i] < sarVal))
         {
          trendDir   = -1; // Flip to Bearish (Sell Zone)
          sarVal     = MathMax(high[i], trailingEP) + atrPad;
          trailingEP = low[i];
          currentAF  = InpSARAccelFactor;
         }
        else
          if(trendDir < 0 && (isStrength || close[i] > sarVal))
           {
            trendDir   = 1;  // Flip to Bullish (Buy Zone)
            sarVal     = MathMin(low[i], trailingEP) - atrPad;
            trailingEP = high[i];
            currentAF  = InpSARAccelFactor;
           }
          else
           {
            // Standard Trailing Parabolic Acceleration
            sarVal = sarVal + currentAF * (trailingEP - sarVal);
            if(trendDir > 0)
             {
              if(high[i] > trailingEP)
               {
                trailingEP = high[i];
                currentAF  = MathMin(InpSARMaxAccel, currentAF + InpSARAccelFactor);
               }
              // Guarantee SAR stays below candle lows in an uptrend
              double floorLimit = low[i] - atrPad;
              if(sarVal > floorLimit)
                sarVal = floorLimit;
             }
            else
             {
              if(low[i] < trailingEP)
               {
                trailingEP = low[i];
                currentAF  = MathMin(InpSARMaxAccel, currentAF + InpSARAccelFactor);
               }
              // Guarantee SAR stays above candle highs in a downtrend
              double ceilingLimit = high[i] + atrPad;
              if(sarVal < ceilingLimit)
                sarVal = ceilingLimit;
             }
           }
       }
      // Output into Plot 2
      BuffSARDots[i]  = sarVal;
      BuffSARColor[i] = (trendDir > 0) ? 0 : 1; // 0: Green (Buy Zone), 1: Red (Sell Zone)
     }
    else
     {
      BuffSARDots[i] = EMPTY_VALUE;
     }
   }
  return(rates_total);
 }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
