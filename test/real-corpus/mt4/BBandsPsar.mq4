//+------------------------------------------------------------------+
//|                                                   BBandsPsar.mq4 |
//|                        Copyright 2023, MetaQuotes Software Corp. |
//|                                            https://forge.mql5.io |
//+------------------------------------------------------------------+
#property copyright "Wamek EA"
#property link      "https://www.mql5.com/en/users/wamek"
#property version   "1.00"
#property strict

#property indicator_separate_window
#property indicator_buffers 2

#property indicator_color1 Lime
#property indicator_width1 2

#property indicator_color2 Red
#property indicator_width2 2

#property indicator_level1     0.5
#property indicator_level2    -0.5
#property indicator_level3     1.5
#property indicator_level4    -1.5
#property indicator_level5     2.5
#property indicator_level6    -2.5

//---- indicator buffers
double UpLevelBuffer[];
double DownLevelBuffer[];

//-- Input parameters
input int    bbPeriod = 20;        // Bollinger Bands period
input double bbDeviation = 2.0;    // Bollinger Bands deviation
input double pstep = 0.02;         // SAR step
input double pMax = 0.2;           // SAR maximum

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int init()
{
   //--- Set indicator buffers
   SetIndexBuffer(0, UpLevelBuffer);
   SetIndexBuffer(1, DownLevelBuffer);
   
   //--- Set drawing styles
   SetIndexStyle(0, DRAW_HISTOGRAM, EMPTY, 2, Lime);
   SetIndexStyle(1, DRAW_HISTOGRAM, EMPTY, 2, Red);
   
   //--- Set labels
   SetIndexLabel(0, "UpLevel");
   SetIndexLabel(1, "DownLevel");
   
   //--- Set indicator name for the Data Window
   IndicatorShortName("BBandsPsar");
   
   return(0);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int start()
{
   //--- Check for minimum bars required
   if(Bars < bbPeriod + 50) return(0);

   //--- Calculate the starting point for recalculating bars
   int counted_bars = IndicatorCounted();
   if(counted_bars > 0) counted_bars--;
   int limit = Bars - counted_bars;
   
   //--- Main calculation loop (from oldest uncalculated bar down to the current bar)
   for(int i = limit - 1; i >= 0; i--)
   {
      //--- Get indicator values for the current shift (i)
      double sarVal    = iSAR(NULL, 0, pstep, pMax, i);
      double upperBand = iBands(NULL, 0, bbPeriod, bbDeviation, 0, PRICE_CLOSE, MODE_UPPER, i);
      double lowerBand = iBands(NULL, 0, bbPeriod, bbDeviation, 0, PRICE_CLOSE, MODE_LOWER, i);
      
      //--- Calculate Band Width
      double bandWidth = MathAbs(upperBand - lowerBand);
      if(bandWidth == 0.0) bandWidth = Point; // Fallback to prevent division by zero
      
      //--- Calculate Min/Max of Open and Close
      double minOC = MathMin(Open[i], Close[i]);
      double maxOC = MathMax(Open[i], Close[i]);
      
      //--- Calculate Levels
      double invBandWidth = 1.0 / bandWidth;
      double upLevel      = (minOC - sarVal) * invBandWidth;
      double downLevel    = (maxOC - sarVal) * invBandWidth;

      //--- Assign values to buffers
      if(upLevel > 0)
      {
         UpLevelBuffer[i]   = upLevel;
         DownLevelBuffer[i] = EMPTY_VALUE;
      }
      else if(downLevel < 0)
      {
         DownLevelBuffer[i] = downLevel;
         UpLevelBuffer[i]   = EMPTY_VALUE;
      }
      else
      {
         UpLevelBuffer[i]   = EMPTY_VALUE;
         DownLevelBuffer[i] = EMPTY_VALUE;
      }
   }
   
   return(0);
}