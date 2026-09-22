//+------------------------------------------------------------------+
//|                                                    InsideBar.mq4 |
//|                                                      reza rahmad |
//|                                             rezarahmad@gmail.com |
//+------------------------------------------------------------------+
#property copyright "reza rahmad"
#property link      "rezarahmad@gmail.com"
#property version   "1.00"
#property strict
#property indicator_chart_window

//--- Input parameters (Basic)
input int      BarsToKeep           = 50;        // Number of candles backward to keep rectangles
input int      ForwardBars          = 5;         // Rectangle extension (bars ahead from big candle)
input bool     RectangleFill        = true;      // Fill rectangle with color

//--- Color inputs
input bool     AutoColorByDirection = true;     // Auto color based on small candle direction
input color    BullishColor         = clrGreen;  // Color for bullish signal
input color    BearishColor         = clrRed;    // Color for bearish signal
input color    NeutralColor         = clrBlue;   // Color for neutral signal (border when auto off)
input color    RectangleFillColor   = clrBlue;   // Fill color when auto color is off

//--- Premium features
input bool     EnableAlert          = true;      // Enable notifications (popup, push, sound)
input bool     EnableLabel          = true;      // Show text labels on chart
input bool     LabelOnlyOnNewBar    = true;      // Show label only on latest pattern
input bool     FilterDirection      = false;     // Show only bullish/bearish signals (ignore neutral)

//--- Global variables
string         ExtPrefix            = "IBRect_";
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
   string msg = StringFormat("Inside Bar %s | %s | Range: %.5f - %.5f", dir_str, TimeToString(bar_time), low, high);

//--- Send alerts
   if(!IsTesting())
     {
      Alert(msg);
      SendNotification(msg);
      PlaySound("alert.wav");
     }
  }

//+------------------------------------------------------------------+
//| Determine direction based on small candle close vs open          |
//+------------------------------------------------------------------+
int GetDirection(double open, double close)
  {
   if(close > open)
      return(1);  // bullish
   if(close < open)
      return(-1); // bearish
   return(0);     // neutral
  }

//+------------------------------------------------------------------+
//| Get color based on direction (for auto mode)                     |
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

//--- Delete old rectangles
   DeleteOldRectangles(time[0]);

//--- Initialize loop variables
   int limit = MathMin(rates_total - 3, ExtBarsToKeep);
   int last_pattern_bar = -1;

//--- Find latest pattern for label (if LabelOnlyOnNewBar is enabled)
   if(LabelOnlyOnNewBar && EnableLabel)
     {
      for(int i = 0; i <= limit; i++)
        {
         int smallIdx = i + 1; // Small candle
         int bigIdx   = i + 2; // Big candle

         if(high[smallIdx] <= high[bigIdx] && low[smallIdx] >= low[bigIdx])
           {
            int dir = GetDirection(open[smallIdx], close[smallIdx]);
            if(!FilterDirection || dir != 0)
              {
               last_pattern_bar = bigIdx;
               break;
              }
           }
        }
     }

//--- Main loop - detect inside bars
   for(int i = limit; i >= 0; i--)
     {
      int smallIdx = i + 1;
      int bigIdx   = i + 2;

      //--- Inside bar condition
      if(high[smallIdx] <= high[bigIdx] && low[smallIdx] >= low[bigIdx])
        {
         int direction = GetDirection(open[smallIdx], close[smallIdx]);
         if(FilterDirection && direction == 0)
            continue;

         int targetIdx = bigIdx - ExtForwardBars;
         if(targetIdx < 0)
            targetIdx = 0;

         string obj_name = ExtPrefix + IntegerToString((long)time[bigIdx]);

         //--- Determine colors
         color border_color, bg_color;
         if(AutoColorByDirection)
           {
            border_color = GetColorByDirection(direction);
            bg_color = border_color;   // same color for fill
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
               datetime left_time  = time[bigIdx];
               datetime right_time = time[targetIdx] + PeriodSeconds();
               double   high_level = high[bigIdx];
               double   low_level  = low[bigIdx];

               ObjectSetInteger(0, obj_name, OBJPROP_TIME, 0, left_time);
               ObjectSetInteger(0, obj_name, OBJPROP_TIME, 1, right_time);
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

         //--- Text label
         if(EnableLabel)
           {
            bool draw_label = (!LabelOnlyOnNewBar || bigIdx == last_pattern_bar);
            if(draw_label)
              {
               string label_name = ExtPrefix + "Label_" + IntegerToString((long)time[bigIdx]);
               if(ObjectFind(0, label_name) == -1)
                 {
                  //--- shift distance by 4 bars to the right based on targetIdx
                  datetime label_time = time[targetIdx] + PeriodSeconds() * 4;
                  double label_price = high[bigIdx] + (high[bigIdx] - low[bigIdx]) * 0.2;

                  if(ObjectCreate(0, label_name, OBJ_TEXT, 0, label_time, label_price))
                    {
                     string dir_text = "";
                     if(FilterDirection || AutoColorByDirection)
                        dir_text = (direction == 1) ? " ^ BULLISH" : ((direction == -1) ? " v BEARISH" : "");
                     string text = "Inside Bar" + dir_text;
                     ObjectSetString(0, label_name, OBJPROP_TEXT, text);
                     ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 9);
                     ObjectSetInteger(0, label_name, OBJPROP_COLOR, (long)border_color);
                     ObjectSetInteger(0, label_name, OBJPROP_BACK, false);
                     ObjectSetInteger(0, label_name, OBJPROP_SELECTABLE, false);

                     //--- set Anchor so the text is left-aligned
                     ObjectSetInteger(0, label_name, OBJPROP_ANCHOR, ANCHOR_LEFT);
                    }
                 }
              }
           }

         //--- Send alert only once per pattern
         if(EnableAlert && time[smallIdx] > ExtLastAlertTime)
           {
            ExtLastAlertTime = time[smallIdx];
            SendAlert(direction, time[bigIdx], high[bigIdx], low[bigIdx]);
           }
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
