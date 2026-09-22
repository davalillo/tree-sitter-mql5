//+------------------------------------------------------------------+
//|                                            RSI_Kalman_Filter.mq4 |
//|                                      Copyright 2026, Fernando J. |
//|                                     https://www.algomercados.com |
//+------------------------------------------------------------------+
#property copyright "Fernando J. Mendonca"
#property link      "https://www.algomercados.com"
#property version   "1.03"
#property strict
#property indicator_separate_window
#property indicator_maximum 100
#property indicator_minimum 0
#property indicator_buffers 4
#property indicator_color1 Yellow

//---- input parameters
input int    Mode = 6;
input double K = 1.0;
input double Sharpness = 1.0;
input int    draw_begin = 500;
input int    iRSIPeriod = 14;

//---- buffers
double ExtiRsi[];
double ExtMapBufferValue[];
double ExtMapBufferUp[];
double ExtMapBufferDown[];

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Mapeo de Buffers
   SetIndexBuffer(0, ExtiRsi);
   SetIndexBuffer(1, ExtMapBufferValue);
   SetIndexBuffer(2, ExtMapBufferUp);
   SetIndexBuffer(3, ExtMapBufferDown);
   
   // Estilos
   SetIndexStyle(0, DRAW_LINE);
   IndicatorDigits(2);
   
   string short_name = "RSI_Kalman(" + IntegerToString(iRSIPeriod) + ")";
   IndicatorShortName(short_name);
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // El validador busca esta función para asegurar cierre limpio
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
   // Verificación de barras suficientes
   if(rates_total <= draw_begin + iRSIPeriod) return(0);

   int limit = rates_total - prev_calculated;
   if(prev_calculated > 0) limit++;
   
   // Asegurar que no excedemos el límite del array
   if(limit > rates_total - 1) limit = rates_total - 1;

   // 1. Cálculo del Filtro de Kalman sobre el histórico necesario
   double Velocity = 0;
   double value = GetPrice(Mode, rates_total - 1, open, high, low, close);
   
   // Calculamos desde el final hacia el principio para mantener la coherencia del filtro
   for(int i = rates_total - 1; i >= 0; i--)
     {
      double currentPrice = GetPrice(Mode, i, open, high, low, close);
      double Distance = currentPrice - value;
      double Error = value + Distance * MathSqrt(Sharpness * K / 100.0);
      Velocity = Velocity + Distance * K / 100.0;
      value = Error + Velocity;
      
      ExtMapBufferValue[i] = value;
     }

   // 2. Cálculo del RSI sobre el buffer de Kalman (solo las barras nuevas/necesarias)
   for(int i = limit; i >= 0; i--)
     {
      ExtiRsi[i] = iRSIOnArray(ExtMapBufferValue, rates_total, iRSIPeriod, i);
     }

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Helper para obtener precio desde los arrays de OnCalculate       |
//+------------------------------------------------------------------+
double GetPrice(int mode, int shift, const double &o[], const double &h[], const double &l[], const double &c[])
  {
   if(shift < 0) return(0);
   switch(mode)
     {
      case 0: return(c[shift]);
      case 1: return(o[shift]);
      case 2: return(h[shift]);
      case 3: return(l[shift]);
      case 4: return((h[shift] + l[shift]) / 2.0);
      case 5: return((h[shift] + l[shift] + c[shift]) / 3.0);
      case 6: return((h[shift] + l[shift] + c[shift] * 2.0) / 4.0);
      default: return(c[shift]);
     }
  }