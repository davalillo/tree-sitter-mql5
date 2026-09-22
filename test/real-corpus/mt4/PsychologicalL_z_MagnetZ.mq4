//+------------------------------------------------------------------+
//|                                     Psychological_Levels.mq4     |
//|                                     Copyright 2026, Amanda V     |
//+------------------------------------------------------------------+
#property copyright "Amanda V"
#property version   "1.00"
#property strict
#property indicator_chart_window

//--- Inputs
input int    InpLevelsSpacing = 500;       // Spacing in Points (e.g., 500 or 1000)
input color  InpMajorColor    = clrGray;    // Major Level Color (000)
input color  InpMinorColor    = clrSilver;  // Minor Level Color (500)
input int    InpLinesToDraw   = 20;         // Number of lines above/below price

string prefix = "INST_LEVEL_";

//+------------------------------------------------------------------+
int OnInit() {
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, prefix);
}

//+------------------------------------------------------------------+
//| OnCalculate - Otimizado para MQL4                                |
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
   ObjectsDeleteAll(0, prefix);
   
   double p_size = Point;
   double current_price = Close[0];
   
   // Arredonda o preço atual para o nível mais próximo
   double grid_size = InpLevelsSpacing * p_size;
   if(grid_size <= 0) return(rates_total);
   
   double base_level = MathFloor(current_price / grid_size) * grid_size;
   
   for(int i = -InpLinesToDraw; i <= InpLinesToDraw; i++)
     {
      double level_price = base_level + (i * grid_size);
      string name = prefix + DoubleToString(level_price, Digits);
      
      // Determina se é um nível Major (arredondado por 1000 pontos)
      bool is_major = (MathMod(level_price / p_size, 1000) == 0);
      
      if(ObjectCreate(0, name, OBJ_HLINE, 0, 0, level_price))
        {
         ObjectSetInteger(0, name, OBJPROP_COLOR, is_major ? InpMajorColor : InpMinorColor);
         ObjectSetInteger(0, name, OBJPROP_STYLE, is_major ? STYLE_DOT : STYLE_DOT);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name, OBJPROP_BACK, true);
         ObjectSetString(0, name, OBJPROP_TOOLTIP, is_major ? "Institutional Major Level" : "Psychological Level");
        }
     }
     
   return(rates_total);
}