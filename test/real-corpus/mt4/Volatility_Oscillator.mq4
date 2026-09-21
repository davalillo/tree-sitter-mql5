//+------------------------------------------------------------------+
//|                                        Volatility_Oscillator.mq4 |
//+------------------------------------------------------------------+
// https://www.tradingview.com/script/XL9nXxyY-Volatility-Oscillator/
#property description "Code by Max Michael 2026"
#property indicator_separate_window
#property indicator_buffers 3
#property indicator_color1 DarkGreen
#property indicator_color2 Maroon
#property indicator_color3 White
#property indicator_levelcolor DimGray
#property indicator_levelwidth 1
#property indicator_levelstyle 0
#property indicator_level1   0.0
#property strict

extern int            Length = 100;
input  int   BarsToCalculate = 800;

double    Vup[], Vdn[], Vosc[];

int init()
{
   SetIndexBuffer(0,Vup);  SetIndexStyle(0,DRAW_LINE);
   SetIndexBuffer(1,Vdn);  SetIndexStyle(1,DRAW_LINE);
   SetIndexBuffer(2,Vosc); SetIndexStyle(2,DRAW_LINE);   
   IndicatorShortName("Volatility_Oscillator ("+string(Length)+")");
   IndicatorDigits(_Digits);
   return(0);
}

int deinit() { return (0); }
   
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
   int limit = (prev_calculated>0) ? rates_total-prev_calculated : rates_total-1;
   if (limit > BarsToCalculate) limit=MathMin(BarsToCalculate,rates_total-1);   
   
   for(int i=limit; i>=0; i--)
   {
      double  sd=0;
      for (int k=0; k<Length; k++) sd += MathPow(Close[i+k]-Open[i+k],2);
          sd = MathSqrt(sd/(Length+1));
      Vup[i] = sd;    // upper band green
      Vdn[i] = sd*-1; // lower band red
      Vosc[i]= Close[i]-Open[i];
   }
   return(rates_total);
}
