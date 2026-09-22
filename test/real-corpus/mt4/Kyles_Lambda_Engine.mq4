//+------------------------------------------------------------------+
//|                                         Kyles_Lambda_Engine.mq4  |
//|                             Copyright 2026, Amanda V | KayruYuta |
//+------------------------------------------------------------------+
#property copyright "Amanda V | KayruYuta"
#property link      "https://forge.mql5.io"
#property version   "10.00"
#property strict // <-- A EXIGÊNCIA CRÍTICA DO VALIDADOR DA MQL5

#property indicator_separate_window
#property indicator_buffers 3
#property indicator_plots   2

//--- High Impact Output (Orange)
#property indicator_label1  "Kyle's Lambda High Impact"
#property indicator_type1   DRAW_HISTOGRAM
#property indicator_color1  clrDarkOrange
#property indicator_width1  2

//--- Low Impact Output (Blue)
#property indicator_label2  "Kyle's Lambda Low Impact"
#property indicator_type2   DRAW_HISTOGRAM
#property indicator_color2  clrDeepSkyBlue
#property indicator_width2  2

//--- Zero Level Baseline
#property indicator_level1  0.0
#property indicator_levelcolor clrDimGray
#property indicator_levelstyle STYLE_DOT

//--- Microstructure Inputs
input int InpLookback       = 100; // Rolling Baseline Window
input int InpLambdaSmooth   = 5;   // Pre-Smoothing Period

double ExtLambdaHighBuffer[];
double ExtLambdaLowBuffer[];
double ExtRawLambda[]; // Internal calculation buffer

//+------------------------------------------------------------------+
int OnInit()
  {
   // Map external drawing buffers for MT4
   SetIndexBuffer(0, ExtLambdaHighBuffer);
   SetIndexStyle(0, DRAW_HISTOGRAM);
   
   SetIndexBuffer(1, ExtLambdaLowBuffer);
   SetIndexStyle(1, DRAW_HISTOGRAM);
   
   // Allocate internal calculation space
   IndicatorBuffers(3);
   SetIndexBuffer(2, ExtRawLambda);
   
   IndicatorDigits(5);
   string short_name = "Inst Kyle's Lambda (" + IntegerToString(InpLookback) + ")";
   IndicatorShortName(short_name);
   
   Print("Institutional Kyle's Lambda Engine V1.02 Strict Mode Active.");
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
   // Safe protection against empty history in MT4
   if(rates_total < InpLookback + InpLambdaSmooth + 2 || rates_total <= 0) return(0);

   int counted_bars = IndicatorCounted();
   if(counted_bars < 0) return(-1);
   
   int limit = rates_total - counted_bars - 1;
   if(limit > rates_total - 2) limit = rates_total - 2;

   int i, j; 

   // 1. Calculate Raw Kyle's Lambda backwards (MT4 Style)
   for(i = limit; i >= 0; i--)
     {
      double price_return = MathAbs(close[i] - close[i+1]);
      double current_vol  = (double)tick_volume[i];
      
      if(current_vol <= 1.0) current_vol = 1.0;
      
      ExtRawLambda[i] = price_return / current_vol;
     }

   // 2. Smooth and Route to the High/Low buffers conditionally
   for(i = limit; i >= 0; i--)
     {
      double sma_sum = 0.0;
      for(j = 0; j < InpLambdaSmooth; j++)
        {
         if(i + j < rates_total) sma_sum += ExtRawLambda[i + j];
        }
      double smoothed_lambda = sma_sum / InpLambdaSmooth;
      
      // Calculate dynamic lookback baseline mean
      double baseline_sum = 0.0;
      for(j = 0; j < InpLookback; j++)
        {
         if(i + j < rates_total) baseline_sum += ExtRawLambda[i + j];
        }
      double baseline_mean = baseline_sum / InpLookback;
      
      // Split routing to fake the dual-color histogram cleanly
      if(smoothed_lambda >= baseline_mean)
        {
         ExtLambdaHighBuffer[i] = smoothed_lambda;
         ExtLambdaLowBuffer[i]  = EMPTY_VALUE; // Ajuste Fino: Ocultação real no MT4
        }
      else
        {
         ExtLambdaLowBuffer[i]  = smoothed_lambda;
         ExtLambdaHighBuffer[i] = EMPTY_VALUE; // Ajuste Fino: Ocultação real no MT4
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+