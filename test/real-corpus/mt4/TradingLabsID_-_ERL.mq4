//+------------------------------------------------------------------+
//|                            External Range Liquidity ( ERL ).mq4  |
//|                               Copyright @ 2025, TradingLabs ID.  |
//|                          https://www.tiktok.com/@cakndutproject  |
//+------------------------------------------------------------------+
#property copyright "Copyright @ 2025, TradingLabs ID."
#property link      "https://www.mql5.com/en/users/suhendrawan/seller"
#property version   "2.5" 
#property description "Charting Tools External Range Liquidity ( ERL ) for MT4."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0
#property strict

//--- Input Parameters
input string  Group         = "--- Charting Tools Information ---";
input string  Tools                  = "External Range Liquidity ( ERL )"; // Indicator Name
input string  Company                = "Copyright @ 2025 - TradingLabs ID"; // Developer
input string  MoreIndicatorsLink = "https://www.mql5.com/en/users/suhendrawan/seller"; // More Free Indicator & EA Link

input string  Group1         = "--- Indicator Settings ---";
input int InpSwingCandles  = 5;     // Swing Candle
input int InpMaxBarsToScan = 200;   // Bar to scan

//--- Input Parameters Tampilan Garis ---
input int   InpLineLengthBars = 15;        // Line Length Bar
input color InpColorSwingHigh = clrHotPink;    // Swing High Color
input color InpColorSwingLow  = clrDodgerBlue; // Swing Low Color
input ENUM_LINE_STYLE InpLineStyle = STYLE_DOT; // Line style
input int   InpLineWidth      = 1;           // Line width

//--- Input Parameters Tampilan Teks ---
input int   InpTextFontSize   = 7;  // Text size
int   InpTextShiftYPips = 2;

//--- Variabel Global ---
string   g_obj_prefix = "DynSwingMarker_MQL4_" + IntegerToString(WindowHandle(Symbol(), 0));
datetime g_last_calc_time_swing_internal = 0;

static double g_last_swing_high_price = 0;
static string g_last_high_label = "";
static double g_last_swing_low_price = 0;
static string g_last_low_label = "";

//--- Structure Data ---
struct SSwingPoint
{
   datetime time;
   double   price;
   string   label;
   bool     is_high;
   string   obj_name_base;
};
SSwingPoint g_swing_points_list[];

//+------------------------------------------------------------------+
//| Fungsi Inisialisasi                                              |
//+------------------------------------------------------------------+
int init()
{
   ArrayFree(g_swing_points_list);
   return(0);
}
//+------------------------------------------------------------------+
//| Fungsi De-inisialisasi                                           |
//+------------------------------------------------------------------+
int deinit()
{
   ObjectsDeleteAll(0, g_obj_prefix);
   ArrayFree(g_swing_points_list);
   ChartRedraw();
   return(0);
}

void DrawMarkerLineWithText(string obj_name_base, datetime anchor_time, double price_level, bool is_high_swing_type,
                            string label_text, color marker_color)
{
   string obj_line_name = obj_name_base + "_Line";
   string obj_text_name = obj_name_base + "_Text";
   
   if(ObjectFind(0, obj_line_name) != -1) ObjectDelete(0, obj_line_name);
   if(ObjectFind(0, obj_text_name) != -1) ObjectDelete(0, obj_text_name);

   datetime time1_line = anchor_time;
   long ps_current = Period() * 60;
   if(ps_current == 0) ps_current = 3600;
   datetime time2_line = (datetime)((long)anchor_time + (InpLineLengthBars > 0 ? InpLineLengthBars - 1 : 0) * ps_current);

   if(ObjectCreate(0, obj_line_name, OBJ_TREND, 0, time1_line, price_level, time2_line, price_level))
   {
      ObjectSetInteger(0, obj_line_name, OBJPROP_COLOR, marker_color);
      ObjectSetInteger(0, obj_line_name, OBJPROP_STYLE, InpLineStyle);
      ObjectSetInteger(0, obj_line_name, OBJPROP_WIDTH, InpLineWidth);
      ObjectSetInteger(0, obj_line_name, OBJPROP_RAY_RIGHT, 0);
      ObjectSetInteger(0, obj_line_name, OBJPROP_SELECTABLE, 0);
      ObjectSetInteger(0, obj_line_name, OBJPROP_BACK, 1);
   }

   double pip_value = Point * ((Digits == 3 || Digits == 5) ? 10 : 1);
   double text_price_val;
   int text_anchor_val;
   datetime text_time_anchor_val = time1_line;

   if(is_high_swing_type)
   {
      text_price_val = price_level + (InpTextShiftYPips * pip_value);
      text_anchor_val = ANCHOR_LEFT_LOWER;
   }
   else
   {
      text_price_val = price_level - (InpTextShiftYPips * pip_value);
      text_anchor_val = ANCHOR_LEFT_UPPER;
   }
   
   if(ObjectCreate(0, obj_text_name, OBJ_TEXT, 0, text_time_anchor_val, text_price_val))
   {
      ObjectSetString(0, obj_text_name, OBJPROP_TEXT, label_text);
      ObjectSetInteger(0, obj_text_name, OBJPROP_COLOR, marker_color);
      ObjectSetInteger(0, obj_text_name, OBJPROP_FONTSIZE, InpTextFontSize);
      ObjectSetString(0, obj_text_name, OBJPROP_FONT, "Arial Italic");
      ObjectSetInteger(0, obj_text_name, OBJPROP_ANCHOR, text_anchor_val);
      ObjectSetInteger(0, obj_text_name, OBJPROP_SELECTABLE, 0);
      ObjectSetInteger(0, obj_text_name, OBJPROP_BACK, 0);
   }
}

void ModifyMarkerText(string obj_name_base, string new_text)
{
   string obj_text_name = obj_name_base + "_Text";
   if(ObjectFind(0, obj_text_name) != -1)
   {
      ObjectSetString(0, obj_text_name, OBJPROP_TEXT, new_text);
   }
}

bool isNewBar()
{
   datetime barOpenTime = iTime(Symbol(), Period(), 0);
   if(barOpenTime > g_last_calc_time_swing_internal)
   {
      g_last_calc_time_swing_internal = barOpenTime;
      return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Calculate                       |
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
      if(rates_total < (InpSwingCandles * 2) + 2)
      return(0);

   if(isNewBar())
   {

      ObjectsDeleteAll(0, g_obj_prefix);
      ArrayFree(g_swing_points_list);
      g_last_swing_high_price = 0; g_last_high_label = "";
      g_last_swing_low_price = 0;  g_last_low_label = "";
      
      int scan_limit = InpMaxBarsToScan;
      if(rates_total - InpSwingCandles < scan_limit)
      {
         scan_limit = rates_total - InpSwingCandles - 1;
      }

      for(int i = scan_limit; i >= InpSwingCandles; i--)
      {
         int j, k, total_swings;
         SSwingPoint prev_swing;
         datetime prev_swing_line_end_time;
         
         bool is_ith_bar_swing_high = true;
         for(j = 1; j <= InpSwingCandles; j++)
         {
            if(high[i] < high[i-j] || high[i] < high[i+j]) { is_ith_bar_swing_high = false; break; }
            if((high[i] == high[i-j] && (i-j)!=i) || (high[i] == high[i+j] && (i+j)!=i)) { is_ith_bar_swing_high = false; break; }
         }

         bool is_ith_bar_swing_low = true;
         for(j = 1; j <= InpSwingCandles; j++)
         {
            if(low[i] > low[i-j] || low[i] > low[i+j]) { is_ith_bar_swing_low = false; break; }
            if((low[i] == low[i-j] && (i-j)!=i) || (low[i] == low[i+j] && (i+j)!=i)) { is_ith_bar_swing_low = false; break; }
         }

         if(is_ith_bar_swing_high && is_ith_bar_swing_low) continue;

         string label_to_draw = "";
         color color_to_draw = clrNONE;
         bool is_high_type_swing = false;
         double price_level_swing = 0;

         if(is_ith_bar_swing_high)
         {
            price_level_swing = high[i];
            is_high_type_swing = true;
            color_to_draw = InpColorSwingHigh;

            if(g_last_swing_high_price == 0 || price_level_swing > g_last_swing_high_price) label_to_draw = "HH";
            else if(price_level_swing < g_last_swing_high_price) label_to_draw = "LH";
            else label_to_draw = g_last_high_label != "" ? g_last_high_label : "HH";

            total_swings = ArraySize(g_swing_points_list);
            for(k = total_swings - 1; k >= 0; k--)
            {
               prev_swing = g_swing_points_list[k];
               if(!prev_swing.is_high) continue;

               prev_swing_line_end_time = (datetime)((long)prev_swing.time + (InpLineLengthBars > 0 ? InpLineLengthBars - 1 : 0) * (Period() * 60));
               if(time[i] > prev_swing_line_end_time) continue;

               if(high[i] > prev_swing.price && MathMin(open[i], close[i]) < prev_swing.price)
               {
                  if(prev_swing.label == "LH") { label_to_draw = "LH"; }
                  ModifyMarkerText(prev_swing.obj_name_base, " Sweep ");
                  g_swing_points_list[k].label = " Sweep ";
                  break;
               }
            }
            g_last_swing_high_price = price_level_swing;
            g_last_high_label = label_to_draw;
         }
         else if(is_ith_bar_swing_low)
         {
            price_level_swing = low[i];
            is_high_type_swing = false;
            color_to_draw = InpColorSwingLow;

            if(g_last_swing_low_price == 0 || price_level_swing < g_last_swing_low_price) label_to_draw = "LL";
            else if(price_level_swing > g_last_swing_low_price) label_to_draw = "HL";
            else label_to_draw = g_last_low_label != "" ? g_last_low_label : "LL";
               
            total_swings = ArraySize(g_swing_points_list);
            for(k = total_swings - 1; k >= 0; k--)
            {
               prev_swing = g_swing_points_list[k];
               if(prev_swing.is_high) continue;
            
               prev_swing_line_end_time = (datetime)((long)prev_swing.time + (InpLineLengthBars > 0 ? InpLineLengthBars - 1 : 0) * (Period() * 60));
               if(time[i] > prev_swing_line_end_time) continue;

               if(low[i] < prev_swing.price && MathMax(open[i], close[i]) > prev_swing.price)
               {
                  if(prev_swing.label == "HL") { label_to_draw = "HL"; }
                  ModifyMarkerText(prev_swing.obj_name_base, " Sweep ");
                  g_swing_points_list[k].label = " Sweep ";
                  break;
               }
            }
            g_last_swing_low_price = price_level_swing;
            g_last_low_label = label_to_draw;
         }

         if(label_to_draw != "")
         {
            string obj_base = g_obj_prefix + TimeToStr(time[i], TIME_DATE | TIME_SECONDS);
            DrawMarkerLineWithText(obj_base, time[i], price_level_swing, is_high_type_swing, label_to_draw, color_to_draw);
            
            int list_size = ArraySize(g_swing_points_list);
            ArrayResize(g_swing_points_list, list_size + 1);
            g_swing_points_list[list_size].time = time[i];
            g_swing_points_list[list_size].price = price_level_swing;
            g_swing_points_list[list_size].label = label_to_draw;
            g_swing_points_list[list_size].is_high = is_high_type_swing;
            g_swing_points_list[list_size].obj_name_base = obj_base;
         }
      } 
   } 
   
   return(rates_total);
}
//+------------------------------------------------------------------+
