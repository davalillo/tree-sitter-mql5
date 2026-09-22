//+------------------------------------------------------------------+
//|                                                 FairValueGap.mq4 |
//|                                                      reza rahmad |
//|                                             rezarahmad@gmail.com |
//+------------------------------------------------------------------+
#property copyright "reza rahmad"
#property link      "rezarahmad@gmail.com"
#property version   "1.00"
#property strict
#property indicator_chart_window

//--- Input parameters
input int      BarsToKeep           = 500;        // Number of candles backward to scan
input int      ForwardBars          = 18;         // Rectangle extension (bars ahead)
input bool     RectangleFill        = true;       // Fill rectangle with color

//--- Color inputs
input bool     AutoColorByDirection = false;      // Auto color based on FVG direction
input color    BullishColor         = clrGreen;   // Color for bullish FVG
input color    BearishColor         = clrRed;     // Color for bearish FVG
input color    NeutralColor         = clrSkyBlue; // Color for neutral border
input color    RectangleFillColor   = clrSkyBlue; // Fill color when auto color is off

//--- Premium features
input bool     EnableAlert          = true;       // Enable notifications (popup, push, sound)
input bool     EnableLabel          = true;       // Show text labels on chart
input bool     LabelOnlyOnNewBar    = true;       // Show label only on latest FVG

//--- Global variables
string         ExtPrefix            = "FVGRect_";
datetime       ExtLastBarTime       = 0;
datetime       ExtLastAlertTime     = 0;
int            ExtBarsToKeep;
int            ExtForwardBars;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Check and assign inputs
   ExtBarsToKeep  = (BarsToKeep < 1) ? 1 : BarsToKeep;
   ExtForwardBars = (ForwardBars < 1) ? 1 : ForwardBars;
   ExtLastAlertTime = 0;

//--- Limits to prevent Timeout and MTF errors in Tester
   if(IsTesting())
     {
      ExtBarsToKeep = 50;
     }

//--- Initialization complete
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- Remove all indicator objects
   ObjectsDeleteAll(0, ExtPrefix);
  }

//+------------------------------------------------------------------+
//| Delete rectangles older than ExtBarsToKeep bars                  |
//+------------------------------------------------------------------+
void DeleteOldRectangles(datetime current_time)
  {
//--- Calculate oldest allowed time
   int seconds_per_bar = PeriodSeconds();
   datetime oldest_time = current_time - ExtBarsToKeep * seconds_per_bar;

//--- Iterate backwards to delete old rectangles
   for(int i = ObjectsTotal(0, 0, OBJ_RECTANGLE) - 1; i >= 0; i--)
     {
      string obj_name = ObjectName(0, i, 0, OBJ_RECTANGLE);
      if(StringFind(obj_name, ExtPrefix) == 0)
        {
         datetime left_time = (datetime)ObjectGetInteger(0, obj_name, OBJPROP_TIME, 0);
         if(left_time < oldest_time)
           {
            ObjectDelete(0, obj_name);
            string label_name = ExtPrefix + "Label_" + StringSubstr(obj_name, StringLen(ExtPrefix));
            ObjectDelete(0, label_name);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Send alert notification                                          |
//+------------------------------------------------------------------+
void SendAlert(int direction, datetime bar_time, double high, double low)
  {
//--- Format message
   string dir_str = (direction == 1) ? "BULLISH" : ((direction == -1) ? "BEARISH" : "NEUTRAL");
   string msg = StringFormat("Fair Value Gap %s | %s | Range: %.5f - %.5f", dir_str, TimeToString(bar_time), low, high);
//--- Send alerts
   if(!IsTesting())
     {
      Alert(msg);
      SendNotification(msg);
      PlaySound("alert.wav");
     }
  }

//+------------------------------------------------------------------+
//| Get color based on FVG direction                                 |
//+------------------------------------------------------------------+
color GetColorByDirection(int direction)
  {
   if(direction == 1)
      return(BullishColor);
   if(direction == -1)
      return(BearishColor);
   return(NeutralColor);
  }

//+------------------------------------------------------------------+
//| Draw previous day high and low lines                             |
//+------------------------------------------------------------------+
void DrawDailyLines()
  {
//--- Fetch previous day high and low
   double prev_high = iHigh(_Symbol, PERIOD_D1, 1);
   double prev_low = iLow(_Symbol, PERIOD_D1, 1);

   if(prev_high > 0 && prev_low > 0)
     {
      string high_name = ExtPrefix + "PrevDayHigh";
      if(ObjectFind(0, high_name) == -1 || ObjectGetDouble(0, high_name, OBJPROP_PRICE, 0) != prev_high)
        {
         ObjectDelete(0, high_name);
         ObjectCreate(0, high_name, OBJ_HLINE, 0, 0, prev_high);
         ObjectSetDouble(0, high_name, OBJPROP_PRICE, 0, prev_high);
         ObjectSetInteger(0, high_name, OBJPROP_COLOR, BearishColor);
         ObjectSetInteger(0, high_name, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetString(0, high_name, OBJPROP_TEXT, "Break High -> Buy, Fakeout -> Sell");
         ObjectSetInteger(0, high_name, OBJPROP_HIDDEN, false);
        }

      string low_name = ExtPrefix + "PrevDayLow";
      if(ObjectFind(0, low_name) == -1 || ObjectGetDouble(0, low_name, OBJPROP_PRICE, 0) != prev_low)
        {
         ObjectDelete(0, low_name);
         ObjectCreate(0, low_name, OBJ_HLINE, 0, 0, prev_low);
         ObjectSetDouble(0, low_name, OBJPROP_PRICE, 0, prev_low);
         ObjectSetInteger(0, low_name, OBJPROP_COLOR, BullishColor);
         ObjectSetInteger(0, low_name, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetString(0, low_name, OBJPROP_TEXT, "Break Low -> Sell, Fakeout -> Buy");
         ObjectSetInteger(0, low_name, OBJPROP_HIDDEN, false);
        }

      ChartSetInteger(0, CHART_SHOW_OBJECT_DESCR, true);
     }
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
//--- Check for enough bars
   if(rates_total < 3)
      return(0);

//--- Suppress historical alerts on first run
   if(prev_calculated == 0)
      ExtLastAlertTime = time[0];

//--- Check for new bar
   if(time[0] == ExtLastBarTime)
      return(rates_total);
   ExtLastBarTime = time[0];

//--- Draw daily lines on new bar (Disabled in tester to prevent MTF data sync errors)
   if(!IsTesting())
      DrawDailyLines();

//--- Delete old rectangles
   DeleteOldRectangles(time[0]);

//--- Initialize loop variables
   int limit = MathMin(rates_total - 3, ExtBarsToKeep);
   int last_pattern_bar = -1;

//--- Find latest pattern for label
   if(LabelOnlyOnNewBar && EnableLabel)
     {
      for(int i = 0; i <= limit; i++)
        {
         int c1 = i + 2; // Oldest bar of the 3-bar pattern
         int c3 = i;     // Newest bar of the 3-bar pattern

         if(high[c1] < low[c3] || low[c1] > high[c3])
           {
            bool is_touched = false;
            int dir = (high[c1] < low[c3]) ? 1 : -1;
            double h_level = (dir == 1) ? low[c3] : low[c1];
            double l_level = (dir == 1) ? high[c1] : high[c3];

            for(int j = c3 - 1; j >= 0; j--)
              {
               if(dir == 1 && low[j] <= h_level)
                 {
                  is_touched = true;
                  break;
                 }
               if(dir == -1 && high[j] >= l_level)
                 {
                  is_touched = true;
                  break;
                 }
              }

            if(!is_touched)
              {
               last_pattern_bar = c3;
               break;
              }
           }
        }
     }

//--- Main loop to detect FVG
   for(int i = limit; i >= 0; i--)
     {
      int c1 = i + 2;
      int c3 = i;

      int direction = 0;
      double high_level = 0;
      double low_level = 0;

      if(high[c1] < low[c3])
        {
         direction = 1; // Bullish FVG
         high_level = low[c3];
         low_level = high[c1];
        }
      else
         if(low[c1] > high[c3])
           {
            direction = -1; // Bearish FVG
            high_level = low[c1];
            low_level = high[c3];
           }

      if(direction != 0)
        {
         bool is_touched = false;
         for(int j = c3 - 1; j >= 0; j--)
           {
            if(direction == 1 && low[j] <= high_level)
              {
               is_touched = true;
               break;
              }
            if(direction == -1 && high[j] >= low_level)
              {
               is_touched = true;
               break;
              }
           }

         string obj_name = ExtPrefix + IntegerToString((long)time[c3]);
         string label_name = ExtPrefix + "Label_" + IntegerToString((long)time[c3]);

         if(is_touched)
           {
            ObjectDelete(0, obj_name);
            ObjectDelete(0, label_name);
            continue;
           }

         datetime right_time = time[0] + ExtForwardBars * PeriodSeconds();

         //--- Determine colors
         color border_color, bg_color;
         if(AutoColorByDirection)
           {
            border_color = GetColorByDirection(direction);
            bg_color = border_color;
           }
         else
           {
            border_color = NeutralColor;
            bg_color = RectangleFillColor;
           }

         //--- Create rectangle if not exists
         if(ObjectFind(0, obj_name) == -1)
           {
            if(ObjectCreate(0, obj_name, OBJ_RECTANGLE, 0, 0, 0, 0, 0))
              {
               datetime left_time = time[c1];

               ObjectSetInteger(0, obj_name, OBJPROP_TIME, 0, left_time);
               ObjectSetDouble(0, obj_name, OBJPROP_PRICE, 0, high_level);
               ObjectSetDouble(0, obj_name, OBJPROP_PRICE, 1, low_level);

               //--- Color and Fill settings
               if(RectangleFill)
                 {
                  ObjectSetInteger(0, obj_name, OBJPROP_COLOR, (long)bg_color);
                  ObjectSetInteger(0, obj_name, OBJPROP_FILL, true);
                 }
               else
                 {
                  ObjectSetInteger(0, obj_name, OBJPROP_COLOR, (long)border_color);
                  ObjectSetInteger(0, obj_name, OBJPROP_FILL, false);
                 }

               //--- Ensure background is drawn behind chart data
               ObjectSetInteger(0, obj_name, OBJPROP_BACK, true);
               ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 1);
               ObjectSetInteger(0, obj_name, OBJPROP_STYLE, STYLE_SOLID);
               ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, false);
               ObjectSetInteger(0, obj_name, OBJPROP_HIDDEN, false);
              }
           }

         //--- Update right time continuously
         ObjectSetInteger(0, obj_name, OBJPROP_TIME, 1, right_time);

         //--- Text label
         if(EnableLabel)
           {
            bool draw_label = (!LabelOnlyOnNewBar || c3 == last_pattern_bar);
            if(draw_label)
              {
               if(ObjectFind(0, label_name) == -1)
                 {
                  //--- increase distance by shifting 4 bars to the right
                  datetime label_time = right_time + PeriodSeconds() * 4;
                  double label_price = high_level + (high_level - low_level) * 0.2;
                  if(ObjectCreate(0, label_name, OBJ_TEXT, 0, label_time, label_price))
                    {
                     string dir_text = "";
                     if(AutoColorByDirection)
                        dir_text = (direction == 1) ? " ^ BULLISH" : ((direction == -1) ? " v BEARISH" : "");
                     string text = "FVG" + dir_text;
                     ObjectSetString(0, label_name, OBJPROP_TEXT, text);
                     ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 9);
                     ObjectSetInteger(0, label_name, OBJPROP_COLOR, (long)border_color);
                     ObjectSetInteger(0, label_name, OBJPROP_BACK, false);
                     ObjectSetInteger(0, label_name, OBJPROP_SELECTABLE, false);

                     //--- set Anchor so the text is left-aligned
                     ObjectSetInteger(0, label_name, OBJPROP_ANCHOR, ANCHOR_LEFT);
                    }
                 }

               //--- Update label continuously
               ObjectSetInteger(0, label_name, OBJPROP_TIME, 0, right_time + PeriodSeconds() * 4);
              }
           }

         //--- Send alert only once per pattern
         if(EnableAlert && time[c3] > ExtLastAlertTime)
           {
            ExtLastAlertTime = time[c3];
            SendAlert(direction, time[c3], high_level, low_level);
           }
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
