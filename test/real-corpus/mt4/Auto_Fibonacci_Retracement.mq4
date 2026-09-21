//+------------------------------------------------------------------+
//|                                   Auto_Fibonacci_Retracement.mq4 |
//|                                     Forexobroker - Dominic Walsh |
//|                                     https://www.forexobroker.com |
//+------------------------------------------------------------------+
#property copyright "Forexobroker - Dominic Walsh"
#property link      "https://www.forexobroker.com"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property description "Auto-draws Fibonacci retracement levels based on ZigZag swings."
#property description "Levels update dynamically as new swing points form."
#property description ""
#property description "Fibonacci ratios are the foundation of harmonic pattern trading."
#property description "For multi-symbol harmonic scanning, search MQL5 Market for"
#property description "Harmonic Dashboard indicators by Dominic Walsh."

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+

//--- ZigZag Settings
input int      InpZigZagDepth     = 12;          // ZigZag Depth
input int      InpZigZagDeviation = 5;           // ZigZag Deviation
input int      InpZigZagBackstep  = 3;           // ZigZag Backstep

//--- Fibonacci Level Visibility
input bool     InpShowLevel_0     = true;         // Show 0% Level
input bool     InpShowLevel_236   = true;         // Show 23.6% Level
input bool     InpShowLevel_382   = true;         // Show 38.2% Level
input bool     InpShowLevel_500   = true;         // Show 50% Level
input bool     InpShowLevel_618   = true;         // Show 61.8% Level
input bool     InpShowLevel_786   = true;         // Show 78.6% Level
input bool     InpShowLevel_100   = true;         // Show 100% Level
input bool     InpShowLevel_1272  = true;         // Show 127.2% Extension
input bool     InpShowLevel_1618  = true;         // Show 161.8% Extension

//--- Level Line Appearance
input color    InpLevelColor      = clrGold;      // Level Line Color
input int      InpLevelStyle      = STYLE_DOT;    // Level Line Style (0=Solid,1=Dash,2=Dot)
input int      InpLevelWidth      = 1;            // Level Line Width

//--- Label Settings
input bool     InpShowPriceLabels = true;         // Show Price Labels
input int      InpLabelFontSize   = 8;            // Label Font Size

//--- ZigZag Display
input bool     InpShowZigZag      = true;         // Show ZigZag Line
input color    InpZigZagColor     = clrDodgerBlue; // ZigZag Line Color

//+------------------------------------------------------------------+
//| Constants                                                         |
//+------------------------------------------------------------------+
#define PREFIX           "AutoFibRet_"    // Unique object name prefix
#define MAX_BARS_SEARCH  500              // Max bars to scan for ZigZag pivots

//+------------------------------------------------------------------+
//| Fibonacci level definitions                                       |
//+------------------------------------------------------------------+
struct FibLevel
{
   double   ratio;        // Fibonacci ratio (0.0 to 1.618)
   string   label;        // Display label text
   bool     enabled;      // Whether this level is shown
};

//+------------------------------------------------------------------+
//| Global Variables                                                   |
//+------------------------------------------------------------------+
FibLevel    g_levels[9];           // Array of all Fibonacci levels
datetime    g_lastBarTime = 0;     // Track last bar for new-bar detection
double      g_lastSwingHigh = 0;   // Cache last swing high price
double      g_lastSwingLow = 0;    // Cache last swing low price
datetime    g_lastSwingHighTime = 0;
datetime    g_lastSwingLowTime = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Validate inputs
   if(InpZigZagDepth < 2)
   {
      Print("AutoFibRet: ZigZag Depth must be >= 2. Using default 12.");
   }

   //--- Initialize Fibonacci level definitions
   InitFibLevels();

   //--- Force initial draw
   g_lastBarTime = 0;

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Remove all objects created by this indicator
   DeleteAllObjects();
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                               |
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
   //--- Minimum bars required
   if(rates_total < InpZigZagDepth + InpZigZagBackstep + 2)
      return(rates_total);

   //--- Only update on new bar for performance
   if(Time[0] == g_lastBarTime && prev_calculated > 0)
      return(rates_total);

   g_lastBarTime = Time[0];

   //--- Find the two most recent ZigZag swing points
   double swingHighPrice = 0, swingLowPrice = 0;
   datetime swingHighTime = 0, swingLowTime = 0;

   if(!FindZigZagSwings(swingHighPrice, swingHighTime, swingLowPrice, swingLowTime))
   {
      //--- Could not find two swing points; clean up and exit
      DeleteAllObjects();
      return(rates_total);
   }

   //--- Check if swings have changed to avoid unnecessary redraws
   if(swingHighPrice == g_lastSwingHigh && swingLowPrice == g_lastSwingLow &&
      swingHighTime == g_lastSwingHighTime && swingLowTime == g_lastSwingLowTime)
   {
      //--- Only extend lines to current bar time (right edge update)
      ExtendLinesToRightEdge();
      return(rates_total);
   }

   //--- Cache new swing values
   g_lastSwingHigh     = swingHighPrice;
   g_lastSwingLow      = swingLowPrice;
   g_lastSwingHighTime = swingHighTime;
   g_lastSwingLowTime  = swingLowTime;

   //--- Clear previous drawings
   DeleteAllObjects();

   //--- Draw the ZigZag connector line between swing points
   if(InpShowZigZag)
   {
      DrawZigZagLine(swingHighPrice, swingHighTime, swingLowPrice, swingLowTime);
   }

   //--- Determine the swing range
   double range = swingHighPrice - swingLowPrice;
   if(range <= 0)
      return(rates_total);

   //--- Determine swing direction (which came first)
   //    If swing low is older, price moved up: 0% = low, 100% = high
   //    If swing high is older, price moved down: 0% = high, 100% = low
   bool isUpswing = (swingLowTime < swingHighTime);

   //--- The origin point (0% level) and end point (100% level)
   double originPrice, endPrice;
   datetime originTime;

   if(isUpswing)
   {
      //--- Upswing: 0% at high (most recent), 100% at low (retracement target)
      originPrice = swingHighPrice;
      endPrice    = swingLowPrice;
      originTime  = swingHighTime;
   }
   else
   {
      //--- Downswing: 0% at low (most recent), 100% at high (retracement target)
      originPrice = swingLowPrice;
      endPrice    = swingHighPrice;
      originTime  = swingLowTime;
   }

   //--- Calculate the start time for lines (earlier of the two swings)
   datetime lineStartTime = MathMin(swingHighTime, swingLowTime);

   //--- Draw each enabled Fibonacci level
   for(int i = 0; i < 9; i++)
   {
      if(!g_levels[i].enabled)
         continue;

      //--- Calculate price at this Fibonacci level
      //    Price = Origin + (End - Origin) * ratio
      //    For 0%: price = originPrice
      //    For 100%: price = endPrice
      //    For extensions (>100%): price extends beyond endPrice
      double levelPrice = originPrice + (endPrice - originPrice) * g_levels[i].ratio;
      levelPrice = NormalizeDouble(levelPrice, Digits);

      //--- Draw the level line
      DrawFibLevel(i, levelPrice, lineStartTime, g_levels[i].label);
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Initialize Fibonacci level data                                   |
//+------------------------------------------------------------------+
void InitFibLevels()
{
   //--- Level 0: 0%
   g_levels[0].ratio   = 0.0;
   g_levels[0].label   = "0%";
   g_levels[0].enabled = InpShowLevel_0;

   //--- Level 1: 23.6%
   g_levels[1].ratio   = 0.236;
   g_levels[1].label   = "23.6%";
   g_levels[1].enabled = InpShowLevel_236;

   //--- Level 2: 38.2%
   g_levels[2].ratio   = 0.382;
   g_levels[2].label   = "38.2%";
   g_levels[2].enabled = InpShowLevel_382;

   //--- Level 3: 50%
   g_levels[3].ratio   = 0.5;
   g_levels[3].label   = "50%";
   g_levels[3].enabled = InpShowLevel_500;

   //--- Level 4: 61.8%
   g_levels[4].ratio   = 0.618;
   g_levels[4].label   = "61.8%";
   g_levels[4].enabled = InpShowLevel_618;

   //--- Level 5: 78.6%
   g_levels[5].ratio   = 0.786;
   g_levels[5].label   = "78.6%";
   g_levels[5].enabled = InpShowLevel_786;

   //--- Level 6: 100%
   g_levels[6].ratio   = 1.0;
   g_levels[6].label   = "100%";
   g_levels[6].enabled = InpShowLevel_100;

   //--- Level 7: 127.2% Extension
   g_levels[7].ratio   = 1.272;
   g_levels[7].label   = "127.2%";
   g_levels[7].enabled = InpShowLevel_1272;

   //--- Level 8: 161.8% Extension
   g_levels[8].ratio   = 1.618;
   g_levels[8].label   = "161.8%";
   g_levels[8].enabled = InpShowLevel_1618;
}

//+------------------------------------------------------------------+
//| Find the two most recent ZigZag swing high and swing low          |
//| Returns false if two valid swing points cannot be found           |
//+------------------------------------------------------------------+
bool FindZigZagSwings(double &swingHighPrice, datetime &swingHighTime,
                      double &swingLowPrice,  datetime &swingLowTime)
{
   //--- Direct swing detection without iCustom dependency
   //    Finds swing highs/lows using the lookback method:
   //    A swing high at bar i if High[i] >= High[i-N..i+N]
   //    A swing low  at bar i if Low[i]  <= Low[i-N..i+N]
   int depth = MathMax(2, InpZigZagDepth);
   int limit = MathMin(MAX_BARS_SEARCH, Bars - depth - 1);

   int pivotCount = 0;
   double pivot1Price = 0, pivot2Price = 0;
   datetime pivot1Time = 0, pivot2Time = 0;
   bool pivot1IsHigh = false, pivot2IsHigh = false;

   //--- Scan from most recent confirmed bar outward
   for(int i = depth; i < limit; i++)
   {
      bool isSwingHigh = true;
      bool isSwingLow  = true;

      //--- Check if bar i is a swing high or swing low
      for(int j = 1; j <= depth; j++)
      {
         if(High[i] < High[i - j] || High[i] < High[i + j])
            isSwingHigh = false;
         if(Low[i] > Low[i - j] || Low[i] > Low[i + j])
            isSwingLow = false;
         if(!isSwingHigh && !isSwingLow)
            break;
      }

      //--- If both qualify, pick the dominant one (larger range from open/close midpoint)
      if(isSwingHigh && isSwingLow)
      {
         double mid = (Open[i] + Close[i]) / 2.0;
         if(High[i] - mid >= mid - Low[i])
            isSwingLow = false;
         else
            isSwingHigh = false;
      }

      if(!isSwingHigh && !isSwingLow)
         continue;

      //--- Found a pivot — ensure alternation (high-low-high or low-high-low)
      if(pivotCount == 0)
      {
         pivot1Price  = isSwingHigh ? High[i] : Low[i];
         pivot1Time   = Time[i];
         pivot1IsHigh = isSwingHigh;
         pivotCount   = 1;
      }
      else if(pivotCount == 1)
      {
         //--- Must be opposite type from pivot1 for valid zigzag
         if(isSwingHigh == pivot1IsHigh)
         {
            //--- Same type: replace pivot1 if this one is more extreme
            if(isSwingHigh && High[i] > pivot1Price)
            {
               pivot1Price = High[i];
               pivot1Time  = Time[i];
            }
            else if(!isSwingHigh && Low[i] < pivot1Price)
            {
               pivot1Price = Low[i];
               pivot1Time  = Time[i];
            }
            continue;
         }

         pivot2Price  = isSwingHigh ? High[i] : Low[i];
         pivot2Time   = Time[i];
         pivot2IsHigh = isSwingHigh;
         pivotCount   = 2;
         break;  // Found both pivots
      }
   }

   //--- Need exactly two pivots of opposite type
   if(pivotCount < 2)
      return(false);

   //--- Assign swing high and swing low
   if(pivot1IsHigh)
   {
      swingHighPrice = pivot1Price;
      swingHighTime  = pivot1Time;
      swingLowPrice  = pivot2Price;
      swingLowTime   = pivot2Time;
   }
   else
   {
      swingHighPrice = pivot2Price;
      swingHighTime  = pivot2Time;
      swingLowPrice  = pivot1Price;
      swingLowTime   = pivot1Time;
   }

   return(true);
}

//+------------------------------------------------------------------+
//| Draw a single Fibonacci level line with optional price label      |
//+------------------------------------------------------------------+
void DrawFibLevel(int index, double price, datetime startTime, string levelText)
{
   //--- Build unique object names
   string lineName  = PREFIX + "Line_" + IntegerToString(index);
   string labelName = PREFIX + "Label_" + IntegerToString(index);

   //--- Calculate right edge time: project forward from current bar
   datetime rightEdgeTime = Time[0] + Period() * 60 * 20; // 20 bars into the future

   //--- Create trend line from start to right edge at fixed price (horizontal)
   if(ObjectCreate(0, lineName, OBJ_TREND, 0, startTime, price, rightEdgeTime, price))
   {
      ObjectSetInteger(0, lineName, OBJPROP_COLOR, InpLevelColor);
      ObjectSetInteger(0, lineName, OBJPROP_STYLE, InpLevelStyle);
      ObjectSetInteger(0, lineName, OBJPROP_WIDTH, InpLevelWidth);
      ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, lineName, OBJPROP_BACK, true);
      ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, lineName, OBJPROP_HIDDEN, true);
   }

   //--- Create price label at the right side of the visible chart
   if(InpShowPriceLabels)
   {
      //--- Position label a few bars ahead of the current bar
      datetime labelTime = Time[0] + Period() * 60 * 3;

      if(ObjectCreate(0, labelName, OBJ_TEXT, 0, labelTime, price))
      {
         string displayText = levelText + "  " + DoubleToString(price, Digits);
         ObjectSetString(0, labelName, OBJPROP_TEXT, displayText);
         ObjectSetString(0, labelName, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, InpLabelFontSize);
         ObjectSetInteger(0, labelName, OBJPROP_COLOR, InpLevelColor);
         ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
         ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, labelName, OBJPROP_HIDDEN, true);
      }
   }
}

//+------------------------------------------------------------------+
//| Draw ZigZag connector line between the two swing points           |
//+------------------------------------------------------------------+
void DrawZigZagLine(double highPrice, datetime highTime,
                    double lowPrice,  datetime lowTime)
{
   string name = PREFIX + "ZigZag";

   if(ObjectCreate(0, name, OBJ_TREND, 0, lowTime, lowPrice, highTime, highPrice))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, InpZigZagColor);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
//| Extend existing lines to updated right edge (time update only)    |
//+------------------------------------------------------------------+
void ExtendLinesToRightEdge()
{
   datetime rightEdgeTime = Time[0] + Period() * 60 * 20;
   datetime labelTime     = Time[0] + Period() * 60 * 3;

   for(int i = 0; i < 9; i++)
   {
      if(!g_levels[i].enabled)
         continue;

      string lineName  = PREFIX + "Line_" + IntegerToString(i);
      string labelName = PREFIX + "Label_" + IntegerToString(i);

      //--- Update the second time anchor of the trend line
      if(ObjectFind(0, lineName) >= 0)
      {
         ObjectSetInteger(0, lineName, OBJPROP_TIME, 1, rightEdgeTime);
      }

      //--- Update the label time position
      if(ObjectFind(0, labelName) >= 0)
      {
         ObjectSetInteger(0, labelName, OBJPROP_TIME, 0, labelTime);
      }
   }
}

//+------------------------------------------------------------------+
//| Delete all objects created by this indicator                      |
//+------------------------------------------------------------------+
void DeleteAllObjects()
{
   int totalObjects = ObjectsTotal(0, 0, -1);

   //--- Iterate backwards to safely delete
   for(int i = totalObjects - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);

      if(StringFind(name, PREFIX) == 0)
      {
         ObjectDelete(0, name);
      }
   }
}
//+------------------------------------------------------------------+
