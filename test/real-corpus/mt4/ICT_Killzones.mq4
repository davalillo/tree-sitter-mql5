//+------------------------------------------------------------------+
//|                                              ICT_Killzones.mq4   |
//|                                         Copyright 2026, Amanda V |
//+------------------------------------------------------------------+
#property copyright "Amanda V"
#property version   "1.50"
#property strict
#property indicator_chart_window

//--- Inputs
input group "=== General Settings ==="
input int    InpDaysToCalc = 5;          // Days to Calculate History
input int    InpGMTShift   = 0;          // Broker GMT Shift (Hours)

input group "=== Asian Range ==="
input bool   Show_Asia     = true;
input string Asia_Start    = "20:00";
input string Asia_End      = "00:00";
input color  Color_Asia    = clrLightSteelBlue;

input group "=== London Killzone ==="
input bool   Show_London   = true;
input string London_Start  = "02:00";
input string London_End    = "05:00";
input color  Color_London  = clrMistyRose;

input group "=== New York Killzone ==="
input bool   Show_NY       = true;
input string NY_Start      = "07:00";
input string NY_End        = "10:00";
input color  Color_NY      = clrHoneydew;

string prefix = "ICT_KZ_";

//+------------------------------------------------------------------+
int OnInit() {
   Print("ICT Killzones Initialized.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, prefix);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[],
                const double &close[], const long &tick_volume[], const long &volume[],
                const int &spread[]) {
                
   if(Period() > PERIOD_H1) return(rates_total); // Only draw on H1 or lower
   
   ObjectsDeleteAll(0, prefix); // Refresh boxes on new calculation
   
   datetime current_time = TimeCurrent();
   datetime start_date = current_time - (InpDaysToCalc * 86400);
   
   for(int i = 0; i < InpDaysToCalc + 1; i++) {
      datetime day_base = current_time - (i * 86400);
      string str_day = TimeToStr(day_base, TIME_DATE);
      
      if(Show_Asia)   DrawSessionBox(str_day, Asia_Start, Asia_End, Color_Asia, "Asia_" + IntegerToString(i));
      if(Show_London) DrawSessionBox(str_day, London_Start, London_End, Color_London, "Lon_" + IntegerToString(i));
      if(Show_NY)     DrawSessionBox(str_day, NY_Start, NY_End, Color_NY, "NY_" + IntegerToString(i));
   }

   return(rates_total);
}

void DrawSessionBox(string date_str, string t_start, string t_end, color box_color, string name_suffix) {
   datetime time1 = StrToTime(date_str + " " + t_start) + (InpGMTShift * 3600);
   datetime time2 = StrToTime(date_str + " " + t_end) + (InpGMTShift * 3600);
   
   // Adjust if session crosses midnight
   if(time2 <= time1) time2 += 86400;
   
   int shift1 = iBarShift(Symbol(), Period(), time1, false);
   int shift2 = iBarShift(Symbol(), Period(), time2, false);
   
   if(shift1 < 0 || shift2 < 0) return;
   if(shift2 > shift1) { int temp = shift1; shift1 = shift2; shift2 = temp; }
   
   double max_high = 0;
   double min_low = 999999;
   
   for(int i = shift2; i <= shift1; i++) {
      if(High[i] > max_high) max_high = High[i];
      if(Low[i] < min_low) min_low = Low[i];
   }
   
   if(max_high == 0 || min_low == 999999) return;
   
   string obj_name = prefix + name_suffix;
   ObjectCreate(0, obj_name, OBJ_RECTANGLE, 0, time1, max_high, time2, min_low);
   ObjectSet(obj_name, OBJPROP_COLOR, box_color);
   ObjectSet(obj_name, OBJPROP_BACK, true);
}
//+------------------------------------------------------------------+