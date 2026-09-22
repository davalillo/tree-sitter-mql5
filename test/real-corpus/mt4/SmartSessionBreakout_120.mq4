//+------------------------------------------------------------------+
//|                                         SmartSessionBreakout.mq4 |
//|                                Copyright 2026, Antonios Kokkalis |
//|                           https://www.mql5.com/en/users/palaki06 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antonios Kokkalis"
#property link      "https://www.mql5.com/en/users/palaki06"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_color1 clrLimeGreen  // Buy Signal Arrow
#property indicator_color2 clrRed       // Sell Signal Arrow
#property indicator_color3 clrDodgerBlue // Upper Range Level
#property indicator_color4 clrDeepPink   // Lower Range Level
#property indicator_width1 2
#property indicator_width2 2
#property indicator_width3 1
#property indicator_width4 1

//--- Indicator Buffers
double BufferBuy[];
double BufferSell[];
double BufferUpperLevel[];
double BufferLowerLevel[];

//--- Input Parameters Groups
//+------------------------------------------------------------------+
//| Session & Range Settings                                         |
//+------------------------------------------------------------------+
input string   InpAsianStart    = "00:00";    // Asian Session Start (Broker Time HH:MM)
input string   InpAsianEnd      = "08:00";    // Asian Session End (Broker Time HH:MM)
input int      InpMaxDays       = 30;         // Max Days to Process on Chart
input double   InpMinBoxPips    = 8.0;        // Min Range Box Height (Pips)
input double   InpMaxBoxPips    = 70.0;       // Max Range Box Height (Pips)
input bool     InpSignalOnClose = true;       // Confirm Signal on Bar Close (Non-Repainting)

//+------------------------------------------------------------------+
//| Volatility & Filter Settings                                     |
//+------------------------------------------------------------------+
input bool     InpUseATRFilter  = true;       // Enable ATR Expansion Filter
input int      InpATRPeriod     = 14;         // ATR Period
input double   InpATRCoeff      = 0.8;        // Min Breakout Candle Body vs ATR Ratio

//+------------------------------------------------------------------+
//| Visual & Colors Settings                                         |
//+------------------------------------------------------------------+
input color    InpBoxColor      = C'30,50,90'; // Asian Box Color (Dark Navy)
input bool     InpFillBox       = true;       // Fill Asian Range Box
input color    InpUpperLineCol  = clrDodgerBlue;// Upper Line Color
input color    InpLowerLineCol  = clrDeepPink; // Lower Line Color

//+------------------------------------------------------------------+
//| Dashboard Panel Settings                                         |
//+------------------------------------------------------------------+
input bool     InpShowDash      = true;       // Show On-Screen Dashboard Panel
input ENUM_BASE_CORNER InpCorner= CORNER_RIGHT_UPPER; // Panel Position Corner
input color    InpBgColor       = C'18,24,38';// Dashboard Background Color
input color    InpTxtColor      = clrWhite;   // Dashboard Text Color
input color    InpAccentColor   = C'0,195,255';// Dashboard Accent Highlight

//+------------------------------------------------------------------+
//| Notification Settings                                            |
//+------------------------------------------------------------------+
input bool     InpPopupAlert    = true;       // Enable Pop-up Alert
input bool     InpSoundAlert    = true;       // Enable Sound Alert
input bool     InpSendEmail     = false;      // Enable Email Alert
input bool     InpSendPush      = false;      // Enable Push Alert to Mobile

//--- Global Variables
datetime g_lastAlertTime = 0;
string   g_prefix        = "SSB_";
double   g_pipSize       = 0.0001;

//--- Function Prototypes
void DrawSessionBox(int dayId, datetime tStart, datetime tEnd, double highVal, double lowVal);
void UpdateDashboard();
void CreateOrUpdateLabel(string id, string text, int x, int y, color col, int fontSize=8, bool isBold=false);
void TriggerAlert(string msg);
void CleanUpObjects();

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // Define Pip Size based on Digits
   if(Digits == 3 || Digits == 5)
      g_pipSize = Point * 10.0;
   else
      g_pipSize = Point;

   // Bind Indicator Buffers
   SetIndexBuffer(0, BufferBuy);
   SetIndexBuffer(1, BufferSell);
   SetIndexBuffer(2, BufferUpperLevel);
   SetIndexBuffer(3, BufferLowerLevel);

   // Set Buffer Styles
   SetIndexStyle(0, DRAW_ARROW, EMPTY, 2, clrLimeGreen);
   SetIndexArrow(0, 233); // Up Arrow
   SetIndexLabel(0, "Buy Breakout Signal");

   SetIndexStyle(1, DRAW_ARROW, EMPTY, 2, clrRed);
   SetIndexArrow(1, 234); // Down Arrow
   SetIndexLabel(1, "Sell Breakout Signal");

   SetIndexStyle(2, DRAW_LINE, STYLE_SOLID, 1, InpUpperLineCol);
   SetIndexLabel(2, "Session Resistance Level");

   SetIndexStyle(3, DRAW_LINE, STYLE_SOLID, 1, InpLowerLineCol);
   SetIndexLabel(3, "Session Support Level");

   // Indicator Short Name
   IndicatorShortName("Smart Session Breakout (" + Symbol() + ")");

   // Initialize Objects
   CleanUpObjects();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanUpObjects();
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
   if(rates_total < 50) return(0);

   int limit = rates_total - prev_calculated;
   if(prev_calculated > 0) limit++;

   // Restrict historical calculations to InpMaxDays for optimization
   int maxBars = iBarShift(NULL, 0, TimeCurrent() - InpMaxDays * 86400);
   if(maxBars > 0 && limit > maxBars) limit = maxBars;

   // Calculate indicator logic for bars
   for(int i = limit - 1; i >= 0; i--)
   {
      BufferBuy[i]        = EMPTY_VALUE;
      BufferSell[i]       = EMPTY_VALUE;
      BufferUpperLevel[i] = EMPTY_VALUE;
      BufferLowerLevel[i] = EMPTY_VALUE;

      datetime curTime = time[i];
      MqlDateTime dt;
      TimeToStruct(curTime, dt);

      // Construct session start & end time for the day of current bar
      datetime dayStart = StringToTime(TimeToStr(curTime, TIME_DATE) + " " + InpAsianStart);
      datetime dayEnd   = StringToTime(TimeToStr(curTime, TIME_DATE) + " " + InpAsianEnd);

      if(dayEnd <= dayStart) dayEnd += 86400; // Overlap handling

      // Process completed Asian session for breakout logic
      if(curTime >= dayEnd)
      {
         int barStart = iBarShift(NULL, 0, dayStart, true);
         int barEnd   = iBarShift(NULL, 0, dayEnd, true);

         if(barStart != -1 && barEnd != -1 && barStart > barEnd)
         {
            int count = barStart - barEnd + 1;
            int highestShift = iHighest(NULL, 0, MODE_HIGH, count, barEnd);
            int lowestShift  = iLowest(NULL, 0, MODE_LOW, count, barEnd);

            if(highestShift != -1 && lowestShift != -1)
            {
               double boxHigh = High[highestShift];
               double boxLow  = Low[lowestShift];
               double boxPips = (boxHigh - boxLow) / g_pipSize;

               // Filter box size
               if(boxPips >= InpMinBoxPips && boxPips <= InpMaxBoxPips)
               {
                  BufferUpperLevel[i] = boxHigh;
                  BufferLowerLevel[i] = boxLow;

                  // Draw Session Visual Box once per day (on live bar calculation)
                  if(i == 0 || (i > 0 && TimeDay(time[i]) != TimeDay(time[i+1])))
                  {
                     DrawSessionBox(dt.day, dayStart, dayEnd, boxHigh, boxLow);
                  }

                  // Breakout Signals evaluation
                  // Non-repainting mode requires bar to be closed (i >= 1)
                  if(!InpSignalOnClose || i >= 1)
                  {
                     double barClose = close[i];
                     double barOpen  = open[i];

                     // ATR expansion filter check
                     double atrVal = iATR(NULL, 0, InpATRPeriod, i);
                     double candleBody = MathAbs(barClose - barOpen);
                     bool atrValid = (!InpUseATRFilter) || (candleBody >= atrVal * InpATRCoeff);

                     // Bullish Breakout Signal
                     if(barOpen <= boxHigh && barClose > boxHigh && atrValid)
                     {
                        BufferBuy[i] = low[i] - 10 * Point;
                        if(i == 1) TriggerAlert("Bullish Breakout Signal detected on " + Symbol() + "!");
                     }
                     // Bearish Breakout Signal
                     else if(barOpen >= boxLow && barClose < boxLow && atrValid)
                     {
                        BufferSell[i] = high[i] + 10 * Point;
                        if(i == 1) TriggerAlert("Bearish Breakout Signal detected on " + Symbol() + "!");
                     }
                  }
               }
            }
         }
      }
   }

   // Update GUI Dashboard
   if(InpShowDash)
   {
      UpdateDashboard();
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Draw Visual Asian Session Rectangle Box                         |
//+------------------------------------------------------------------+
void DrawSessionBox(int dayId, datetime tStart, datetime tEnd, double highVal, double lowVal)
{
   string boxName = g_prefix + "Box_" + IntegerToString(dayId) + "_" + TimeToStr(tStart, TIME_DATE);

   if(ObjectFind(0, boxName) < 0)
   {
      ObjectCreate(0, boxName, OBJ_RECTANGLE, 0, tStart, highVal, tEnd, lowVal);
      ObjectSetInteger(0, boxName, OBJPROP_COLOR, InpBoxColor);
      ObjectSetInteger(0, boxName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, boxName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, boxName, OBJPROP_BACK, InpFillBox);
      ObjectSetInteger(0, boxName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, boxName, OBJPROP_HIDDEN, true);
   }
   else
   {
      ObjectMove(0, boxName, 0, tStart, highVal);
      ObjectMove(0, boxName, 1, tEnd, lowVal);
   }
}

//+------------------------------------------------------------------+
//| Render & Update Modern GUI Dashboard Panel                       |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   int xOffset = 15;
   int yOffset = 25;
   int width   = 220;
   int height  = 160;

   // 1. Panel Background Box
   string bgObj = g_prefix + "Dash_BG";
   if(ObjectFind(0, bgObj) < 0)
   {
      ObjectCreate(0, bgObj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgObj, OBJPROP_CORNER, InpCorner);
      ObjectSetInteger(0, bgObj, OBJPROP_XDISTANCE, xOffset);
      ObjectSetInteger(0, bgObj, OBJPROP_YDISTANCE, yOffset);
      ObjectSetInteger(0, bgObj, OBJPROP_XSIZE, width);
      ObjectSetInteger(0, bgObj, OBJPROP_YSIZE, height);
      ObjectSetInteger(0, bgObj, OBJPROP_BGCOLOR, InpBgColor);
      ObjectSetInteger(0, bgObj, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bgObj, OBJPROP_COLOR, InpAccentColor);
      ObjectSetInteger(0, bgObj, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, bgObj, OBJPROP_BACK, false);
      ObjectSetInteger(0, bgObj, OBJPROP_SELECTABLE, false);
   }

   // Metrics calculations
   double curSpread = (double)MarketInfo(Symbol(), MODE_SPREAD) / (Digits == 3 || Digits == 5 ? 10.0 : 1.0);
   double atrVal    = iATR(Symbol(), 0, InpATRPeriod, 0) / g_pipSize;
   int remainingSec = (int)(Time[0] + PeriodSeconds() - TimeCurrent());
   if(remainingSec < 0) remainingSec = 0;
   string timerStr  = StringFormat("%02d:%02d", remainingSec / 60, remainingSec % 60);

   // Determine Status
   string sessionStatus = "Active Range";
   datetime curTime = TimeCurrent();
   datetime dayStart = StringToTime(TimeToStr(curTime, TIME_DATE) + " " + InpAsianStart);
   datetime dayEnd   = StringToTime(TimeToStr(curTime, TIME_DATE) + " " + InpAsianEnd);
   if(dayEnd <= dayStart) dayEnd += 86400;

   if(curTime >= dayStart && curTime <= dayEnd)
      sessionStatus = "Asian Accumulation";
   else
      sessionStatus = "London/NY Expansion";

   // Rows definition
   CreateOrUpdateLabel("T1", "SMART SESSION BREAKOUT", xOffset + 12, yOffset + 12, InpAccentColor, 9, true);
   CreateOrUpdateLabel("T2", "Symbol: " + Symbol() + " (" + EnumToString((ENUM_TIMEFRAMES)Period()) + ")", xOffset + 12, yOffset + 32, InpTxtColor, 8, false);
   CreateOrUpdateLabel("T3", "Session Phase: " + sessionStatus, xOffset + 12, yOffset + 50, clrGold, 8, false);
   CreateOrUpdateLabel("T4", "Spread: " + DoubleToString(curSpread, 1) + " pips", xOffset + 12, yOffset + 68, InpTxtColor, 8, false);
   CreateOrUpdateLabel("T5", "ATR (" + IntegerToString(InpATRPeriod) + "): " + DoubleToString(atrVal, 1) + " pips", xOffset + 12, yOffset + 86, InpTxtColor, 8, false);
   CreateOrUpdateLabel("T6", "Bar Close Timer: " + timerStr, xOffset + 12, yOffset + 104, InpAccentColor, 8, true);
   CreateOrUpdateLabel("T7", "Smart Session Breakout v1 by palaki06", xOffset + 12, yOffset + 130, clrGray, 7, false);
}

//+------------------------------------------------------------------+
//| Create or update label text object                               |
//+------------------------------------------------------------------+
void CreateOrUpdateLabel(string id, string text, int x, int y, color col, int fontSize=8, bool isBold=false)
{
   string name = g_prefix + "Lbl_" + id;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, InpCorner);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, name, OBJPROP_FONT, isBold ? "Segoe UI Bold" : "Segoe UI");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
}

//+------------------------------------------------------------------+
//| Multi-Channel Alert Handler                                      |
//+------------------------------------------------------------------+
void TriggerAlert(string msg)
{
   if(TimeCurrent() - g_lastAlertTime < 60) return; // Prevent alert spam
   g_lastAlertTime = TimeCurrent();

   if(InpPopupAlert) Alert(msg);
   if(InpSoundAlert) PlaySound("alert.wav");
   if(InpSendEmail)  SendMail("Smart Session Breakout Alert", msg);
   if(InpSendPush)   SendNotification(msg);
}

//+------------------------------------------------------------------+
//| Remove all created graphic objects                               |
//+------------------------------------------------------------------+
void CleanUpObjects()
{
   int totalObjs = ObjectsTotal(0, -1, -1);
   for(int i = totalObjs - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, g_prefix) == 0)
      {
         ObjectDelete(0, name);
      }
   }
}
//+------------------------------------------------------------------+
