//+------------------------------------------------------------------+
//|                                    Ehlers_Fisher_Transform.mq4   |
//|                             Copyright 2026, Amanda V | KayruYuta |
//+------------------------------------------------------------------+
#property copyright "Amanda V | KayruYuta"
#property link      "https://www.mql5.com/en/users/kayruyuta"
#property version   "2.00"
#property strict
#property indicator_separate_window
#property indicator_buffers 3
#property indicator_plots   2

//--- Fisher Transform Output
#property indicator_label1  "Fisher Transform"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDeepSkyBlue
#property indicator_width1  2

//--- Trigger Line Output
#property indicator_label2  "Trigger Line"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrCrimson
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

//--- Zero Level Baseline
#property indicator_level1  0.0
#property indicator_levelcolor clrDimGray
#property indicator_levelstyle STYLE_DOT

input int InpPeriod = 10; // DSP Transform Window

double ExtFisherBuffer[];
double ExtTriggerBuffer[];
double ExtValueBuffer[]; // Internal calculation buffer

//+------------------------------------------------------------------+
int OnInit()
  {
   // Map external drawing buffers for MT4
   SetIndexBuffer(0, ExtFisherBuffer);
   SetIndexStyle(0, DRAW_LINE);
   
   SetIndexBuffer(1, ExtTriggerBuffer);
   SetIndexStyle(1, DRAW_LINE);
   
   // Allocate internal calculation space
   IndicatorBuffers(3);
   SetIndexBuffer(2, ExtValueBuffer);
   
   IndicatorDigits(4);
   string short_name = "Inst Fisher Transform (" + IntegerToString(InpPeriod) + ")";
   IndicatorShortName(short_name);
   
   Print("Institutional Ehlers Fisher DSP Engine V1.00 Initialized (MT4).");
   return(INIT_SUCCEEDED);
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
   // Safe protection against empty history in MT4 Cloud Validator
   if(rates_total < InpPeriod + 2 || rates_total <= 0) return(0);

   int counted_bars = IndicatorCounted();
   if(counted_bars < 0) return(-1);
   
   int limit = rates_total - counted_bars - 1;
   if(limit > rates_total - 2) limit = rates_total - 2;

   int i, j;

   // DSP Mathematical Loop (Reverse Indexing for MT4)
   for(i = limit; i >= 0; i--)
     {
      double highest_high = low[i];
      double lowest_low   = high[i];

      // Find Max/Min for the current lookback window
      for(j = 0; j < InpPeriod; j++)
        {
         if(i + j >= rates_total) continue;
         if(high[i+j] > highest_high) highest_high = high[i+j];
         if(low[i+j] < lowest_low) lowest_low = low[i+j];
        }

      double median_price = (high[i] + low[i]) / 2.0;
      
      // Secure historical memory state
      double prev_value = (i + 1 < rates_total) ? ExtValueBuffer[i+1] : 0.0;
      double prev_fisher = (i + 1 < rates_total) ? ExtFisherBuffer[i+1] : 0.0;

      // 1. Normalize price into a -1 to +1 bounding constraint
      double value1 = 0.0;
      if(highest_high != lowest_low)
         value1 = 0.66 * ((median_price - lowest_low) / (highest_high - lowest_low) - 0.5) + 0.67 * prev_value;
      else
         value1 = 0.0;

      // 2. Truncate to absolute limits to prevent Mathematical Logarithm infinity errors
      if(value1 > 0.999)  value1 = 0.999;
      if(value1 < -0.999) value1 = -0.999;

      ExtValueBuffer[i] = value1;

      // 3. Apply the Fisher Transform Equation to force Gaussian Distribution
      double fisher = 0.5 * MathLog((1.0 + value1) / (1.0 - value1)) + 0.5 * prev_fisher;
      
      ExtFisherBuffer[i] = fisher;
      
      // 4. Offset Trigger Line
      ExtTriggerBuffer[i] = prev_fisher;
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+