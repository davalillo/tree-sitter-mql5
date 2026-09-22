//+------------------------------------------------------------------+
//|                            H1_Container_MTF_Boxes_v3.mq4         |
//|                            Copyright 2026, Dragan Joksimovic     |
//+------------------------------------------------------------------+
//
//  One H1 container box holds every M30, M15, M5 and M1 box that falls
//  inside it.
//
//  LEVELS
//  ------
//  The container and the boxes inside it are read differently, so they
//  are marked differently:
//
//      H1 container : 25%, 50% and 75% of its range - quarters, so the
//                     hour can be read as four zones.
//      Inner boxes  : the 50% line only. On M30, M15, M5 and M1 the
//                     middle is the level that matters; anything more
//                     turns the chart into noise.
//
//  DRAWING BUDGET
//  --------------
//  With every timeframe on, one container holds
//      1 H1 + 2 M30 + 4 M15 + 12 M5 + 60 M1 = 79 boxes.
//  The container is 4 edges + 3 levels = 7 objects, and every inner box
//  is 4 edges + 1 level = 5, so roughly 400 chart objects.
//
//  Those objects are not rebuilt on every tick:
//    * A closed H1 container never changes, so it is drawn once and then
//      left alone entirely.
//    * For the live container, a full rebuild happens only when a new
//      bar opens on the lowest enabled timeframe.
//    * Between rebuilds only the boxes that can still move are touched -
//      the current bar of each enabled timeframe plus the container.
//      That is about five boxes instead of seventy-nine.
//
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property copyright "Dragan Joksimovic"
#property link      "https://www.mql5.com/en/users/draganjoksimovi"
#property version   "3.00"
#property description "One H1 container box holding its M30, M15, M5 and M1 boxes."
#property description "Container marked at 25/50/75%, inner boxes at the middle."
#property description "Display only - places no orders and modifies no positions."

//==================================================================
// INPUTS
//==================================================================

input string _s1_                = "=== Container ===";
input bool   AutoFollowCurrentH1 = true;   // always follow the forming H1 candle
input int    H1Shift             = 0;      // used only when AutoFollow is off: 0 = current, 1 = previous

input string _s2_                = "=== Timeframes shown ===";
input bool   ShowH1              = true;
input bool   ShowM30             = true;
input bool   ShowM15             = true;
input bool   ShowM5              = true;
input bool   ShowM1              = true;   // heaviest: 60 boxes per container

input string _s3_                = "=== Container levels (25 / 50 / 75%) ===";
input bool   ShowH1Levels        = true;   // master switch for all three
input bool   ShowH1Level25       = true;
input bool   ShowH1Level50       = true;
input bool   ShowH1Level75       = true;

input string _s4_                = "=== Inner box level (50%) ===";
input bool   ShowInnerMiddle     = true;   // middle line on M30 / M15 / M5 / M1 boxes

input string _s5_                = "=== Colours ===";
input color  H1Color             = clrMagenta;
input color  M30Color            = clrDodgerBlue;
input color  M15Color            = clrLime;
input color  M5Color             = clrYellow;
input color  M1Color             = clrWhite;

input string _s6_                = "=== Line widths and styles ===";
input int    H1BoxWidth          = 3;
input int    M30BoxWidth         = 2;
input int    M15BoxWidth         = 1;
input int    M5BoxWidth          = 1;
input int    M1BoxWidth          = 1;
input int    H1LevelWidth        = 2;
input int    H1LevelStyle        = STYLE_DASH;
input int    InnerLevelWidth     = 1;
input int    InnerLevelStyle     = STYLE_DOT;

input string _s7_                = "=== Labels & misc ===";
input bool   DrawInBackground    = false;
input bool   ShowMainLabel       = true;
input bool   ShowTFLabels        = false;
input int    LabelFontSize       = 8;
input string LabelFont           = "Arial";
input string ObjectPrefix        = "H1MTFB_";  // change it to run a second copy on the same chart

//==================================================================
// GLOBALS
//==================================================================

int      g_shift         = 0;      // container shift actually in use
datetime g_h1Start       = 0;      // container start time drawn last
int      g_drawnShift    = -1;
datetime g_lastRebuild   = 0;      // bar time of the lowest enabled TF at the last full rebuild
bool     g_containerLive = true;   // false when a fixed, already closed H1 is shown

//==================================================================
// SMALL HELPERS
//==================================================================

int SafeWidth(int width)
{
   if(width < 1) return 1;
   if(width > 5) return 5;
   return width;
}

//------------------------------------------------------------------
// Lowest enabled timeframe. Its bar opening is what triggers a full
// rebuild, because that is the fastest thing that can add a new box.
//------------------------------------------------------------------
ENUM_TIMEFRAMES LowestEnabledTF()
{
   if(ShowM1)  return PERIOD_M1;
   if(ShowM5)  return PERIOD_M5;
   if(ShowM15) return PERIOD_M15;
   if(ShowM30) return PERIOD_M30;
   return PERIOD_H1;
}

//------------------------------------------------------------------
void DeleteAll()
{
   int total = ObjectsTotal(0, 0, -1);

   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, ObjectPrefix) == 0)
         ObjectDelete(0, name);
   }
}

//------------------------------------------------------------------
void Line(string name,
          datetime t1, double p1,
          datetime t2, double p2,
          color clr, int width, int style)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2))
      {
         Print("ObjectCreate failed: ", name, " error=", GetLastError());
         ResetLastError();
         return;
      }
   }
   else
   {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
   }

   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      SafeWidth(width));
   ObjectSetInteger(0, name, OBJPROP_STYLE,      style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  false);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,   false);
   ObjectSetInteger(0, name, OBJPROP_BACK,       DrawInBackground);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

//------------------------------------------------------------------
// Draws one level line, or removes it when the level is switched off.
// Removing matters: without it, turning a level off would leave the old
// line frozen on the chart until the container changes.
//------------------------------------------------------------------
void LevelLine(string base, string suffix, bool enabled,
               datetime t1, datetime t2, double price,
               color clr, int width, int style)
{
   string name = base + suffix;

   if(enabled) Line(name, t1, price, t2, price, clr, width, style);
   else        ObjectDelete(0, name);
}

//------------------------------------------------------------------
void DrawLabel(string name, datetime t, double price, string text, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
         return;
   }
   else
   {
      ObjectMove(0, name, 0, t, price);
   }

   ObjectSetString (0, name, OBJPROP_TEXT,       text);
   ObjectSetString (0, name, OBJPROP_FONT,       LabelFont);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   LabelFontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

//==================================================================
// ONE BOX
//
// isContainer decides which level set is drawn:
//    true  -> the H1 container: 25 / 50 / 75%
//    false -> an inner box: the 50% middle only
//==================================================================

void DrawBox(string tfName,
             datetime t1, datetime t2,
             double hi, double lo,
             color clr, int boxWidth,
             bool showLabel, bool isContainer)
{
   string b = ObjectPrefix + tfName + "_" + IntegerToString((long)t1);

   Line(b + "_H",  t1, hi, t2, hi, clr, boxWidth, STYLE_SOLID);
   Line(b + "_L",  t1, lo, t2, lo, clr, boxWidth, STYLE_SOLID);
   Line(b + "_VL", t1, hi, t1, lo, clr, boxWidth, STYLE_SOLID);
   Line(b + "_VR", t2, hi, t2, lo, clr, boxWidth, STYLE_SOLID);

   double range = hi - lo;

   if(isContainer)
   {
      LevelLine(b, "_25", ShowH1Levels && ShowH1Level25,
                t1, t2, lo + range * 0.25, clr, H1LevelWidth, H1LevelStyle);
      LevelLine(b, "_50", ShowH1Levels && ShowH1Level50,
                t1, t2, lo + range * 0.50, clr, H1LevelWidth, H1LevelStyle);
      LevelLine(b, "_75", ShowH1Levels && ShowH1Level75,
                t1, t2, lo + range * 0.75, clr, H1LevelWidth, H1LevelStyle);
   }
   else
   {
      LevelLine(b, "_50", ShowInnerMiddle,
                t1, t2, lo + range * 0.50, clr, InnerLevelWidth, InnerLevelStyle);
   }

   if(showLabel) DrawLabel(b + "_TXT", t1, hi, tfName, clr);
   else          ObjectDelete(0, b + "_TXT");
}

//------------------------------------------------------------------
// One bar of one timeframe, drawn only if it really starts inside the
// container.
//------------------------------------------------------------------
bool DrawBarBox(string tfName, ENUM_TIMEFRAMES tf, int shift,
                datetime h1Start, datetime h1End,
                double h1High, double h1Low,
                color clr, int width)
{
   if(shift < 0)
      return false;

   datetime t1 = iTime(Symbol(), tf, shift);
   if(t1 < h1Start || t1 >= h1End)
      return false;

   double hi = iHigh(Symbol(), tf, shift);
   double lo = iLow (Symbol(), tf, shift);
   if(hi <= 0.0 || lo <= 0.0 || hi < lo)
      return false;

   hi = MathMin(hi, h1High);
   lo = MathMax(lo, h1Low);

   int sec = PeriodSeconds(tf);
   if(sec <= 0)
      return false;

   datetime t2 = t1 + sec;
   if(t2 > h1End)
      t2 = h1End;

   DrawBox(tfName, t1, t2, hi, lo, clr, width, ShowTFLabels, false);
   return true;
}

//------------------------------------------------------------------
void DrawTF(string tfName, ENUM_TIMEFRAMES tf,
            datetime h1Start, datetime h1End,
            double h1High, double h1Low,
            color clr, int width)
{
   int sec = PeriodSeconds(tf);
   if(sec <= 0)
      return;

   for(datetime slot = h1Start; slot < h1End; slot += sec)
   {
      int shift = iBarShift(Symbol(), tf, slot, true);
      if(shift < 0)
         continue;

      DrawBarBox(tfName, tf, shift, h1Start, h1End, h1High, h1Low, clr, width);
   }
}

//==================================================================
// FULL REBUILD
//==================================================================

void RebuildAll(datetime h1Start, datetime h1End, double h1High, double h1Low)
{
   if(ShowH1)
      DrawBox("H1", h1Start, h1End, h1High, h1Low, H1Color, H1BoxWidth, false, true);

   if(ShowM30) DrawTF("M30", PERIOD_M30, h1Start, h1End, h1High, h1Low, M30Color, M30BoxWidth);
   if(ShowM15) DrawTF("M15", PERIOD_M15, h1Start, h1End, h1High, h1Low, M15Color, M15BoxWidth);
   if(ShowM5)  DrawTF("M5",  PERIOD_M5,  h1Start, h1End, h1High, h1Low, M5Color,  M5BoxWidth);
   if(ShowM1)  DrawTF("M1",  PERIOD_M1,  h1Start, h1End, h1High, h1Low, M1Color,  M1BoxWidth);

   if(ShowMainLabel)
   {
      string txt = "H1 CONTAINER | " +
                   TimeToString(h1Start, TIME_DATE|TIME_MINUTES) +
                   " | 25 / 50 / 75%";
      DrawLabel(ObjectPrefix + "MAIN_LABEL", h1Start, h1High, txt, H1Color);
   }
   else
   {
      ObjectDelete(0, ObjectPrefix + "MAIN_LABEL");
   }
}

//==================================================================
// LIGHT UPDATE - only the boxes that can still move
//==================================================================

void UpdateLiveBoxes(datetime h1Start, datetime h1End, double h1High, double h1Low)
{
   if(ShowH1)
      DrawBox("H1", h1Start, h1End, h1High, h1Low, H1Color, H1BoxWidth, false, true);

   if(ShowM30) DrawBarBox("M30", PERIOD_M30, 0, h1Start, h1End, h1High, h1Low, M30Color, M30BoxWidth);
   if(ShowM15) DrawBarBox("M15", PERIOD_M15, 0, h1Start, h1End, h1High, h1Low, M15Color, M15BoxWidth);
   if(ShowM5)  DrawBarBox("M5",  PERIOD_M5,  0, h1Start, h1End, h1High, h1Low, M5Color,  M5BoxWidth);
   if(ShowM1)  DrawBarBox("M1",  PERIOD_M1,  0, h1Start, h1End, h1High, h1Low, M1Color,  M1BoxWidth);

   if(ShowMainLabel)
      DrawLabel(ObjectPrefix + "MAIN_LABEL", h1Start, h1High,
                "H1 CONTAINER | " + TimeToString(h1Start, TIME_DATE|TIME_MINUTES) +
                " | 25 / 50 / 75%", H1Color);
}

//==================================================================
// MAIN REFRESH
//==================================================================

void Refresh()
{
   int hs = AutoFollowCurrentH1 ? 0 : g_shift;

   if(iBars(Symbol(), PERIOD_H1) <= hs)
      return;

   datetime h1Start = iTime(Symbol(), PERIOD_H1, hs);
   if(h1Start <= 0)
      return;

   double h1High = iHigh(Symbol(), PERIOD_H1, hs);
   double h1Low  = iLow (Symbol(), PERIOD_H1, hs);
   if(h1High <= 0.0 || h1Low <= 0.0 || h1High < h1Low)
      return;

   datetime h1End = h1Start + PeriodSeconds(PERIOD_H1);

   bool containerChanged = (h1Start != g_h1Start || hs != g_drawnShift);

   if(containerChanged)
   {
      DeleteAll();
      g_h1Start       = h1Start;
      g_drawnShift    = hs;
      g_lastRebuild   = 0;
      g_containerLive = (hs == 0);
   }

   ENUM_TIMEFRAMES lowTF  = LowestEnabledTF();
   datetime        lowBar = iTime(Symbol(), lowTF, 0);

   if(containerChanged || lowBar != g_lastRebuild)
   {
      RebuildAll(h1Start, h1End, h1High, h1Low);
      g_lastRebuild = lowBar;
      ChartRedraw();
      return;
   }

   // A closed container cannot change any more.
   if(!g_containerLive)
      return;

   UpdateLiveBoxes(h1Start, h1End, h1High, h1Low);
   ChartRedraw();
}

//==================================================================
// EVENTS
//==================================================================

int OnInit()
{
   IndicatorShortName("H1 Container - M30 M15 M5 M1 - 25/50/75");

   g_shift = (H1Shift < 0) ? 0 : H1Shift;

   if(StringLen(ObjectPrefix) == 0)
   {
      Print("ObjectPrefix must not be empty.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_h1Start     = 0;
   g_drawnShift  = -1;
   g_lastRebuild = 0;

   DeleteAll();
   return INIT_SUCCEEDED;
}

//------------------------------------------------------------------
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
   Refresh();
   return rates_total;
}

//------------------------------------------------------------------
void OnDeinit(const int reason)
{
   DeleteAll();
   ChartRedraw();
}
//+------------------------------------------------------------------+
