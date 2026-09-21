//+------------------------------------------------------------------+
//|                                             MSNR_KeyLevels_MTF.mq5|
//|                             Malaysian Support & Resistance levels |
//|                              M5 / M10 / M15 / H1 / H4 / D1 + HUD  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Vesath"
#property link      "https://www.mql5.com/en/users/vesath"
#property version   "3.00"

#property description "Malaysian SNR key levels (A, V, SBR, RBS) from six timeframes at once."
#property description "An on-chart panel switches M5, M10, M15, H1, H4 and D1 on and off with one click."
#property description "Levels are built from closed candles only and are independent of the chart timeframe."

#property indicator_chart_window
#property indicator_plots 0

#define TF_COUNT 6

//====================================================================
// INPUTS
//====================================================================

input group "=== MSNR logic ==="

input bool     FreshOnly           = true;

// true  = any wick touching the level breaks freshness
// false = only a candle body touching the level breaks freshness
input bool     WickMakesUnfresh    = true;

//--- which level types to display
input bool     ShowA               = true;
input bool     ShowV               = true;
input bool     ShowSBR             = true;
input bool     ShowRBS             = true;

input group "=== Level type colors ==="

input color    AColor              = clrRed;
input color    VColor              = clrDodgerBlue;
input color    SBRColor            = clrOrange;
input color    RBSColor            = clrLimeGreen;

input int      LineWidth           = 1;

input group "=== Line style per timeframe ==="

input ENUM_LINE_STYLE StyleM5      = STYLE_SOLID;
input ENUM_LINE_STYLE StyleM10     = STYLE_DOT;
input ENUM_LINE_STYLE StyleM15     = STYLE_DOT;
input ENUM_LINE_STYLE StyleH1      = STYLE_DASH;
input ENUM_LINE_STYLE StyleH4      = STYLE_DASH;
input ENUM_LINE_STYLE StyleD1      = STYLE_DASHDOT;

input group "=== History depth per timeframe (bars) ==="

input int      LookbackM5          = 3000;
input int      LookbackM10         = 2000;
input int      LookbackM15         = 2000;
input int      LookbackH1          = 1500;
input int      LookbackH4          = 1000;
input int      LookbackD1          = 500;

input group "=== Max visible levels per timeframe ==="

input int      MaxLevelsM5         = 30;
input int      MaxLevelsM10        = 20;
input int      MaxLevelsM15        = 20;
input int      MaxLevelsH1         = 15;
input int      MaxLevelsH4         = 10;
input int      MaxLevelsD1         = 10;

input group "=== Price labels ==="

input bool     ShowLabels          = true;
input int      LabelFontSize       = 8;
input int      LabelShiftBars      = 3;

input group "=== HUD: position and size ==="

input int      HudX                = 14;
input int      HudY                = 20;
input int      HudColumns          = 2;      // 2 = 2x3 grid, 1 = column, 6 = single row
input int      HudBtnWidth         = 82;
input int      HudBtnHeight        = 28;
input int      HudGap              = 6;
input int      HudPadding          = 12;

input group "=== HUD: text ==="

input string   HudTitle            = "MSNR KEYLEVELS";
input string   HudSubTitle         = "by strostor";
input string   HudFont             = "Segoe UI";
input int      HudTitleSize        = 11;
input int      HudSubSize          = 8;
input int      HudBtnFontSize      = 9;

input group "=== HUD: colors ==="

input color    HudPanelColor       = C'22,24,30';
input color    HudBorderColor      = C'58,62,74';
input color    HudAccentColor      = C'0,170,140';
input color    HudTitleColor       = clrWhite;
input color    HudSubColor         = C'128,134,148';
input color    HudOnColor          = C'0,150,124';
input color    HudOnTextColor      = clrWhite;
input color    HudOffColor         = C'38,41,50';
input color    HudOffTextColor     = C'140,146,160';
input color    HudFooterColor      = C'128,134,148';

input group "=== Button start-up state ==="

// used only when no saved state exists for this symbol
input bool     StartM5             = true;
input bool     StartM10            = false;
input bool     StartM15            = false;
input bool     StartH1             = false;
input bool     StartH4             = false;
input bool     StartD1             = false;

input bool     RememberState       = true;

input group "=== Stability ==="

// remove leftover objects of previous copies of this indicator
// keep it ON unless you deliberately run two copies on one chart
input bool     CleanupOldObjects   = true;

// self-heal interval in seconds: rebuilds the HUD / lines if the chart
// dropped them (timeframe switch, re-attach, "delete all objects")
input int      SelfHealSeconds     = 2;

//====================================================================
// GLOBALS
//====================================================================

enum LevelType
{
   LEVEL_A   = 0,
   LEVEL_V   = 1,
   LEVEL_SBR = 2,
   LEVEL_RBS = 3
};

struct MSNRLevel
{
   double   price;
   int      type;
   datetime created;
   datetime lastChange;
   bool     fresh;
   int      tf;         // index inside TFList
};

ENUM_TIMEFRAMES TFList[TF_COUNT] =
{
   PERIOD_M5, PERIOD_M10, PERIOD_M15,
   PERIOD_H1, PERIOD_H4,  PERIOD_D1
};

string TFNames[TF_COUNT] =
{
   "M5", "M10", "M15", "H1", "H4", "D1"
};

bool            TFOn[TF_COUNT];
int             TFLookback[TF_COUNT];
int             TFMaxLevels[TF_COUNT];
ENUM_LINE_STYLE TFStyle[TF_COUNT];

MSNRLevel Draw[];              // levels currently drawn (all timeframes)

//--- computed HUD layout
int hCols, hRows, hBtnW, hBtnH, hGap, hPad;
int hPanelW, hPanelH, hBtnTop, hFooterY, hSepY;

datetime LastBarTime[TF_COUNT];

//--- object names are unique per indicator copy, so an old copy being
//--- unloaded can never delete the objects of the new one
string BASE_PREFIX  = "MSNR3_";
string INSTANCE_TAG = "";
string LEVEL_PREFIX = "MSNR3_L_";
string HUD_PREFIX   = "MSNR3_HUD_";

void InitPrefixes()
{
   if(INSTANCE_TAG == "")
      INSTANCE_TAG = IntegerToString((int)(ChartID() % 100000)) + "x"
                     + IntegerToString((int)(GetMicrosecondCount() % 1000000));

   LEVEL_PREFIX = BASE_PREFIX + INSTANCE_TAG + "_L_";
   HUD_PREFIX   = BASE_PREFIX + INSTANCE_TAG + "_H_";
}

//====================================================================
// HELPERS
//====================================================================

string TypeName(int type)
{
   switch(type)
   {
      case LEVEL_A:   return "A";
      case LEVEL_V:   return "V";
      case LEVEL_SBR: return "SBR";
      case LEVEL_RBS: return "RBS";
   }
   return "";
}

//--------------------------------------------------------------------

color TypeColor(int type)
{
   switch(type)
   {
      case LEVEL_A:   return AColor;
      case LEVEL_V:   return VColor;
      case LEVEL_SBR: return SBRColor;
      case LEVEL_RBS: return RBSColor;
   }
   return clrWhite;
}

//--------------------------------------------------------------------

bool TypeEnabled(int type)
{
   switch(type)
   {
      case LEVEL_A:   return ShowA;
      case LEVEL_V:   return ShowV;
      case LEVEL_SBR: return ShowSBR;
      case LEVEL_RBS: return ShowRBS;
   }
   return false;
}

//--------------------------------------------------------------------

bool IsResistance(int type)
{
   return (type == LEVEL_A || type == LEVEL_SBR);
}

//--------------------------------------------------------------------

bool IsSupport(int type)
{
   return (type == LEVEL_V || type == LEVEL_RBS);
}

//--------------------------------------------------------------------

string LineName(int idx)
{
   return LEVEL_PREFIX + "LINE_" + IntegerToString(idx);
}

string TextName(int idx)
{
   return LEVEL_PREFIX + "TEXT_" + IntegerToString(idx);
}

string BtnName(int t)
{
   return HUD_PREFIX + "BTN_" + TFNames[t];
}

string HudName(string tag)
{
   return HUD_PREFIX + tag;
}

string StateKey(int t)
{
   return "MSNR3_" + _Symbol + "_" + TFNames[t];
}

//====================================================================
// OBJECT CLEANUP
//====================================================================

void DeleteByPrefix(string prefix)
{
   int total = ObjectsTotal(0);

   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);

      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

//====================================================================
// LEVEL TOUCH TESTS
//====================================================================

bool BodyTouches(double open, double close, double level)
{
   double top = MathMax(open, close);
   double bot = MathMin(open, close);

   return (bot <= level && top >= level);
}

//--------------------------------------------------------------------

bool WickTouches(double high, double low, double level)
{
   return (low <= level && high >= level);
}

//====================================================================
// APPLY ONE CANDLE TO THE ACTIVE LEVELS
//====================================================================

void ProcessBar(MSNRLevel &act[], MqlRates &bar)
{
   for(int i = ArraySize(act) - 1; i >= 0; i--)
   {
      // the candle that created the level cannot immediately break it
      if(bar.time <= act[i].created)
         continue;

      double level = act[i].price;

      //=============================================================
      // RESISTANCE: A / SBR
      //=============================================================

      if(IsResistance(act[i].type))
      {
         // close above = break, resistance becomes support
         if(bar.close > level)
         {
            act[i].type       = LEVEL_RBS;
            act[i].fresh      = true;
            act[i].lastChange = bar.time;
            continue;
         }

         bool touched = WickMakesUnfresh
                        ? WickTouches(bar.high, bar.low, level)
                        : BodyTouches(bar.open, bar.close, level);

         if(touched)
         {
            act[i].fresh      = false;
            act[i].lastChange = bar.time;

            if(FreshOnly)
            {
               // remove by swapping with the last element
               int last = ArraySize(act) - 1;

               if(i != last)
                  act[i] = act[last];

               ArrayResize(act, last);
            }
         }
      }

      //=============================================================
      // SUPPORT: V / RBS
      //=============================================================

      else if(IsSupport(act[i].type))
      {
         // close below = break, support becomes resistance
         if(bar.close < level)
         {
            act[i].type       = LEVEL_SBR;
            act[i].fresh      = true;
            act[i].lastChange = bar.time;
            continue;
         }

         bool touched = WickMakesUnfresh
                        ? WickTouches(bar.high, bar.low, level)
                        : BodyTouches(bar.open, bar.close, level);

         if(touched)
         {
            act[i].fresh      = false;
            act[i].lastChange = bar.time;

            if(FreshOnly)
            {
               int last = ArraySize(act) - 1;

               if(i != last)
                  act[i] = act[last];

               ArrayResize(act, last);
            }
         }
      }
   }
}

//====================================================================
// ADD A LEVEL
//====================================================================

void AddLevel(MSNRLevel &act[],
              double price,
              int type,
              datetime created,
              int tfIndex)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = 0; i < ArraySize(act); i++)
   {
      if(MathAbs(act[i].price - price) <= point)
         return;
   }

   int n = ArraySize(act);
   ArrayResize(act, n + 1);

   act[n].price      = price;
   act[n].type       = type;
   act[n].created    = created;
   act[n].lastChange = created;
   act[n].fresh      = true;
   act[n].tf         = tfIndex;
}

//====================================================================
// DETECT NEW A / V LEVELS
//====================================================================

void DetectNewLevel(MSNRLevel &act[],
                    MqlRates &previous,
                    MqlRates &current,
                    int tfIndex)
{
   // a doji does not create a level
   if(previous.close == previous.open) return;
   if(current.close  == current.open)  return;

   bool previousBull = previous.close > previous.open;
   bool previousBear = previous.close < previous.open;
   bool currentBull  = current.close  > current.open;
   bool currentBear  = current.close  < current.open;

   // A: bullish -> bearish, level = close of the bullish candle
   if(previousBull && currentBear)
      AddLevel(act, previous.close, LEVEL_A, current.time, tfIndex);

   // V: bearish -> bullish, level = close of the bearish candle
   if(previousBear && currentBull)
      AddLevel(act, previous.close, LEVEL_V, current.time, tfIndex);
}

//====================================================================
// LIMIT THE NUMBER OF LEVELS (keep the newest ones)
//====================================================================

void TrimOldest(MSNRLevel &act[], int maxCount)
{
   if(maxCount <= 0)
      return;

   while(ArraySize(act) > maxCount)
   {
      int      oldest     = -1;
      datetime oldestTime = D'2099.01.01';

      for(int i = 0; i < ArraySize(act); i++)
      {
         if(!TypeEnabled(act[i].type))
         {
            oldest = i;
            break;
         }

         if(act[i].created < oldestTime)
         {
            oldestTime = act[i].created;
            oldest     = i;
         }
      }

      if(oldest < 0)
         break;

      int last = ArraySize(act) - 1;

      if(oldest != last)
         act[oldest] = act[last];

      ArrayResize(act, last);
   }
}

//====================================================================
// BUILD LEVELS FOR A SINGLE TIMEFRAME
//====================================================================

void BuildTF(int t)
{
   MqlRates rates[];

   int copied = CopyRates(_Symbol,
                          TFList[t],
                          0,
                          TFLookback[t] + 5,
                          rates);

   if(copied < 10)
      return;

   ArraySetAsSeries(rates, false);

   // last element = current, unfinished candle
   int lastClosed = copied - 2;

   MSNRLevel act[];
   ArrayResize(act, 0);

   for(int i = 1; i <= lastClosed; i++)
   {
      // first: what this candle did to the existing levels
      ProcessBar(act, rates[i]);

      // then: new A/V levels from the candle pair
      DetectNewLevel(act, rates[i - 1], rates[i], t);
   }

   //--- drop level types disabled in the inputs
   for(int i = ArraySize(act) - 1; i >= 0; i--)
   {
      bool drop = (!TypeEnabled(act[i].type));

      if(FreshOnly && !act[i].fresh)
         drop = true;

      if(drop)
      {
         int last = ArraySize(act) - 1;

         if(i != last)
            act[i] = act[last];

         ArrayResize(act, last);
      }
   }

   TrimOldest(act, TFMaxLevels[t]);

   //--- append to the draw list
   int base = ArraySize(Draw);
   int add  = ArraySize(act);

   ArrayResize(Draw, base + add);

   for(int i = 0; i < add; i++)
      Draw[base + i] = act[i];
}

//====================================================================
// DRAWING
//====================================================================

datetime LabelTime()
{
   return iTime(_Symbol, _Period, 0)
          + (datetime)(PeriodSeconds(_Period) * LabelShiftBars);
}

//--------------------------------------------------------------------

void DrawOne(int idx)
{
   string line = LineName(idx);
   string text = TextName(idx);

   ObjectDelete(0, line);
   ObjectDelete(0, text);

   //--- horizontal line
   if(ObjectFind(0, line) < 0)
      if(!ObjectCreate(0, line, OBJ_HLINE, 0, 0, Draw[idx].price))
         return;

   ObjectSetDouble (0, line, OBJPROP_PRICE,      Draw[idx].price);
   ObjectSetInteger(0, line, OBJPROP_COLOR,      TypeColor(Draw[idx].type));
   ObjectSetInteger(0, line, OBJPROP_STYLE,      TFStyle[Draw[idx].tf]);
   ObjectSetInteger(0, line, OBJPROP_WIDTH,      LineWidth);
   ObjectSetInteger(0, line, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, line, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, line, OBJPROP_BACK,       false);
   ObjectSetInteger(0, line, OBJPROP_HIDDEN,     true);

   ObjectSetString (0, line, OBJPROP_TOOLTIP,
                    TFNames[Draw[idx].tf] + " " +
                    TypeName(Draw[idx].type) + " " +
                    DoubleToString(Draw[idx].price, _Digits));

   //--- price label
   if(!ShowLabels)
      return;

   string label = TFNames[Draw[idx].tf] + " "
                  + TypeName(Draw[idx].type) + " "
                  + DoubleToString(Draw[idx].price, _Digits);

   bool textReady = (ObjectFind(0, text) >= 0);

   if(!textReady)
      textReady = ObjectCreate(0, text, OBJ_TEXT, 0, LabelTime(), Draw[idx].price);

   if(textReady)
   {
      ObjectMove(0, text, 0, LabelTime(), Draw[idx].price);

      ObjectSetString (0, text, OBJPROP_TEXT,       label);
      ObjectSetString (0, text, OBJPROP_FONT,       "Arial");
      ObjectSetInteger(0, text, OBJPROP_FONTSIZE,   LabelFontSize);
      ObjectSetInteger(0, text, OBJPROP_COLOR,      TypeColor(Draw[idx].type));
      ObjectSetInteger(0, text, OBJPROP_ANCHOR,     ANCHOR_LEFT);
      ObjectSetInteger(0, text, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, text, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, text, OBJPROP_HIDDEN,     true);
   }
}

//--------------------------------------------------------------------

void DrawAll()
{
   for(int i = 0; i < ArraySize(Draw); i++)
      DrawOne(i);
}

//--------------------------------------------------------------------

void UpdateLabels()
{
   if(!ShowLabels)
      return;

   datetime lt = LabelTime();

   for(int i = 0; i < ArraySize(Draw); i++)
   {
      string text = TextName(i);

      if(ObjectFind(0, text) >= 0)
         ObjectMove(0, text, 0, lt, Draw[i].price);
   }
}

//====================================================================
// HUD
//====================================================================

int LevelCount(int t)
{
   int c = 0;

   for(int i = 0; i < ArraySize(Draw); i++)
      if(Draw[i].tf == t)
         c++;

   return c;
}

//--------------------------------------------------------------------

void CalcHudLayout()
{
   hCols = HudColumns;

   if(hCols < 1) hCols = 1;
   if(hCols > TF_COUNT) hCols = TF_COUNT;

   hRows = (TF_COUNT + hCols - 1) / hCols;

   hBtnW = MathMax(40, HudBtnWidth);
   hBtnH = MathMax(18, HudBtnHeight);
   hGap  = MathMax(0,  HudGap);
   hPad  = MathMax(4,  HudPadding);

   int titleH = HudTitleSize + 8;
   int subH   = HudSubSize   + 6;

   hSepY    = HudY + hPad + titleH + subH + 4;
   hBtnTop  = hSepY + 11;
   hFooterY = hBtnTop + hRows * hBtnH + (hRows - 1) * hGap + 10;

   hPanelW  = 2 * hPad + hCols * hBtnW + (hCols - 1) * hGap;
   hPanelH  = (hFooterY + HudSubSize + 6 + hPad) - HudY;
}

//--------------------------------------------------------------------

void MakeRect(string name, int x, int y, int w, int h,
              color bg, color border, int borderWidth)
{
   if(ObjectFind(0, name) < 0)
      if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
         return;

   ObjectSetInteger(0, name, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,        h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE,  BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,        border);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,        borderWidth);
   ObjectSetInteger(0, name, OBJPROP_STYLE,        STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_BACK,         false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,     false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,       true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,       0);
}

//--------------------------------------------------------------------

void MakeLabel(string name, int x, int y, string text,
               string font, int size, color clr)
{
   if(ObjectFind(0, name) < 0)
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
         return;

   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetString (0, name, OBJPROP_TEXT,       text);
   ObjectSetString (0, name, OBJPROP_FONT,       font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   size);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,     1);
}

//--------------------------------------------------------------------

void CreateHUD()
{
   DeleteByPrefix(HUD_PREFIX);

   CalcHudLayout();

   //--- panel background plus a thin accent bar on top
   MakeRect(HudName("PANEL"),
            HudX, HudY, hPanelW, hPanelH,
            HudPanelColor, HudBorderColor, 1);

   MakeRect(HudName("ACCENT"),
            HudX, HudY, hPanelW, 3,
            HudAccentColor, HudAccentColor, 1);

   //--- header
   MakeLabel(HudName("TITLE"),
             HudX + hPad,
             HudY + hPad + 2,
             HudTitle,
             HudFont + " Semibold",
             HudTitleSize,
             HudTitleColor);

   MakeLabel(HudName("SUB"),
             HudX + hPad,
             HudY + hPad + HudTitleSize + 10,
             HudSubTitle,
             HudFont,
             HudSubSize,
             HudSubColor);

   //--- separator
   MakeRect(HudName("SEP"),
            HudX + hPad, hSepY, hPanelW - 2 * hPad, 1,
            HudBorderColor, HudBorderColor, 1);

   //--- timeframe buttons
   for(int t = 0; t < TF_COUNT; t++)
   {
      string name = BtnName(t);

      int col = t % hCols;
      int row = t / hCols;

      int x = HudX + hPad + col * (hBtnW + hGap);
      int y = hBtnTop     + row * (hBtnH + hGap);

      if(ObjectFind(0, name) < 0)
         if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
            continue;

      ObjectSetInteger(0, name, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE,    x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE,    y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE,        hBtnW);
      ObjectSetInteger(0, name, OBJPROP_YSIZE,        hBtnH);
      ObjectSetString (0, name, OBJPROP_FONT,         HudFont + " Semibold");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,     HudBtnFontSize);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, HudBorderColor);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,     false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,       true);
      ObjectSetInteger(0, name, OBJPROP_ZORDER,       2);
      ObjectSetInteger(0, name, OBJPROP_STATE,        false);
   }

   //--- footer counter
   MakeLabel(HudName("FOOT"),
             HudX + hPad,
             hFooterY,
             "",
             HudFont,
             HudSubSize,
             HudFooterColor);

   UpdateHUD();
}

//--------------------------------------------------------------------

void UpdateHUD()
{
   int total = 0;
   int onTF  = 0;

   for(int t = 0; t < TF_COUNT; t++)
   {
      string name = BtnName(t);

      if(ObjectFind(0, name) < 0)
         continue;

      int cnt = LevelCount(t);

      if(TFOn[t])
      {
         total += cnt;
         onTF++;
      }

      string caption = TFNames[t];

      if(TFOn[t])
         caption += "  " + ShortToString(0x00B7) + "  " + IntegerToString(cnt);

      ObjectSetString (0, name, OBJPROP_TEXT,    caption);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, TFOn[t] ? HudOnColor      : HudOffColor);
      ObjectSetInteger(0, name, OBJPROP_COLOR,   TFOn[t] ? HudOnTextColor  : HudOffTextColor);
      ObjectSetInteger(0, name, OBJPROP_STATE,   false);
   }

   string foot = IntegerToString(total) + " levels / "
                 + IntegerToString(onTF) + " TF";

   if(ObjectFind(0, HudName("FOOT")) >= 0)
      ObjectSetString(0, HudName("FOOT"), OBJPROP_TEXT, foot);
}

//====================================================================
// FULL REBUILD
//====================================================================

void BuildAll()
{
   DeleteByPrefix(LEVEL_PREFIX);

   ArrayResize(Draw, 0);

   for(int t = 0; t < TF_COUNT; t++)
      if(TFOn[t])
         BuildTF(t);

   DrawAll();
   UpdateHUD();

   ChartRedraw();
}

//====================================================================
// SELF HEALING
//====================================================================

bool HudAlive()
{
   if(ObjectFind(0, HudName("PANEL")) < 0)
      return false;

   if(ObjectFind(0, BtnName(0)) < 0)
      return false;

   return true;
}

//--------------------------------------------------------------------

bool LevelsAlive()
{
   if(ArraySize(Draw) == 0)
      return true;

   return (ObjectFind(0, LineName(0)) >= 0);
}

//--------------------------------------------------------------------

void HealthCheck()
{
   bool repaired = false;

   if(!HudAlive())
   {
      CreateHUD();
      repaired = true;
   }

   if(!LevelsAlive())
   {
      DrawAll();
      UpdateHUD();
      repaired = true;
   }

   if(repaired)
      ChartRedraw();
}

//--------------------------------------------------------------------

bool NewBarSeen()
{
   bool changed = false;

   for(int t = 0; t < TF_COUNT; t++)
   {
      if(!TFOn[t])
         continue;

      datetime bt = iTime(_Symbol, TFList[t], 0);

      if(bt == 0)
         continue;

      if(bt != LastBarTime[t])
      {
         LastBarTime[t] = bt;
         changed        = true;
      }
   }

   return changed;
}

//====================================================================
// SAVE / LOAD BUTTON STATE
//====================================================================

void SaveState()
{
   if(!RememberState)
      return;

   for(int t = 0; t < TF_COUNT; t++)
      GlobalVariableSet(StateKey(t), TFOn[t] ? 1.0 : 0.0);
}

//--------------------------------------------------------------------

void LoadState()
{
   bool startDefaults[TF_COUNT];

   startDefaults[0] = StartM5;
   startDefaults[1] = StartM10;
   startDefaults[2] = StartM15;
   startDefaults[3] = StartH1;
   startDefaults[4] = StartH4;
   startDefaults[5] = StartD1;

   for(int t = 0; t < TF_COUNT; t++)
   {
      if(RememberState && GlobalVariableCheck(StateKey(t)))
         TFOn[t] = (GlobalVariableGet(StateKey(t)) > 0.5);
      else
         TFOn[t] = startDefaults[t];
   }
}

//====================================================================
// INIT
//====================================================================

int OnInit()
{
   TFLookback[0] = LookbackM5;
   TFLookback[1] = LookbackM10;
   TFLookback[2] = LookbackM15;
   TFLookback[3] = LookbackH1;
   TFLookback[4] = LookbackH4;
   TFLookback[5] = LookbackD1;

   TFMaxLevels[0] = MaxLevelsM5;
   TFMaxLevels[1] = MaxLevelsM10;
   TFMaxLevels[2] = MaxLevelsM15;
   TFMaxLevels[3] = MaxLevelsH1;
   TFMaxLevels[4] = MaxLevelsH4;
   TFMaxLevels[5] = MaxLevelsD1;

   TFStyle[0] = StyleM5;
   TFStyle[1] = StyleM10;
   TFStyle[2] = StyleM15;
   TFStyle[3] = StyleH1;
   TFStyle[4] = StyleH4;
   TFStyle[5] = StyleD1;

   for(int t = 0; t < TF_COUNT; t++)
      LastBarTime[t] = 0;

   InitPrefixes();

   // wipe anything left behind by a previous copy of this indicator,
   // otherwise old objects would block the new ones from being created
   if(CleanupOldObjects)
      DeleteByPrefix(BASE_PREFIX);

   LoadState();

   IndicatorSetString(INDICATOR_SHORTNAME, "MSNR MultiTF");

   CreateHUD();
   BuildAll();

   for(int t = 0; t < TF_COUNT; t++)
      LastBarTime[t] = iTime(_Symbol, TFList[t], 0);

   EventSetTimer(MathMax(1, SelfHealSeconds));

   Comment("");

   return INIT_SUCCEEDED;
}

//====================================================================
// TIMER: keeps working without incoming ticks and repairs the chart
//====================================================================

void OnTimer()
{
   if(NewBarSeen())
      BuildAll();
   else
      HealthCheck();
}

//====================================================================
// CALCULATE
//====================================================================

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
   if(NewBarSeen())
   {
      BuildAll();
   }
   else
   {
      HealthCheck();
      UpdateLabels();
   }

   return rates_total;
}

//====================================================================
// HUD CLICK HANDLING
//====================================================================

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      for(int t = 0; t < TF_COUNT; t++)
      {
         if(sparam != BtnName(t))
            continue;

         TFOn[t] = !TFOn[t];

         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);

         if(TFOn[t])
            LastBarTime[t] = iTime(_Symbol, TFList[t], 0);

         SaveState();
         BuildAll();

         return;
      }
   }

   if(id == CHARTEVENT_CHART_CHANGE)
   {
      HealthCheck();
      UpdateLabels();
      ChartRedraw();
   }
}

//====================================================================
// DEINIT
//====================================================================

void OnDeinit(const int reason)
{
   EventKillTimer();

   // only this copy's own objects, never a foreign prefix
   DeleteByPrefix(LEVEL_PREFIX);
   DeleteByPrefix(HUD_PREFIX);

   Comment("");

   ChartRedraw();
}
//+------------------------------------------------------------------+
