//+------------------------------------------------------------------+
//|                                     Draw_On_Liquidity_Mapper.mq4 |
//|                                     Forexobroker - Dominic Walsh |
//|                                     https://www.forexobroker.com |
//+------------------------------------------------------------------+
#property copyright "Forexobroker - Dominic Walsh"
#property link      "https://www.forexobroker.com"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property description "Draw on Liquidity (DOL) Mapper - maps all liquidity targets:"
#property description "previous day/week highs-lows, equal levels, untested FVGs."
#property description "Shows WHERE price is heading next. Core ICT planning concept."
#property description ""
#property description "For professional ICT tools, visit MQL5 Market - Dominic Walsh."

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input string   Sep1              = "=== Period High/Low Settings ===";  // ---
input bool     ShowPDHL          = true;       // Show Previous Day High/Low
input bool     ShowPWHL          = true;       // Show Previous Week High/Low
input bool     ShowPMHL          = true;       // Show Previous Month High/Low

input string   Sep2              = "=== Equal Levels Settings ===";     // ---
input bool     ShowEqualLevels   = true;       // Show Equal Highs/Lows
input int      EqualTolerancePts = 15;         // Equal Level Tolerance (points)
input int      SwingLookback     = 10;         // Swing Lookback Bars for Equals

input string   Sep3              = "=== FVG Settings ===";              // ---
input bool     ShowUntestedFVGs  = true;       // Show Untested FVGs
input int      MinFVGSizePts     = 5;          // Minimum FVG Size (points)
input int      MaxFVGBarsBack    = 500;        // Max Bars Back for FVG Scan

input string   Sep4              = "=== Colors ===";                    // ---
input color    ColorPDH          = clrRed;           // Previous Day High Color
input color    ColorPDL          = clrRed;           // Previous Day Low Color
input color    ColorPWH          = clrOrange;        // Previous Week High Color
input color    ColorPWL          = clrOrange;        // Previous Week Low Color
input color    ColorPMH          = clrPurple;        // Previous Month High Color
input color    ColorPML          = clrPurple;        // Previous Month Low Color
input color    ColorEQH          = clrMagenta;       // Equal Highs Color
input color    ColorEQL          = clrMagenta;       // Equal Lows Color
input color    ColorFVGBull      = clrDodgerBlue;    // Bullish FVG Color (below price)
input color    ColorFVGBear      = clrDodgerBlue;    // Bearish FVG Color (above price)

input string   Sep5              = "=== Panel & Display ===";           // ---
input bool     ShowInfoPanel     = true;       // Show Info Panel
input int      PanelX            = 20;         // Panel X Position
input int      PanelY            = 50;         // Panel Y Position
input int      MaxTargets        = 30;         // Maximum DOL Targets to Display
input ENUM_LINE_STYLE LineStyle  = STYLE_DOT;  // Line Style

input string   Sep6              = "=== Alerts ===";                    // ---
input bool     AlertApproaching  = true;       // Alert When Approaching DOL
input int      ApproachDistPips  = 20;         // Approach Distance (pips)
input bool     PushNotification  = false;      // Send Push Notifications

//+------------------------------------------------------------------+
//| Constants and Globals                                             |
//+------------------------------------------------------------------+
#define PREFIX "DOL_"

//--- DOL target structure
struct DOLTarget
{
   string   name;        // Display name (e.g. "PDH", "EQL")
   double   price;       // Price level
   color    clr;         // Color
   int      strength;    // Strength rating 1-5
   bool     isAbove;     // Above current price
   string   type;        // Category: "period","equal","fvg"
   datetime created;     // When identified
};

DOLTarget g_targets[];
int        g_targetCount   = 0;
datetime   g_lastBarTime   = 0;
bool       g_alertedAbove  = false;
bool       g_alertedBelow  = false;
double     g_lastAlertAbove = 0;
double     g_lastAlertBelow = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorShortName("DOL Mapper");

   //--- Initial calculation
   CalculateAllTargets();
   DrawAllTargets();
   if(ShowInfoPanel) DrawPanel();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
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
   if(rates_total < 2) return(0);

   datetime currentBarTime = Time[0];

   //--- Recalculate on new bar
   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;

      CalculateAllTargets();
      DrawAllTargets();
   }

   //--- Update panel every tick for live distance
   if(ShowInfoPanel) DrawPanel();

   //--- Check approach alerts
   if(AlertApproaching) CheckApproachAlerts();

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Master calculation: find all DOL targets                          |
//+------------------------------------------------------------------+
void CalculateAllTargets()
{
   g_targetCount = 0;
   ArrayResize(g_targets, 0);

   double currentPrice = (Bid + Ask) / 2.0;
   if(currentPrice == 0) currentPrice = Close[0];

   //--- Period highs/lows
   if(ShowPDHL) FindPeriodLevels(PERIOD_D1, "PD", ColorPDH, ColorPDL);
   if(ShowPWHL) FindPeriodLevels(PERIOD_W1, "PW", ColorPWH, ColorPWL);
   if(ShowPMHL) FindPeriodLevels(PERIOD_MN1, "PM", ColorPMH, ColorPML);

   //--- Equal highs/lows
   if(ShowEqualLevels) FindEqualLevels();

   //--- Untested FVGs
   if(ShowUntestedFVGs) FindUntestedFVGs();

   //--- Remove targets already reached by price
   RemoveReachedTargets(currentPrice);

   //--- Sort by distance from current price
   SortTargetsByDistance(currentPrice);

   //--- Cap at MaxTargets
   if(g_targetCount > MaxTargets)
   {
      g_targetCount = MaxTargets;
      ArrayResize(g_targets, MaxTargets);
   }
}

//+------------------------------------------------------------------+
//| Find previous period high/low                                     |
//+------------------------------------------------------------------+
void FindPeriodLevels(int timeframe, string prefix, color highColor, color lowColor)
{
   //--- We need at least 2 bars on the higher timeframe
   if(iBars(Symbol(), timeframe) < 2) return;

   //--- Bar index 1 = previous completed period
   double prevHigh = iHigh(Symbol(), timeframe, 1);
   double prevLow  = iLow(Symbol(), timeframe, 1);

   if(prevHigh == 0 || prevLow == 0) return;

   prevHigh = NormalizeDouble(prevHigh, Digits);
   prevLow  = NormalizeDouble(prevLow, Digits);

   //--- Determine strength: more recent = higher strength
   int strength = 3;
   if(timeframe == PERIOD_D1)  strength = 3;
   if(timeframe == PERIOD_W1)  strength = 4;
   if(timeframe == PERIOD_MN1) strength = 5;

   string highName = prefix + "H";
   string lowName  = prefix + "L";

   AddTarget(highName, prevHigh, highColor, strength, "period");
   AddTarget(lowName, prevLow, lowColor, strength, "period");
}

//+------------------------------------------------------------------+
//| Find Equal Highs and Equal Lows                                   |
//+------------------------------------------------------------------+
void FindEqualLevels()
{
   int barsAvailable = MathMin(Bars - 1, MaxFVGBarsBack);
   if(barsAvailable < SwingLookback * 2 + 1) return;

   double tolerance = EqualTolerancePts * Point;

   //--- Collect swing highs
   double swingHighs[];
   int    swingHighBars[];
   int    shCount = 0;

   //--- Collect swing lows
   double swingLows[];
   int    swingLowBars[];
   int    slCount = 0;

   //--- Find swing points
   for(int i = SwingLookback; i < barsAvailable - SwingLookback; i++)
   {
      //--- Check swing high
      if(IsSwingHigh(i, SwingLookback))
      {
         ArrayResize(swingHighs, shCount + 1);
         ArrayResize(swingHighBars, shCount + 1);
         swingHighs[shCount]    = High[i];
         swingHighBars[shCount] = i;
         shCount++;
      }

      //--- Check swing low
      if(IsSwingLow(i, SwingLookback))
      {
         ArrayResize(swingLows, slCount + 1);
         ArrayResize(swingLowBars, slCount + 1);
         swingLows[slCount]    = Low[i];
         swingLowBars[slCount] = i;
         slCount++;
      }
   }

   //--- Find equal highs (2+ swing highs within tolerance)
   bool usedHigh[];
   ArrayResize(usedHigh, shCount);
   ArrayInitialize(usedHigh, false);

   for(int i = 0; i < shCount; i++)
   {
      if(usedHigh[i]) continue;

      int matchCount = 1;
      double sumPrice = swingHighs[i];

      for(int j = i + 1; j < shCount; j++)
      {
         if(usedHigh[j]) continue;
         if(MathAbs(swingHighs[i] - swingHighs[j]) <= tolerance)
         {
            matchCount++;
            sumPrice += swingHighs[j];
            usedHigh[j] = true;
         }
      }

      if(matchCount >= 2)
      {
         double avgPrice = NormalizeDouble(sumPrice / matchCount, Digits);
         int strength = MathMin(5, matchCount + 1); // More touches = stronger
         string name = "EQH_" + IntegerToString(i);
         AddTarget(name, avgPrice, ColorEQH, strength, "equal");
         usedHigh[i] = true;
      }
   }

   //--- Find equal lows (2+ swing lows within tolerance)
   bool usedLow[];
   ArrayResize(usedLow, slCount);
   ArrayInitialize(usedLow, false);

   for(int i = 0; i < slCount; i++)
   {
      if(usedLow[i]) continue;

      int matchCount = 1;
      double sumPrice = swingLows[i];

      for(int j = i + 1; j < slCount; j++)
      {
         if(usedLow[j]) continue;
         if(MathAbs(swingLows[i] - swingLows[j]) <= tolerance)
         {
            matchCount++;
            sumPrice += swingLows[j];
            usedLow[j] = true;
         }
      }

      if(matchCount >= 2)
      {
         double avgPrice = NormalizeDouble(sumPrice / matchCount, Digits);
         int strength = MathMin(5, matchCount + 1);
         string name = "EQL_" + IntegerToString(i);
         AddTarget(name, avgPrice, ColorEQL, strength, "equal");
         usedLow[i] = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Check if bar is a swing high                                      |
//+------------------------------------------------------------------+
bool IsSwingHigh(int bar, int lookback)
{
   double testHigh = High[bar];

   for(int i = 1; i <= lookback; i++)
   {
      if(High[bar - i] >= testHigh) return false;
      if(High[bar + i] >= testHigh) return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check if bar is a swing low                                       |
//+------------------------------------------------------------------+
bool IsSwingLow(int bar, int lookback)
{
   double testLow = Low[bar];

   for(int i = 1; i <= lookback; i++)
   {
      if(Low[bar - i] <= testLow) return false;
      if(Low[bar + i] <= testLow) return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Find untested Fair Value Gaps                                     |
//+------------------------------------------------------------------+
void FindUntestedFVGs()
{
   int barsAvailable = MathMin(Bars - 1, MaxFVGBarsBack);
   if(barsAvailable < 3) return;

   double minSize = MinFVGSizePts * Point;
   double currentPrice = Close[0];
   int fvgCount = 0;

   for(int i = 2; i < barsAvailable && fvgCount < MaxTargets; i++)
   {
      //--- Bullish FVG: bar[i] high < bar[i-2] low (gap up)
      //--- Three-candle pattern: candle i+0 = oldest, gap between bar i high and bar i-2 low
      double bullGapTop    = Low[i - 2];   // Low of the candle after the gap
      double bullGapBottom = High[i];      // High of the candle before the gap

      if(bullGapBottom < bullGapTop)
      {
         double gapSize = bullGapTop - bullGapBottom;
         if(gapSize >= minSize)
         {
            //--- Check if FVG has been tested (price traded into it)
            double fvgMid = NormalizeDouble((bullGapTop + bullGapBottom) / 2.0, Digits);
            if(!IsFVGTested(i, bullGapBottom, bullGapTop))
            {
               //--- Bullish FVG is below price = draw on liquidity target below
               int strength = CalculateFVGStrength(gapSize, i);
               string name = "BFVG_" + IntegerToString(i);
               AddTarget(name, fvgMid, ColorFVGBull, strength, "fvg");
               fvgCount++;
            }
         }
      }

      //--- Bearish FVG: bar[i] low > bar[i-2] high (gap down)
      double bearGapTop    = Low[i];       // Low of the candle before the gap
      double bearGapBottom = High[i - 2];  // High of the candle after the gap

      if(bearGapTop > bearGapBottom)
      {
         double gapSize = bearGapTop - bearGapBottom;
         if(gapSize >= minSize)
         {
            double fvgMid = NormalizeDouble((bearGapTop + bearGapBottom) / 2.0, Digits);
            if(!IsFVGTested(i, bearGapBottom, bearGapTop))
            {
               int strength = CalculateFVGStrength(gapSize, i);
               string name = "SFVG_" + IntegerToString(i);
               AddTarget(name, fvgMid, ColorFVGBear, strength, "fvg");
               fvgCount++;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if an FVG has been tested by subsequent price action        |
//+------------------------------------------------------------------+
bool IsFVGTested(int fvgBar, double gapBottom, double gapTop)
{
   //--- Check if price has traded into the FVG zone after it formed
   for(int i = fvgBar - 2; i >= 1; i--)
   {
      //--- If price low penetrated the gap top (for bearish FVG above)
      //--- or price high penetrated the gap bottom (for bullish FVG below)
      if(Low[i] <= gapTop && High[i] >= gapBottom)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculate FVG strength based on size and recency                  |
//+------------------------------------------------------------------+
int CalculateFVGStrength(double gapSize, int barsAgo)
{
   int strength = 2; // Base

   //--- Larger gaps are stronger
   double avgATR = iATR(Symbol(), 0, 14, 0);
   if(avgATR > 0)
   {
      double ratio = gapSize / avgATR;
      if(ratio > 0.5) strength++;
      if(ratio > 1.0) strength++;
   }

   //--- More recent FVGs are stronger
   if(barsAgo < 50)  strength++;
   if(barsAgo < 20)  strength++;

   return MathMin(5, strength);
}

//+------------------------------------------------------------------+
//| Add a target to the array                                         |
//+------------------------------------------------------------------+
void AddTarget(string name, double price, color clr, int strength, string type)
{
   int idx = g_targetCount;
   ArrayResize(g_targets, idx + 1);

   double currentPrice = Close[0];

   g_targets[idx].name     = name;
   g_targets[idx].price    = price;
   g_targets[idx].clr      = clr;
   g_targets[idx].strength = MathMax(1, MathMin(5, strength));
   g_targets[idx].isAbove  = (price > currentPrice);
   g_targets[idx].type     = type;
   g_targets[idx].created  = TimeCurrent();

   g_targetCount++;
}

//+------------------------------------------------------------------+
//| Remove targets that have been reached by price                    |
//+------------------------------------------------------------------+
void RemoveReachedTargets(double currentPrice)
{
   double tolerance = 2 * Point; // Small buffer

   int newCount = 0;
   DOLTarget tempTargets[];
   ArrayResize(tempTargets, g_targetCount);

   for(int i = 0; i < g_targetCount; i++)
   {
      double dist = MathAbs(currentPrice - g_targets[i].price);

      //--- Keep target only if price hasn't reached it
      if(dist > tolerance)
      {
         tempTargets[newCount] = g_targets[i];
         newCount++;
      }
   }

   ArrayResize(g_targets, newCount);
   for(int i = 0; i < newCount; i++)
      g_targets[i] = tempTargets[i];

   g_targetCount = newCount;
}

//+------------------------------------------------------------------+
//| Sort targets by distance from current price (nearest first)       |
//+------------------------------------------------------------------+
void SortTargetsByDistance(double currentPrice)
{
   //--- Simple bubble sort (small array)
   for(int i = 0; i < g_targetCount - 1; i++)
   {
      for(int j = i + 1; j < g_targetCount; j++)
      {
         double distI = MathAbs(currentPrice - g_targets[i].price);
         double distJ = MathAbs(currentPrice - g_targets[j].price);

         if(distJ < distI)
         {
            DOLTarget temp = g_targets[i];
            g_targets[i] = g_targets[j];
            g_targets[j] = temp;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Draw all target lines on chart                                    |
//+------------------------------------------------------------------+
void DrawAllTargets()
{
   //--- Remove old DOL lines first
   DeleteTargetLines();

   for(int i = 0; i < g_targetCount; i++)
   {
      string lineName  = PREFIX + "LINE_" + IntegerToString(i);
      string labelName = PREFIX + "LABEL_" + IntegerToString(i);

      //--- Build display label
      string stars = "";
      for(int s = 0; s < g_targets[i].strength; s++) stars += "*";

      string displayText = g_targets[i].name + " [" + stars + "] " +
                           DoubleToString(g_targets[i].price, Digits);

      //--- Draw horizontal line
      if(ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, g_targets[i].price))
      {
         ObjectSetInteger(0, lineName, OBJPROP_COLOR, g_targets[i].clr);
         ObjectSetInteger(0, lineName, OBJPROP_STYLE, LineStyle);
         ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, lineName, OBJPROP_BACK, true);
         ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
         ObjectSetString(0, lineName, OBJPROP_TOOLTIP, displayText);
      }

      //--- Draw text label near the right edge
      datetime labelTime = Time[0] + PeriodSeconds() * 3;
      if(ObjectCreate(0, labelName, OBJ_TEXT, 0, labelTime, g_targets[i].price))
      {
         ObjectSetString(0, labelName, OBJPROP_TEXT, displayText);
         ObjectSetInteger(0, labelName, OBJPROP_COLOR, g_targets[i].clr);
         ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
         ObjectSetString(0, labelName, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
      }
   }
}

//+------------------------------------------------------------------+
//| Delete all target lines and labels                                |
//+------------------------------------------------------------------+
void DeleteTargetLines()
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string objName = ObjectName(0, i, 0, -1);
      if(StringFind(objName, PREFIX + "LINE_") == 0 ||
         StringFind(objName, PREFIX + "LABEL_") == 0)
      {
         ObjectDelete(0, objName);
      }
   }
}

//+------------------------------------------------------------------+
//| Delete all DOL objects                                            |
//+------------------------------------------------------------------+
void DeleteAllObjects()
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string objName = ObjectName(0, i, 0, -1);
      if(StringFind(objName, PREFIX) == 0)
      {
         ObjectDelete(0, objName);
      }
   }
}

//+------------------------------------------------------------------+
//| Draw information panel                                            |
//+------------------------------------------------------------------+
void DrawPanel()
{
   double currentPrice = (Bid + Ask) / 2.0;
   if(currentPrice == 0) currentPrice = Close[0];

   //--- Find nearest above and below
   double nearestAbove      = 0;
   string nearestAboveName  = "None";
   int    nearestAboveStr   = 0;
   double nearestBelow      = 0;
   string nearestBelowName  = "None";
   int    nearestBelowStr   = 0;
   double minDistAbove      = DBL_MAX;
   double minDistBelow      = DBL_MAX;

   int countAbove = 0;
   int countBelow = 0;

   for(int i = 0; i < g_targetCount; i++)
   {
      double dist = g_targets[i].price - currentPrice;

      if(dist > 0) // Above
      {
         countAbove++;
         if(dist < minDistAbove)
         {
            minDistAbove     = dist;
            nearestAbove     = g_targets[i].price;
            nearestAboveName = g_targets[i].name;
            nearestAboveStr  = g_targets[i].strength;
         }
      }
      else if(dist < 0) // Below
      {
         countBelow++;
         double absDist = MathAbs(dist);
         if(absDist < minDistBelow)
         {
            minDistBelow     = absDist;
            nearestBelow     = g_targets[i].price;
            nearestBelowName = g_targets[i].name;
            nearestBelowStr  = g_targets[i].strength;
         }
      }
   }

   //--- Calculate distances in pips
   double pipSize = Point;
   if(Digits == 3 || Digits == 5) pipSize = Point * 10;

   string aboveDistStr = "---";
   string belowDistStr = "---";

   if(nearestAbove > 0)
      aboveDistStr = DoubleToString(minDistAbove / pipSize, 1) + " pips";
   if(nearestBelow > 0)
      belowDistStr = DoubleToString(minDistBelow / pipSize, 1) + " pips";

   //--- Strength stars
   string aboveStars = "";
   for(int s = 0; s < nearestAboveStr; s++) aboveStars += "*";
   string belowStars = "";
   for(int s = 0; s < nearestBelowStr; s++) belowStars += "*";

   //--- Panel dimensions
   int panelWidth  = 280;
   int panelHeight = 155;
   int textX       = PanelX + 10;
   int lineH       = 18;

   //--- Background rectangle
   string bgName = PREFIX + "PNL_BG";
   if(ObjectFind(0, bgName) < 0)
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);

   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, PanelX);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, PanelY);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, panelWidth);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, panelHeight);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, C'20,20,30');
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_COLOR, C'60,60,80');
   ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
   ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);

   //--- Title
   int row = 0;
   CreatePanelLabel("PNL_TITLE", textX, PanelY + 8 + lineH * row,
                    "DRAW ON LIQUIDITY MAPPER", C'0,200,255', 9, true);

   //--- Separator
   row++;
   CreatePanelLabel("PNL_SEP1", textX, PanelY + 8 + lineH * row,
                    "____________________________", C'60,60,80', 7, false);

   //--- Nearest DOL Above
   row++;
   string aboveText = "Nearest Above: " + nearestAboveName;
   if(nearestAbove > 0)
      aboveText += " [" + aboveStars + "] @ " + DoubleToString(nearestAbove, Digits);
   CreatePanelLabel("PNL_ABOVE", textX, PanelY + 8 + lineH * row,
                    aboveText, C'100,255,100', 8, false);

   row++;
   CreatePanelLabel("PNL_ABOVE_DIST", textX + 15, PanelY + 8 + lineH * row,
                    "Distance: " + aboveDistStr, C'180,180,180', 8, false);

   //--- Nearest DOL Below
   row++;
   string belowText = "Nearest Below: " + nearestBelowName;
   if(nearestBelow > 0)
      belowText += " [" + belowStars + "] @ " + DoubleToString(nearestBelow, Digits);
   CreatePanelLabel("PNL_BELOW", textX, PanelY + 8 + lineH * row,
                    belowText, C'255,100,100', 8, false);

   row++;
   CreatePanelLabel("PNL_BELOW_DIST", textX + 15, PanelY + 8 + lineH * row,
                    "Distance: " + belowDistStr, C'180,180,180', 8, false);

   //--- Summary
   row++;
   string summaryText = "Targets: " + IntegerToString(countAbove) + " above | " +
                        IntegerToString(countBelow) + " below | " +
                        IntegerToString(g_targetCount) + " total";
   CreatePanelLabel("PNL_SUMMARY", textX, PanelY + 8 + lineH * row,
                    summaryText, C'150,150,170', 7, false);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Create or update a panel text label                               |
//+------------------------------------------------------------------+
void CreatePanelLabel(string id, int x, int y, string text, color clr, int fontSize, bool bold)
{
   string name = PREFIX + id;

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Check if price is approaching any DOL target                      |
//+------------------------------------------------------------------+
void CheckApproachAlerts()
{
   double currentPrice = (Bid + Ask) / 2.0;
   if(currentPrice == 0) currentPrice = Close[0];

   double pipSize = Point;
   if(Digits == 3 || Digits == 5) pipSize = Point * 10;
   double alertDist = ApproachDistPips * pipSize;

   //--- Find nearest above
   double nearestAbove = 0;
   string nearestAboveName = "";
   double minDistAbove = DBL_MAX;

   //--- Find nearest below
   double nearestBelow = 0;
   string nearestBelowName = "";
   double minDistBelow = DBL_MAX;

   for(int i = 0; i < g_targetCount; i++)
   {
      double dist = g_targets[i].price - currentPrice;

      if(dist > 0 && dist < minDistAbove)
      {
         minDistAbove     = dist;
         nearestAbove     = g_targets[i].price;
         nearestAboveName = g_targets[i].name;
      }
      else if(dist < 0 && MathAbs(dist) < minDistBelow)
      {
         minDistBelow     = MathAbs(dist);
         nearestBelow     = g_targets[i].price;
         nearestBelowName = g_targets[i].name;
      }
   }

   //--- Alert for approaching above target
   if(nearestAbove > 0 && minDistAbove <= alertDist)
   {
      if(!g_alertedAbove || g_lastAlertAbove != nearestAbove)
      {
         string msg = Symbol() + ": Price approaching DOL target ABOVE - " +
                      nearestAboveName + " @ " + DoubleToString(nearestAbove, Digits) +
                      " (" + DoubleToString(minDistAbove / pipSize, 1) + " pips away)";

         Alert(msg);
         if(PushNotification) SendNotification(msg);

         g_alertedAbove   = true;
         g_lastAlertAbove = nearestAbove;
      }
   }
   else
   {
      g_alertedAbove = false;
   }

   //--- Alert for approaching below target
   if(nearestBelow > 0 && minDistBelow <= alertDist)
   {
      if(!g_alertedBelow || g_lastAlertBelow != nearestBelow)
      {
         string msg = Symbol() + ": Price approaching DOL target BELOW - " +
                      nearestBelowName + " @ " + DoubleToString(nearestBelow, Digits) +
                      " (" + DoubleToString(minDistBelow / pipSize, 1) + " pips away)";

         Alert(msg);
         if(PushNotification) SendNotification(msg);

         g_alertedBelow   = true;
         g_lastAlertBelow = nearestBelow;
      }
   }
   else
   {
      g_alertedBelow = false;
   }
}
//+------------------------------------------------------------------+
