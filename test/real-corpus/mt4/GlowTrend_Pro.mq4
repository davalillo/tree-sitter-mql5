//+------------------------------------------------------------------+
//|                                                GlowTrend Pro.mq4 |
//|                                     Copyright 2026, Ilham Hijrah |
//|                                        https://t.me/sorsawoclub" |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Ilham Hijrah"
#property link      "https://t.me/sorsawoclub"
#property version   "1.10"
#property strict
#property indicator_chart_window

// Buffers (Total 4)
#property indicator_buffers 4
#property indicator_color1  clrDodgerBlue
#property indicator_width1  3
#property indicator_color2  clrRed
#property indicator_width2  3
#property indicator_color3  clrBlue
#property indicator_color4  clrDarkRed

// Custom Enumeration untuk Menu Dropdown (MQL5 suka ini)
enum ENUM_MA_MODE
  {
   MODE_SMA_ = 0, // Simple Moving Average
   MODE_EMA_ = 1, // Exponential Moving Average
   MODE_SMMA_ = 2, // Smoothed Moving Average
   MODE_LWMA_ = 3  // Linear Weighted Moving Average
  };

// --- Input Parameters ---
input int            InpPeriod   = 20;            // Trend Period
input ENUM_MA_MODE   InpMethod   = MODE_EMA_;     // Smoothing Method
input ENUM_APPLIED_PRICE InpPrice = PRICE_CLOSE;  // Applied Price

// --- Global Buffers ---
double BullBuffer[];
double BearBuffer[];
double BuyDot[];
double SellDot[];

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   IndicatorBuffers(4);

// Buffer 0: Bullish Line
   SetIndexBuffer(0, BullBuffer);
   SetIndexStyle(0, DRAW_LINE);
   SetIndexLabel(0, "Bullish Trend");

// Buffer 1: Bearish Line
   SetIndexBuffer(1, BearBuffer);
   SetIndexStyle(1, DRAW_LINE);
   SetIndexLabel(1, "Bearish Trend");

// Buffer 2: Buy Signals (Dots)
   SetIndexBuffer(2, BuyDot);
   SetIndexStyle(2, DRAW_ARROW);
   SetIndexArrow(2, 159);
   SetIndexLabel(2, "Buy Signal");

// Buffer 3: Sell Signals (Dots)
   SetIndexBuffer(3, SellDot);
   SetIndexStyle(3, DRAW_ARROW);
   SetIndexArrow(3, 159);
   SetIndexLabel(3, "Sell Signal");

// Visual Optimizations
   IndicatorShortName("GlowTrend Pro ["+IntegerToString(InpPeriod)+"]");
   SetIndexEmptyValue(0, 0.0);
   SetIndexEmptyValue(1, 0.0);
   SetIndexEmptyValue(2, 0.0);
   SetIndexEmptyValue(3, 0.0);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Main Calculation                                                 |
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
// Proteksi jika data belum cukup
   if(rates_total <= InpPeriod)
      return(0);

   int limit = rates_total - prev_calculated;
   if(limit > 1)
      limit = rates_total - InpPeriod - 1;

   for(int i = limit; i >= 0; i--)
     {
      double currMA = iMA(NULL, 0, InpPeriod, 0, (int)InpMethod, InpPrice, i);
      double prevMA = iMA(NULL, 0, InpPeriod, 0, (int)InpMethod, InpPrice, i+1);

      // Reset Current Buffers
      BullBuffer[i] = 0.0;
      BearBuffer[i] = 0.0;
      BuyDot[i]     = 0.0;
      SellDot[i]    = 0.0;

      // Trend Detection Logic
      if(currMA > prevMA) // Upward
        {
         BullBuffer[i] = currMA;
         // Cek Reversal dari Bearish ke Bullish
         if(BearBuffer[i+1] > 0 || (BullBuffer[i+1] == 0 && BearBuffer[i+2] > 0))
           {
            BullBuffer[i+1] = prevMA; // Connect the line
            BuyDot[i] = currMA;
           }
        }
      else
         if(currMA < prevMA) // Downward
           {
            BearBuffer[i] = currMA;
            // Cek Reversal dari Bullish ke Bearish
            if(BullBuffer[i+1] > 0 || (BearBuffer[i+1] == 0 && BullBuffer[i+2] > 0))
              {
               BearBuffer[i+1] = prevMA; // Connect the line
               SellDot[i] = currMA;
              }
           }
         else // Neutral (Flat) - Follow previous color
           {
            if(BullBuffer[i+1] > 0)
               BullBuffer[i] = currMA;
            else
               if(BearBuffer[i+1] > 0)
                  BearBuffer[i] = currMA;
           }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
