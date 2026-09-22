//+------------------------------------------------------------------+
//|                                                 Aura Heiken Ashi |
//|                                       Copyright 2026, BabuForex  |
//|                                            https://babuforex.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, BabuForex"
#property link      "https://babuforex.com"
#property version   "1.1"
#property description "High-precision Aura Heiken Ashi indicator with SnD levels and multi-filter trend logic."
#property strict

#property indicator_chart_window
#property indicator_buffers 5

#property indicator_color1 clrGray
#property indicator_color2 clrGray
#property indicator_color3 clrFireBrick
#property indicator_color4 clrSpringGreen
#property indicator_color5 clrDeepSkyBlue

#property indicator_width1 1
#property indicator_width2 1
#property indicator_width3 3
#property indicator_width4 3
#property indicator_width5 2

input group "--- HEIKEN ASHI SETTINGS ---"
input ENUM_MA_METHOD  InpMaMethod  = MODE_SMMA;  // Candle smoothing method
input int             InpMaPeriod  = 6;          // Candle smoothing period
input ENUM_MA_METHOD  InpMaMethod2 = MODE_EMA;   // Final refinement method
input int             InpMaPeriod2 = 2;          // Final refinement period

input group "--- PRECISION FILTERS ---"
input int             InpEMAFilter   = 200;      // Trend filter (Price above = Buy, Below = Sell)
input bool            ShowEMALine    = true;     // Show or hide the 200 EMA line on chart
input int             InpADXPeriod   = 14;       // Period for trend strength detection
input int             InpADXLevel    = 20;       // Minimum strength to show signal (Higher = Safer)
input int             InpCCIPeriod   = 14;       // Period for momentum calculation
input int             InpMACDFast    = 12;       // Fast EMA for MACD filter
input int             InpMACDSlow    = 26;       // Slow EMA for MACD filter
input int             InpMACDSignal  = 9;        // Signal line for MACD filter

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input group "--- SUPPLY & DEMAND (SnD) ---"
input bool            ShowSnD        = true;     // Enable/Disable Supply & Demand lines
input int             SnD_Period     = 50;       // Lookback bars to find High/Low zones
input color           SupplyColor    = clrLightSalmon;    // Color for Resistance lines
input color           DemandColor    = clrLightSteelBlue;  // Color for Support lines
input ENUM_LINE_STYLE SnDStyle       = STYLE_DOT;       // Style of the SnD lines

//---- Buffers
double ExtBufferHigh[], ExtBufferLow[], ExtBufferOpen[], ExtBufferClose[];
double EMABuffer[];
double TempHigh[], TempLow[], TempOpen[], TempClose[];

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, ExtBufferHigh);
   SetIndexBuffer(1, ExtBufferLow);
   SetIndexBuffer(2, ExtBufferOpen);
   SetIndexBuffer(3, ExtBufferClose);
   SetIndexBuffer(4, EMABuffer);

   for(int i=0; i<4; i++)
      SetIndexStyle(i, DRAW_HISTOGRAM);
   SetIndexStyle(4, ShowEMALine ? DRAW_LINE : DRAW_NONE);

   IndicatorBuffers(9);
   SetIndexBuffer(5, TempOpen);
   SetIndexBuffer(6, TempClose);
   SetIndexBuffer(7, TempHigh);
   SetIndexBuffer(8, TempLow);

   IndicatorShortName("AURA_HA_SnD");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "SND_");
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
   if(rates_total <= MathMax(InpEMAFilter, SnD_Period))
      return(0);

   int limit = rates_total - prev_calculated;
   if(prev_calculated > 0)
      limit++;

//--- Update SnD Lines (Per Bar)
   if(ShowSnD && (prev_calculated == 0 || limit > 0))
      UpdateSnD(rates_total, high, low);

   for(int i=0; i<limit; i++)
     {
      TempOpen[i]  = iMA(NULL, 0, InpMaPeriod, 0, InpMaMethod, PRICE_OPEN, i);
      TempClose[i] = iMA(NULL, 0, InpMaPeriod, 0, InpMaMethod, PRICE_CLOSE, i);
      TempHigh[i]  = iMA(NULL, 0, InpMaPeriod, 0, InpMaMethod, PRICE_HIGH, i);
      TempLow[i]   = iMA(NULL, 0, InpMaPeriod, 0, InpMaMethod, PRICE_LOW, i);
      EMABuffer[i] = iMA(NULL, 0, InpEMAFilter, 0, MODE_EMA, PRICE_CLOSE, i);
     }

   int pos = rates_total - MathMax(InpMaPeriod, prev_calculated) - 2;
   if(pos < 0)
      pos = 0;
   for(int i=pos; i>=0; i--)
     {
      double haOpen  = (TempOpen[i+1] + TempClose[i+1]) / 2.0;
      double haClose = (TempOpen[i] + TempHigh[i] + TempLow[i] + TempClose[i]) / 4.0;
      TempOpen[i]  = haOpen;
      TempClose[i] = haClose;
      TempHigh[i]  = MathMax(TempHigh[i], MathMax(haOpen, haClose));
      TempLow[i]   = MathMin(TempLow[i], MathMin(haOpen, haClose));
     }

   for(int i=0; i<limit; i++)
     {
      double h = iMAOnArray(TempHigh,  0, InpMaPeriod2, 0, InpMaMethod2, i);
      double l = iMAOnArray(TempLow,   0, InpMaPeriod2, 0, InpMaMethod2, i);
      double o = iMAOnArray(TempOpen,  0, InpMaPeriod2, 0, InpMaMethod2, i);
      double c = iMAOnArray(TempClose, 0, InpMaPeriod2, 0, InpMaMethod2, i);

      double adx    = iADX(NULL, 0, InpADXPeriod, PRICE_CLOSE, MODE_MAIN, i);
      double cci    = iCCI(NULL, 0, InpCCIPeriod, PRICE_TYPICAL, i);
      double macd   = iMACD(NULL, 0, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_MAIN, i);
      double signal = iMACD(NULL, 0, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_SIGNAL, i);

      bool trendStrong = (adx > InpADXLevel);
      bool isBullish   = (c > o && cci > 0 && macd > signal && close[i] > EMABuffer[i]);
      bool isBearish   = (c < o && cci < 0 && macd < signal && close[i] < EMABuffer[i]);

      if(isBullish && trendStrong)
        {
         ExtBufferOpen[i] = o;
         ExtBufferClose[i] = c;
         ExtBufferHigh[i] = l;
         ExtBufferLow[i] = h;
        }
      else
         if(isBearish && trendStrong)
           {
            ExtBufferOpen[i] = o;
            ExtBufferClose[i] = c;
            ExtBufferHigh[i] = h;
            ExtBufferLow[i] = l;
           }
         else
           {
            ExtBufferOpen[i] = o;
            ExtBufferClose[i] = c;
            ExtBufferHigh[i] = EMPTY_VALUE;
            ExtBufferLow[i] = EMPTY_VALUE;
           }
     }
   return(rates_total);
  }

//+------------------------------------------------------------------+
void UpdateSnD(int rates_total, const double &high[], const double &low[])
  {
   ObjectsDeleteAll(0, "SND_");

   int resIdx = iHighest(NULL, 0, MODE_HIGH, SnD_Period, 1);
   int supIdx = iLowest(NULL, 0, MODE_LOW, SnD_Period, 1);

   if(resIdx != -1)
      CreateLine("SND_SUPPLY", high[resIdx], SupplyColor);
   if(supIdx != -1)
      CreateLine("SND_DEMAND", low[supIdx], DemandColor);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CreateLine(string name, double price, color clr)
  {
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, SnDStyle);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
  }
//+------------------------------------------------------------------+
