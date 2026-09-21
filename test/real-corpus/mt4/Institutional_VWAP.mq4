//+------------------------------------------------------------------+
//|                                         Institutional_VWAP.mq4   |
//|                                         Copyright 2026, Amanda V |
//+------------------------------------------------------------------+
#property copyright "Amanda V"
#property version   "1.02"
#property strict
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

//--- Visual Settings
#property indicator_label1  "VWAP"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDarkOrange
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "Upper Band"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrGray
#property indicator_style2  STYLE_DASH

#property indicator_label3  "Lower Band"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrGray
#property indicator_style3  STYLE_DASH

//--- Inputs
input ENUM_TIMEFRAMES InpAnchorPeriod = PERIOD_D1; // VWAP Anchor Session
input double          InpDeviation    = 2.0;       // Standard Deviation Multiplier

//--- Buffers
double ExtVWAPBuffer[];
double ExtUpperBuffer[];
double ExtLowerBuffer[];

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, ExtVWAPBuffer);
   SetIndexBuffer(1, ExtUpperBuffer);
   SetIndexBuffer(2, ExtLowerBuffer);
   
   IndicatorShortName("Institutional VWAP (" + DoubleToString(InpDeviation,1) + " SD)");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnCalculate corrigido com referências (&) para o MQL4            |
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
   if(rates_total < 2) return(0);
   if(Period() >= InpAnchorPeriod) return(0);
   
   int limit = prev_calculated - 1;
   if(prev_calculated == 0) limit = 0;
   
   double cum_vol = 0;
   double cum_pv = 0;
   
   // Buffer temporário para cálculo de variância
   static double typical_prices[];
   if(ArraySize(typical_prices) != rates_total) ArrayResize(typical_prices, rates_total);

   for(int i = limit; i < rates_total; i++)
     {
      bool new_session = false;
      if(i == 0) new_session = true;
      else
        {
         if(InpAnchorPeriod == PERIOD_D1 && TimeDay(time[i]) != TimeDay(time[i-1])) new_session = true;
         if(InpAnchorPeriod == PERIOD_W1 && TimeDayOfWeek(time[i]) < TimeDayOfWeek(time[i-1])) new_session = true;
         if(InpAnchorPeriod == PERIOD_MN1 && TimeMonth(time[i]) != TimeMonth(time[i-1])) new_session = true;
        }

      if(new_session) { cum_vol = 0; cum_pv = 0; }

      double typical_price = (high[i] + low[i] + close[i]) / 3.0;
      double vol = (double)tick_volume[i];
      
      cum_vol += vol;
      cum_pv += (typical_price * vol);
      
      ExtVWAPBuffer[i] = (cum_vol > 0) ? cum_pv / cum_vol : typical_price;
      typical_prices[i] = typical_price;
      
      // Cálculo de Desvio Padrão
      double variance = 0;
      int count = 0;
      for(int j = i; j >= 0; j--)
        {
         variance += MathPow(typical_prices[j] - ExtVWAPBuffer[i], 2);
         count++;
         if(j == 0) break;
         if(InpAnchorPeriod == PERIOD_D1 && TimeDay(time[j]) != TimeDay(time[j-1])) break;
         if(InpAnchorPeriod == PERIOD_W1 && TimeDayOfWeek(time[j]) < TimeDayOfWeek(time[j-1])) break;
         if(InpAnchorPeriod == PERIOD_MN1 && TimeMonth(time[j]) != TimeMonth(time[j-1])) break;
        }
        
      double std_dev = (count > 0) ? MathSqrt(variance / count) : 0;
      ExtUpperBuffer[i] = ExtVWAPBuffer[i] + (std_dev * InpDeviation);
      ExtLowerBuffer[i] = ExtVWAPBuffer[i] - (std_dev * InpDeviation);
     }
     
   return(rates_total);
  }