//+------------------------------------------------------------------+
//|                                      RJO_Daily_Pivot_Levels.mq5  |
//|                         Free Code Base indicator for MetaTrader 5 |
//|                                      Copyright 2026, RJO          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, RJO"
#property version   "1.00"
#property description "Daily Pivot Points for MT5 using the previous completed D1 candle."
#property description "Supports Classic and Fibonacci formulas."
#property description "Displays PP, R1-R3 and S1-S3 on any chart timeframe."
#property indicator_chart_window
#property indicator_plots 0

//--- Pivot calculation method
enum ENUM_RJO_PIVOT_METHOD
  {
   RJO_PIVOT_CLASSIC = 0,     // Classic
   RJO_PIVOT_FIBONACCI = 1   // Fibonacci
  };

//--- Inputs
input ENUM_RJO_PIVOT_METHOD InpPivotMethod = RJO_PIVOT_CLASSIC;

input bool  InpShowPP = true;
input bool  InpShowR1 = true;
input bool  InpShowR2 = true;
input bool  InpShowR3 = true;
input bool  InpShowS1 = true;
input bool  InpShowS2 = true;
input bool  InpShowS3 = true;

input color InpPPColor = clrGold;
input color InpResistanceColor = clrTomato;
input color InpSupportColor = clrDeepSkyBlue;

input ENUM_LINE_STYLE InpLineStyle = STYLE_DASH;
input int   InpLineWidth = 1;

input bool  InpShowLabels = true;
input int   InpLabelFontSize = 8;
input int   InpLabelBarsShift = 2;

input bool  InpDrawInBackground = true;
input string InpObjectPrefix = "RJO_DPivot_";

//--- Internal state
datetime g_last_daily_bar = 0;
datetime g_last_chart_bar = 0;

double g_pp = 0.0;
double g_r1 = 0.0;
double g_r2 = 0.0;
double g_r3 = 0.0;
double g_s1 = 0.0;
double g_s2 = 0.0;
double g_s3 = 0.0;

//+------------------------------------------------------------------+
//| Indicator initialization                                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   IndicatorSetString(INDICATOR_SHORTNAME,"RJO Daily Pivot Levels");
   DeletePivotObjects();

   if(!UpdatePivotLevels())
      Print("RJO Daily Pivot Levels: waiting for enough D1 history...");

   g_last_daily_bar = iTime(_Symbol,PERIOD_D1,0);
   g_last_chart_bar = iTime(_Symbol,_Period,0);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Indicator deinitialization                                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   DeletePivotObjects();
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Main calculation                                                 |
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
   if(rates_total < 2)
      return(0);

   datetime current_daily_bar = iTime(_Symbol,PERIOD_D1,0);
   datetime current_chart_bar = iTime(_Symbol,_Period,0);

   // Recalculate only when a new D1 candle starts, or after first load.
   if(prev_calculated == 0 || current_daily_bar != g_last_daily_bar)
     {
      if(UpdatePivotLevels())
         g_last_daily_bar = current_daily_bar;
     }
   // Move labels when the chart creates a new bar.
   else if(current_chart_bar != g_last_chart_bar)
     {
      UpdateAllLabelPositions();
     }

   g_last_chart_bar = current_chart_bar;
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Load previous completed daily candle and calculate levels        |
//+------------------------------------------------------------------+
bool UpdatePivotLevels()
  {
   MqlRates daily[];
   ArraySetAsSeries(daily,true);

   ResetLastError();
   if(CopyRates(_Symbol,PERIOD_D1,1,1,daily) != 1)
     {
      PrintFormat("RJO Daily Pivot Levels: CopyRates failed. Error %d",GetLastError());
      return(false);
     }

   const double H = daily[0].high;
   const double L = daily[0].low;
   const double C = daily[0].close;

   if(H <= 0.0 || L <= 0.0 || H < L)
      return(false);

   const double range = H - L;
   g_pp = (H + L + C) / 3.0;

   if(InpPivotMethod == RJO_PIVOT_FIBONACCI)
     {
      g_r1 = g_pp + 0.382 * range;
      g_r2 = g_pp + 0.618 * range;
      g_r3 = g_pp + 1.000 * range;

      g_s1 = g_pp - 0.382 * range;
      g_s2 = g_pp - 0.618 * range;
      g_s3 = g_pp - 1.000 * range;
     }
   else
     {
      // Classic floor-trader pivot formulas
      g_r1 = 2.0 * g_pp - L;
      g_s1 = 2.0 * g_pp - H;

      g_r2 = g_pp + range;
      g_s2 = g_pp - range;

      g_r3 = H + 2.0 * (g_pp - L);
      g_s3 = L - 2.0 * (H - g_pp);
     }

   DrawLevel("PP",g_pp,InpPPColor,InpShowPP);
   DrawLevel("R1",g_r1,InpResistanceColor,InpShowR1);
   DrawLevel("R2",g_r2,InpResistanceColor,InpShowR2);
   DrawLevel("R3",g_r3,InpResistanceColor,InpShowR3);
   DrawLevel("S1",g_s1,InpSupportColor,InpShowS1);
   DrawLevel("S2",g_s2,InpSupportColor,InpShowS2);
   DrawLevel("S3",g_s3,InpSupportColor,InpShowS3);

   ChartRedraw(0);
   return(true);
  }

//+------------------------------------------------------------------+
//| Draw or update one pivot level                                   |
//+------------------------------------------------------------------+
void DrawLevel(const string level_name,
               const double price,
               const color level_color,
               const bool show_level)
  {
   const string line_name  = InpObjectPrefix + level_name + "_LINE";
   const string label_name = InpObjectPrefix + level_name + "_LABEL";

   if(!show_level)
     {
      ObjectDelete(0,line_name);
      ObjectDelete(0,label_name);
      return;
     }

   //--- Horizontal line
   if(ObjectFind(0,line_name) < 0)
     {
      if(!ObjectCreate(0,line_name,OBJ_HLINE,0,0,price))
        {
         PrintFormat("RJO Daily Pivot Levels: cannot create %s. Error %d",
                     line_name,GetLastError());
         return;
        }
     }

   ObjectSetDouble(0,line_name,OBJPROP_PRICE,NormalizeDouble(price,_Digits));
   ObjectSetInteger(0,line_name,OBJPROP_COLOR,level_color);
   ObjectSetInteger(0,line_name,OBJPROP_STYLE,InpLineStyle);
   ObjectSetInteger(0,line_name,OBJPROP_WIDTH,MathMax(1,InpLineWidth));
   ObjectSetInteger(0,line_name,OBJPROP_BACK,InpDrawInBackground);
   ObjectSetInteger(0,line_name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,line_name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,line_name,OBJPROP_HIDDEN,true);
   ObjectSetString(0,line_name,OBJPROP_TOOLTIP,
                   level_name + "  " + DoubleToString(price,_Digits));

   //--- Optional text label
   if(!InpShowLabels)
     {
      ObjectDelete(0,label_name);
      return;
     }

   datetime label_time = GetLabelTime();

   if(ObjectFind(0,label_name) < 0)
     {
      if(!ObjectCreate(0,label_name,OBJ_TEXT,0,label_time,price))
        {
         PrintFormat("RJO Daily Pivot Levels: cannot create %s. Error %d",
                     label_name,GetLastError());
         return;
        }
     }
   else
     {
      ObjectMove(0,label_name,0,label_time,price);
     }

   ObjectSetString(0,label_name,OBJPROP_TEXT,
                   level_name + "  " + DoubleToString(price,_Digits));
   ObjectSetString(0,label_name,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,label_name,OBJPROP_FONTSIZE,MathMax(6,InpLabelFontSize));
   ObjectSetInteger(0,label_name,OBJPROP_COLOR,level_color);
   ObjectSetInteger(0,label_name,OBJPROP_BACK,false);
   ObjectSetInteger(0,label_name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,label_name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,label_name,OBJPROP_HIDDEN,true);
  }

//+------------------------------------------------------------------+
//| Move all visible labels to the latest chart area                 |
//+------------------------------------------------------------------+
void UpdateAllLabelPositions()
  {
   if(!InpShowLabels)
      return;

   MoveLabel("PP",g_pp,InpShowPP);
   MoveLabel("R1",g_r1,InpShowR1);
   MoveLabel("R2",g_r2,InpShowR2);
   MoveLabel("R3",g_r3,InpShowR3);
   MoveLabel("S1",g_s1,InpShowS1);
   MoveLabel("S2",g_s2,InpShowS2);
   MoveLabel("S3",g_s3,InpShowS3);

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Move one label                                                   |
//+------------------------------------------------------------------+
void MoveLabel(const string level_name,const double price,const bool show_level)
  {
   if(!show_level || price <= 0.0)
      return;

   const string label_name = InpObjectPrefix + level_name + "_LABEL";
   if(ObjectFind(0,label_name) >= 0)
      ObjectMove(0,label_name,0,GetLabelTime(),price);
  }

//+------------------------------------------------------------------+
//| Time coordinate used for labels                                  |
//+------------------------------------------------------------------+
datetime GetLabelTime()
  {
   datetime t = iTime(_Symbol,_Period,0);
   int seconds_per_bar = PeriodSeconds(_Period);

   if(seconds_per_bar <= 0)
      seconds_per_bar = 60;

   int shift = MathMax(0,InpLabelBarsShift);
   return(t + (datetime)(seconds_per_bar * shift));
  }

//+------------------------------------------------------------------+
//| Delete only objects created by this indicator                    |
//+------------------------------------------------------------------+
void DeletePivotObjects()
  {
   const string levels[7] = {"PP","R1","R2","R3","S1","S2","S3"};

   for(int i=0;i<7;i++)
     {
      ObjectDelete(0,InpObjectPrefix + levels[i] + "_LINE");
      ObjectDelete(0,InpObjectPrefix + levels[i] + "_LABEL");
     }
  }
//+------------------------------------------------------------------+
