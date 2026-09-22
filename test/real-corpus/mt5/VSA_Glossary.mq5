//+------------------------------------------------------------------+
//|                                                   VSA Everywhere |
//|                     Dynamic Live-Candle HUD & Fixed Tower Panel  |
//+------------------------------------------------------------------+
#property copyright   "asma batool VSA"
#property link        "https://www.mql5.com"
#property version     "1.50"
#property indicator_separate_window

// 9 Plots, 14 Buffers
#property indicator_plots   9
#property indicator_buffers 14

//--- Plot 1: Volume Ultra Cloud (Background Fill)
#property indicator_label1  "Vol Ultra Fill"
#property indicator_type1   DRAW_FILLING
#property indicator_color1  C'18,78,160',C'18,78,160'

//--- Plot 2: Spread Ultra Cloud (Background Fill)
#property indicator_label2  "Spread Ultra Fill"
#property indicator_type2   DRAW_FILLING
#property indicator_color2  C'212,228,245',C'212,228,245'

//--- Plot 3: Spread Normal Cloud (Background Fill)
#property indicator_label3  "Spread Normal Fill"
#property indicator_type3   DRAW_FILLING
#property indicator_color3  C'230,240,250',C'230,240,250'

//--- Plot 4: Volume Histogram (Foreground)
#property indicator_label4  "Volume Bar"
#property indicator_type4   DRAW_COLOR_HISTOGRAM
#property indicator_style4  STYLE_SOLID
#property indicator_width4  4
#property indicator_color4  C'0,69,83',C'131,33,31',C'38,166,154',C'239,83,80',C'0,39,0',C'44,0,0',C'0,175,0',C'255,0,0'

//--- Plot 5: Volume MA Line
#property indicator_label5  "Volume MA"
#property indicator_type5   DRAW_LINE
#property indicator_style5  STYLE_SOLID
#property indicator_width5  1
#property indicator_color5  C'33,150,243'

//--- Plot 6: Spread Histogram (Foreground - Inverted)
#property indicator_label6  "Spread Bar"
#property indicator_type6   DRAW_COLOR_HISTOGRAM
#property indicator_style6  STYLE_SOLID
#property indicator_width6  1
#property indicator_color6  C'0,69,83',C'131,33,31',C'38,166,154',C'239,83,80',C'0,39,0',C'44,0,0',C'0,175,0',C'255,0,0'

//--- Plot 7: Spread MA Line (Negative)
#property indicator_label7  "Spread MA"
#property indicator_type7   DRAW_LINE
#property indicator_style7  STYLE_SOLID
#property indicator_width7  1
#property indicator_color7  C'33,150,243'

//--- Plot 8 & 9: Auto-Scale Headroom & Floor
#property indicator_label8  "Scale Headroom"
#property indicator_type8   DRAW_NONE
#property indicator_label9  "Scale Floor"
#property indicator_type9   DRAW_NONE

//--- Indicator Buffers
double BufferVolBandHigh[];
double BufferVolBandUltra[];
double BufferSpdBandHigh[];
double BufferSpdBandUltra[];
double BufferSpdBandLow[];
double BufferSpdBandHigh2[];

double BufferVolVal[];
double BufferVolCol[];
double BufferVolMA[];

double BufferSpdVal[];
double BufferSpdCol[];
double BufferSpdMA[];

double BufferHeadroom[];
double BufferFloor[];

//--- Enumerations
enum ENUM_VSA_MA_TYPE
 {
  VSA_MA_SMA = 0,  // SMA
  VSA_MA_EMA = 1,  // EMA
  VSA_MA_SMMA = 2, // SMMA
  VSA_MA_WMA = 3   // WMA
 };

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== Performance Limit ==="
input int                InpLimitBars            = 2000;         // Scan Limit (Max 2k Bars)

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input group "=== Left Side Tower Panel (Glossary) ==="
input bool               InpShowTowerPanel       = true;         // Show Tower Panel on Left
input int                InpTowerX               = 15;           // Tower X Offset (Pixels)
input int                InpTowerY               = 30;           // Tower Y Offset (Pixels)
input int                InpTowerWidth           = 175;          // Tower Panel Width (Pixels)

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input group "=== Main Chart Candle Labels (Closed Bars Only) ==="
input bool               InpShowMainChartLabels  = true;         // Show Patterns on Main Chart (Bar Close Only)
input int                InpMainChartLimitBars   = 500;          // Max Bars for Main Chart Labels
input int                InpMainChartFontSize    = 8;            // Main Chart Font Size
input double             InpMainChartOffsetMult  = 0.40;         // Candle Offset Multiplier

input group "=== Indicator Subwindow Settings ==="
input bool               InpShowShapes           = true;         // Show Baseline Dots
input bool               InpShowLabels           = true;         // Show Labels in Subwindow
input bool               InpShowForecastBadges   = true;         // Show Live Forecast Badges
input int                InpCandleDistancePx     = 96;           // Badge Distance from Live Candle (~1 Inch in Pixels)

input group "=== Volume Settings ==="
input double             InpMultVolumeLow        = 0.5;          // Volume Low Multiplier
input double             InpMultVolumeHigh       = 1.5;          // Volume High Multiplier
input double             InpMultVolumeUltra      = 3.0;          // Volume Ultra Multiplier
input int                InpMALengthVolume       = 20;           // Volume MA Length
input ENUM_VSA_MA_TYPE   InpMATypeVolume         = VSA_MA_SMA;   // Volume MA Type

input group "=== Spread Settings ==="
input double             InpMultSpreadLow        = 0.5;          // Spread Low Multiplier
input double             InpMultSpreadHigh       = 1.5;          // Spread High Multiplier
input double             InpMultSpreadUltra      = 3.0;          // Spread Ultra Multiplier
input int                InpMALengthSpread       = 5;            // Spread MA Length
input ENUM_VSA_MA_TYPE   InpMATypeSpread         = VSA_MA_SMA;   // Spread MA Type
input int                InpSpreadScaleBars      = 100;          // Bars for Spread Auto-Scale

input group "=== Candlestick Geometry ==="
input double             InpDojiMaxBody          = 10.0;         // Doji: Max Body (%)
input double             InpPinBarMaxBody        = 33.0;         // Pin Bar: Max Body (%)
input double             InpPinBarMinWick        = 60.0;         // Pin Bar: Min Wick (%)
input double             InpSpinTopMinWick       = 34.0;         // Spinning Top: Min Wicks (%)

//--- Global Variables
string g_prefix;
string g_shortName = "VSA All";
int    g_subwindow = -1;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
 {
  g_prefix = "VSA_" + IntegerToString(ChartID()) + "_";
// 1. Background Fill Plots (Underneath)
  SetIndexBuffer(0,  BufferVolBandHigh,  INDICATOR_DATA);
  SetIndexBuffer(1,  BufferVolBandUltra, INDICATOR_DATA);
  SetIndexBuffer(2,  BufferSpdBandHigh,  INDICATOR_DATA);
  SetIndexBuffer(3,  BufferSpdBandUltra, INDICATOR_DATA);
  SetIndexBuffer(4,  BufferSpdBandLow,   INDICATOR_DATA);
  SetIndexBuffer(5,  BufferSpdBandHigh2, INDICATOR_DATA);
// 2. Foreground Histograms and MA Lines
  SetIndexBuffer(6,  BufferVolVal,       INDICATOR_DATA);
  SetIndexBuffer(7,  BufferVolCol,       INDICATOR_COLOR_INDEX);
  SetIndexBuffer(8,  BufferVolMA,        INDICATOR_DATA);
  SetIndexBuffer(9,  BufferSpdVal,       INDICATOR_DATA);
  SetIndexBuffer(10, BufferSpdCol,       INDICATOR_COLOR_INDEX);
  SetIndexBuffer(11, BufferSpdMA,        INDICATOR_DATA);
// 3. Subwindow Headroom and Floor Buffers
  SetIndexBuffer(12, BufferHeadroom,     INDICATOR_DATA);
  SetIndexBuffer(13, BufferFloor,        INDICATOR_DATA);
  ArraySetAsSeries(BufferVolBandHigh,  true);
  ArraySetAsSeries(BufferVolBandUltra, true);
  ArraySetAsSeries(BufferSpdBandHigh,  true);
  ArraySetAsSeries(BufferSpdBandUltra, true);
  ArraySetAsSeries(BufferSpdBandLow,   true);
  ArraySetAsSeries(BufferSpdBandHigh2, true);
  ArraySetAsSeries(BufferVolVal,       true);
  ArraySetAsSeries(BufferVolCol,       true);
  ArraySetAsSeries(BufferVolMA,        true);
  ArraySetAsSeries(BufferSpdVal,       true);
  ArraySetAsSeries(BufferSpdCol,       true);
  ArraySetAsSeries(BufferSpdMA,        true);
  ArraySetAsSeries(BufferHeadroom,     true);
  ArraySetAsSeries(BufferFloor,        true);
  IndicatorSetInteger(INDICATOR_DIGITS, 1);
  IndicatorSetString(INDICATOR_SHORTNAME, g_shortName);
  return(INIT_SUCCEEDED);
 }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
 {
  ObjectsDeleteAll(0, g_prefix);
  ChartRedraw(0);
 }

//+------------------------------------------------------------------+
//| Moving Average Helper                                            |
//+------------------------------------------------------------------+
double CalculateMA(const double &arr[], int period, ENUM_VSA_MA_TYPE type, int index, int total)
 {
  if(index + period > total)
    return 0.0;
  switch(type)
   {
    case VSA_MA_SMA:
     {
      double sum = 0;
      for(int i = 0; i < period; i++)
        sum += arr[index + i];
      return (sum / period);
     }
    case VSA_MA_EMA:
     {
      double k = 2.0 / (period + 1.0);
      double ema = arr[index + period - 1];
      for(int i = period - 2; i >= 0; i--)
        ema = arr[index + i] * k + ema * (1.0 - k);
      return ema;
     }
    case VSA_MA_SMMA:
     {
      double sum = 0;
      for(int i = 0; i < period; i++)
        sum += arr[index + i];
      double smma = sum / period;
      for(int i = period - 1; i >= 0; i--)
        smma = (smma * (period - 1) + arr[index + i]) / period;
      return smma;
     }
    case VSA_MA_WMA:
     {
      double sum = 0;
      double denom = 0;
      for(int i = 0; i < period; i++)
       {
        double weight = period - i;
        sum += arr[index + i] * weight;
        denom += weight;
       }
      return (denom > 0 ? sum / denom : 0.0);
     }
   }
  return 0.0;
 }

//+------------------------------------------------------------------+
//| Get Color Index                                                  |
//+------------------------------------------------------------------+
int GetDetailColor(double val, double avg, double mLow, double mHigh, double mUltra, bool isBull)
 {
  double lvlLow   = avg * mLow;
  double lvlHigh  = avg * mHigh;
  double lvlUltra = avg * mUltra;
  if(isBull)
   {
    if(val > lvlUltra)
      return 6; // Ultra Green
    if(val > lvlHigh)
      return 4; // High Dark Green
    if(val < lvlLow)
      return 0; // Low Muted Green
    return 2;                    // Normal Teal
   }
  else
   {
    if(val > lvlUltra)
      return 7; // Ultra Red
    if(val > lvlHigh)
      return 5; // High Dark Maroon
    if(val < lvlLow)
      return 1; // Low Muted Red
    return 3;                    // Normal Coral Red
   }
 }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string GetLevelText(double mult, double mLow, double mHigh, double mUltra)
 {
  if(mult < mLow)
    return "Low";
  if(mult <= mHigh)
    return "Normal";
  if(mult <= mUltra)
    return "High";
  return "Ultra";
 }

//+------------------------------------------------------------------+
//| UI Helper: Draw Forecast Badges Dynamic to Live Candle (~1 Inch) |
//+------------------------------------------------------------------+
void PositionForecastBadge(string badgeId, int pixelX, int pixelY, string text)
 {
  string name = g_prefix + badgeId;
  if(ObjectFind(0, name) < 0)
   {
    ObjectCreate(0, name, OBJ_BUTTON, g_subwindow, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, 230);
    ObjectSetInteger(0, name, OBJPROP_YSIZE, 20);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
    ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'38,166,154');
    ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'38,166,154');
    ObjectSetInteger(0, name, OBJPROP_STATE, false);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
// Keep inside chart canvas boundaries
  int chartWidth = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, g_subwindow);
  if(pixelX + 235 > chartWidth)
    pixelX = chartWidth - 240;
  if(pixelX < 10)
    pixelX = 10;
  ObjectSetInteger(0, name, OBJPROP_XDISTANCE, pixelX);
  ObjectSetInteger(0, name, OBJPROP_YDISTANCE, pixelY);
  ObjectSetString(0, name, OBJPROP_TEXT, text);
 }

//+------------------------------------------------------------------+
//| UI Helper: Left-Side "Tower" Panel with Strict Z-Order (In Front)|
//+------------------------------------------------------------------+
void CreateTowerCell(string id, int x, int y, string text, color clr, bool isBold = false)
 {
  string name = g_prefix + "TWR_" + id;
  if(ObjectFind(0, name) < 0)
   {
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
    ObjectSetString(0, name, OBJPROP_FONT, isBold ? "Segoe UI Bold" : "Segoe UI");
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_BACK, false); // Keep text in front of container
   }
  ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
  ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
  ObjectSetString(0, name, OBJPROP_TEXT, text);
  ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
 }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void RenderLeftTowerPanel()
 {
  if(!InpShowTowerPanel)
    return;
  int startX = InpTowerX;
  int startY = InpTowerY;
  int panelW = InpTowerWidth;
  int curY = startY + 6;
  CreateTowerCell("TITLE", startX + 22, curY, "■ VSA GLOSSARY ■", C'220,225,235', true);
  curY += 17;
// Section 1: STRENGTH (SOS)
  CreateTowerCell("H_SOS", startX + 8, curY, "STRENGTH (SOS)", clrLime, true);
  curY += 14;
  string sosItems[8] =
   {
    "(DT)  Down Thrust",
    "(SC)  Selling Climax",
    "(NoE) No Effort Bear",
    "(NoR) Bear Effort NoR",
    "(IDT) Inv DownThrust",
    "(BH)  Bag Holder",
    "(PDT) Pseudo DT",
    "(NS)  No Supply"
   };
  for(int k = 0; k < 8; k++)
   {
    CreateTowerCell("SOS_" + IntegerToString(k), startX + 10, curY, sosItems[k], C'0,230,118');
    curY += 13;
   }
  curY += 5;
// Section 2: WEAKNESS (SOW)
  CreateTowerCell("H_SOW", startX + 8, curY, "WEAKNESS (SOW)", clrRed, true);
  curY += 14;
  string sowItems[8] =
   {
    "(UT)  Up Thrust",
    "(BC)  Buying Climax",
    "(NoE) No Effort Bull",
    "(NoR) Bull Effort NoR",
    "(IUT) Inv UpThrust",
    "(BS)  Bag Seller",
    "(PUT) Pseudo UT",
    "(ND)  No Demand"
   };
  for(int k = 0; k < 8; k++)
   {
    CreateTowerCell("SOW_" + IntegerToString(k), startX + 10, curY, sowItems[k], C'255,82,82');
    curY += 13;
   }
  curY += 5;
// Section 3: NEUTRALS & SHAPES
  CreateTowerCell("H_NEU", startX + 8, curY, "NEUTRALS & SHAPES", clrDodgerBlue, true);
  curY += 14;
  string neuItems[8] =
   {
    "(BD)  Balanced Doji",
    "(SD)  Strong Doji",
    "(BST) Bal. SpinTop",
    "(SST) Strong SpinTop",
    "[ ┯ ] Bull Pin Bar",
    "[ ┷ ] Bear Pin Bar",
    "[ + ] Doji Bar",
    "[ ╫ ] Spinning Top"
   };
  for(int k = 0; k < 8; k++)
   {
    color itemClr = (k < 4) ? C'68,138,255' : clrYellow;
    CreateTowerCell("NEU_" + IntegerToString(k), startX + 10, curY, neuItems[k], itemClr);
    curY += 13;
   }
  curY += 8;
  int panelH = curY - startY;
// 1. Main Background Box (Sent to background to prevent text overlay)
  string bgName = g_prefix + "TOWER_BG";
  if(ObjectFind(0, bgName) < 0)
   {
    ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, bgName, OBJPROP_COLOR, C'40,48,60');
    ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, C'16,20,28');
    ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, bgName, OBJPROP_BACK, true); // Behind all labels
   }
  ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, startX);
  ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, startY);
  ObjectSetInteger(0, bgName, OBJPROP_XSIZE, panelW);
  ObjectSetInteger(0, bgName, OBJPROP_YSIZE, panelH);
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
  if(rates_total < 40)
    return 0;
  if(g_subwindow < 0)
    g_subwindow = ChartWindowFind(0, g_shortName);
  RenderLeftTowerPanel();
  ArraySetAsSeries(time, true);
  ArraySetAsSeries(open, true);
  ArraySetAsSeries(high, true);
  ArraySetAsSeries(low, true);
  ArraySetAsSeries(close, true);
  ArraySetAsSeries(tick_volume, true);
  ArraySetAsSeries(volume, true);
// Scan limit set to max 2000 bars
  int limit = rates_total - prev_calculated;
  if(limit <= 0)
    limit = 1;
  if(prev_calculated == 0 || limit > InpLimitBars)
    limit = MathMin(rates_total - 1, InpLimitBars);
// Prepare Raw Series
  double arrVol[], arrSpd[];
  ArrayResize(arrVol, rates_total);
  ArrayResize(arrSpd, rates_total);
  ArraySetAsSeries(arrVol, true);
  ArraySetAsSeries(arrSpd, true);
  for(int i = 0; i < rates_total; i++)
   {
    arrVol[i] = (volume[i] > 0) ? (double)volume[i] : (double)tick_volume[i];
    arrSpd[i] = (high[i] - low[i]) / _Point;
    if(arrSpd[i] <= 0.0)
      arrSpd[i] = 1.0;
   }
// Auto-Scale multiplier for spread relative to volume
  int scaleLookback = MathMin(InpSpreadScaleBars, rates_total - 1);
  double maxV = 0.0, maxS = 0.0;
  for(int k = 0; k < scaleLookback; k++)
   {
    if(arrVol[k] > maxV)
      maxV = arrVol[k];
    if(arrSpd[k] > maxS)
      maxS = arrSpd[k];
   }
  double spreadMultiplier = (maxS > 0) ? (maxV / maxS) : 1.0;
// Main Calculation Loop
  for(int i = limit; i >= 0; i--)
   {
    double curV   = arrVol[i];
    double curMAV = CalculateMA(arrVol, InpMALengthVolume, InpMATypeVolume, i, rates_total);
    if(curMAV <= 0)
      curMAV = curV;
    double curS   = arrSpd[i];
    double curMAS = CalculateMA(arrSpd, InpMALengthSpread, InpMATypeSpread, i, rates_total);
    if(curMAS <= 0)
      curMAS = curS;
    bool isBull = (close[i] >= open[i]);
    // 1. Background Fill Calculations
    BufferVolBandHigh[i]  = curMAV * InpMultVolumeHigh;
    BufferVolBandUltra[i] = curMAV * InpMultVolumeUltra;
    BufferSpdBandLow[i]   = (-spreadMultiplier) * (curMAS * InpMultSpreadLow);
    BufferSpdBandHigh2[i] = (-spreadMultiplier) * (curMAS * InpMultSpreadHigh);
    BufferSpdBandHigh[i]  = (-spreadMultiplier) * (curMAS * InpMultSpreadHigh);
    BufferSpdBandUltra[i] = (-spreadMultiplier) * (curMAS * InpMultSpreadUltra);
    // 2. Foreground Histograms & Lines
    BufferVolVal[i]       = curV;
    BufferVolCol[i]       = GetDetailColor(curV, curMAV, InpMultVolumeLow, InpMultVolumeHigh, InpMultVolumeUltra, isBull);
    BufferVolMA[i]        = curMAV;
    BufferSpdVal[i]       = (-spreadMultiplier) * curS;
    BufferSpdCol[i]       = GetDetailColor(curS, curMAS, InpMultSpreadLow, InpMultSpreadHigh, InpMultSpreadUltra, isBull);
    BufferSpdMA[i]        = (-spreadMultiplier) * curMAS;
    // 3. Subwindow Headroom & Floor Buffer
    BufferHeadroom[i]     = MathMax(BufferVolBandUltra[i], curV) * 1.30;
    BufferFloor[i]        = MathMin(BufferSpdBandUltra[i], BufferSpdVal[i]) * 1.20;
    //---------------------------------------------------------
    // Pattern Identification
    //---------------------------------------------------------
    double sprdPoints = high[i] - low[i];
    if(sprdPoints <= 0)
      sprdPoints = _Point;
    double bodyPoints = MathAbs(close[i] - open[i]);
    double upWickPts  = high[i] - MathMax(open[i], close[i]);
    double dnWickPts  = MathMin(open[i], close[i]) - low[i];
    double bodyPct = (bodyPoints / sprdPoints) * 100.0;
    double upWick  = (upWickPts / sprdPoints) * 100.0;
    double dnWick  = (dnWickPts / sprdPoints) * 100.0;
    // Candlestick shapes
    bool isBullPin = (bodyPct <= InpPinBarMaxBody && dnWick >= InpPinBarMinWick);
    bool isBearPin = (bodyPct <= InpPinBarMaxBody && upWick >= InpPinBarMinWick);
    bool isDoji    = (bodyPct <= InpDojiMaxBody);
    bool isSpinTop = (upWick >= InpSpinTopMinWick && dnWick >= InpSpinTopMinWick && bodyPct < 30.0);
    // Volume conditions
    bool isVolUltra = (curV > curMAV * InpMultVolumeUltra);
    bool isVolHigh  = (curV > curMAV * InpMultVolumeHigh);
    bool isVolLow   = (curV < curMAV * InpMultVolumeLow);
    string vsaSig   = "";
    string vsaFull  = "";
    string reaction = "";
    color  sigClr   = clrNONE;
    string barPat   = "";
    string patFull  = "";
    // Pure Candlestick Shape Symbols (Yellow)
    if(isBullPin)
     {
      barPat = "┯";
      patFull = "Bull Pin Bar";
     }
    else
      if(isBearPin)
       {
        barPat = "┷";
        patFull = "Bear Pin Bar";
       }
      else
        if(isDoji)
         {
          barPat = "+";
          patFull = "Doji Bar";
         }
        else
          if(isSpinTop)
           {
            barPat = "╫";
            patFull = "Spinning Top";
           }
    // Signs of Strength (Green)
    if(isBullPin && (isVolHigh || isVolUltra))
     { vsaSig = "DT";  vsaFull = "Down Thrust (Spring)"; reaction = "Bullish Reversal. Supply absorbed below support. Expect upward markup."; sigClr = clrLime; }
    else
      if(!isBull && dnWick >= 25.0 && (isVolUltra || isVolHigh))
       { vsaSig = "SC";  vsaFull = "Selling Climax"; reaction = "Strong Bullish Accumulation. Panic selling absorbed by institutional money. Bottom expected."; sigClr = clrLime; }
      else
        if(!isBull && sprdPoints > curMAS * _Point && isVolLow)
         { vsaSig = "NoE"; vsaFull = "No Effort Bearish Result"; reaction = "Lack of Selling Pressure. Market fell without volume support. Bounce expected."; sigClr = clrLime; }
        else
          if(!isBull && (isVolHigh || isVolUltra) && bodyPct < 30.0)
           { vsaSig = "NoR"; vsaFull = "Bearish Effort No Result"; reaction = "Bullish Absorption. Heavy selling failed to break price down. High demand present."; sigClr = clrLime; }
          else
            if(isBearPin && (isVolHigh || isVolUltra))
             { vsaSig = "IDT"; vsaFull = "Inverse Down Thrust"; reaction = "Bullish Test. Bearish attempt failed. Potential rally ahead."; sigClr = clrLime; }
            else
              if(!isBull && isVolUltra && close[i] > (low[i] + sprdPoints * 0.4))
               { vsaSig = "BH";  vsaFull = "Bag Holder (End of Falling Market)"; reaction = "Institutional Accumulation. Smart money stopping the downtrend."; sigClr = clrLime; }
              else
                if(isBullPin && i < rates_total - 2 && curV < arrVol[i + 1] && curV < arrVol[i + 2])
                 { vsaSig = "PDT"; vsaFull = "Pseudo Down Thrust"; reaction = "Bullish Continuation. Rejection of lows with negligible supply."; sigClr = clrLime; }
                else
                  if(!isBull && isVolLow && i < rates_total - 2 && curV < arrVol[i + 1] && curV < arrVol[i + 2])
                   { vsaSig = "NS";  vsaFull = "No Supply"; reaction = "Confirmed Bullish Test. Lack of sellers confirming smart money is not offloading."; sigClr = clrLime; }
    // Signs of Weakness (Red)
    if(vsaSig == "")
     {
      if(isBearPin && (isVolHigh || isVolUltra))
       { vsaSig = "UT";  vsaFull = "Up Thrust"; reaction = "Bearish Reversal. Liquidity run above resistance swiftly rejected. Distribution active."; sigClr = clrRed; }
      else
        if(isBull && upWick >= 25.0 && (isVolUltra || isVolHigh))
         { vsaSig = "BC";  vsaFull = "Buying Climax"; reaction = "Strong Bearish Distribution. Retail FOMO absorbed by institutional sell orders. Top expected."; sigClr = clrRed; }
        else
          if(isBull && sprdPoints > curMAS * _Point && isVolLow)
           { vsaSig = "NoE"; vsaFull = "No Effort Bullish Result"; reaction = "Lack of Buying Power. Price rose with no volume; susceptible to sudden supply."; sigClr = clrRed; }
          else
            if(isBull && (isVolHigh || isVolUltra) && bodyPct < 30.0)
             { vsaSig = "NoR"; vsaFull = "Bullish Effort No Result"; reaction = "Bearish Absorption. High volume failed to push price higher. Heavy supply capping price."; sigClr = clrRed; }
            else
              if(isBullPin && (isVolHigh || isVolUltra) && high[i] >= high[i + 1])
               { vsaSig = "IUT"; vsaFull = "Inverse Up Thrust"; reaction = "Bearish Trap. Trapped buyers at the highs."; sigClr = clrRed; }
              else
                if(isBull && isVolUltra && close[i] < (high[i] - sprdPoints * 0.4))
                 { vsaSig = "BS";  vsaFull = "Bag Seller (End of Rising Market)"; reaction = "Exhaustion Volume. Smart money offloading inventory into late buyers."; sigClr = clrRed; }
                else
                  if(isBearPin && i < rates_total - 2 && curV < arrVol[i + 1] && curV < arrVol[i + 2])
                   { vsaSig = "PUT"; vsaFull = "Pseudo Up Thrust"; reaction = "Bearish Failure. Upward move met with no follow-through demand."; sigClr = clrRed; }
                  else
                    if(isBull && isVolLow && i < rates_total - 2 && curV < arrVol[i + 1] && curV < arrVol[i + 2])
                     { vsaSig = "ND";  vsaFull = "No Demand"; reaction = "Confirmed Bearish Test. Up bar on low volume; smart money has zero interest in higher prices."; sigClr = clrRed; }
     }
    // Neutrals (Blue)
    if(vsaSig == "")
     {
      if(isDoji && isVolUltra)
       {
        vsaSig = "SD";
        vsaFull = "Strong Doji";
        reaction = "High Volume Indecision. Imminent breakout pending.";
        sigClr = clrDodgerBlue;
       }
      else
        if(isDoji && isVolLow)
         {
          vsaSig = "QD";
          vsaFull = "Quiet Doji";
          reaction = "Low Volume Equilibrium. Market waiting for catalyst.";
          sigClr = clrDodgerBlue;
         }
        else
          if(isDoji)
           {
            vsaSig = "BD";
            vsaFull = "Balanced Doji";
            reaction = "Order flow balance between buyers and sellers.";
            sigClr = clrDodgerBlue;
           }
          else
            if(isSpinTop && isVolUltra)
             {
              vsaSig = "SST";
              vsaFull = "Strong Spinning Top";
              reaction = "High Volume Pause. Active battle at key level.";
              sigClr = clrDodgerBlue;
             }
            else
              if(isSpinTop && isVolLow)
               {
                vsaSig = "QST";
                vsaFull = "Quiet Spinning Top";
                reaction = "Consolidation / Low liquidity pause.";
                sigClr = clrDodgerBlue;
               }
              else
                if(isSpinTop)
                 {
                  vsaSig = "BST";
                  vsaFull = "Balanced Spinning Top";
                  reaction = "Equilibrium candle. Trend continuation pause.";
                  sigClr = clrDodgerBlue;
                 }
     }
    // ---------------------------------------------------------
    // Subwindow Baseline Dots (Created Once, Zero-Shake)
    // ---------------------------------------------------------
    if(InpShowShapes && i <= InpLimitBars && sigClr != clrNONE)
     {
      string dotName = g_prefix + "DOT_" + TimeToString(time[i]);
      if(ObjectFind(0, dotName) < 0)
       {
        ObjectCreate(0, dotName, OBJ_ARROW, g_subwindow, time[i], 0.0);
        ObjectSetInteger(0, dotName, OBJPROP_ARROWCODE, 159);
        ObjectSetInteger(0, dotName, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, dotName, OBJPROP_ANCHOR, ANCHOR_CENTER);
        ObjectSetInteger(0, dotName, OBJPROP_COLOR, sigClr);
       }
     }
    // ---------------------------------------------------------
    // Subwindow Labels (Created Once, Fully Visible)
    // ---------------------------------------------------------
    if(InpShowLabels && i <= InpLimitBars)
     {
      double yTop = MathMax(BufferVolBandUltra[i], BufferVolVal[i]) * 1.04;
      if(barPat != "")
       {
        string pName = g_prefix + "PAT_" + TimeToString(time[i]);
        if(ObjectFind(0, pName) < 0)
         {
          ObjectCreate(0, pName, OBJ_TEXT, g_subwindow, time[i], yTop * 1.14);
          ObjectSetInteger(0, pName, OBJPROP_COLOR, clrYellow);
          ObjectSetInteger(0, pName, OBJPROP_FONTSIZE, 9);
          ObjectSetString(0, pName, OBJPROP_FONT, "Segoe UI Bold");
          ObjectSetInteger(0, pName, OBJPROP_ANCHOR, ANCHOR_LOWER);
          ObjectSetString(0, pName, OBJPROP_TEXT, barPat);
         }
       }
      if(vsaSig != "")
       {
        string sName = g_prefix + "SIG_" + TimeToString(time[i]);
        if(ObjectFind(0, sName) < 0)
         {
          ObjectCreate(0, sName, OBJ_TEXT, g_subwindow, time[i], yTop);
          ObjectSetInteger(0, sName, OBJPROP_COLOR, sigClr);
          ObjectSetInteger(0, sName, OBJPROP_FONTSIZE, 8);
          ObjectSetString(0, sName, OBJPROP_FONT, "Segoe UI Bold");
          ObjectSetInteger(0, sName, OBJPROP_ANCHOR, ANCHOR_LOWER);
          ObjectSetString(0, sName, OBJPROP_TEXT, vsaSig);
         }
       }
     }
    // ---------------------------------------------------------
    // Main Chart: Closed Bars Only (i >= 1) with Hover Tooltips
    // ---------------------------------------------------------
    if(InpShowMainChartLabels && i >= 1 && i <= InpMainChartLimitBars && (vsaSig != "" || barPat != ""))
     {
      string mSigName = g_prefix + "M_SIG_" + TimeToString(time[i]);
      string mPatName = g_prefix + "M_PAT_" + TimeToString(time[i]);
      if(ObjectFind(0, mSigName) < 0 && ObjectFind(0, mPatName) < 0)
       {
        double offset = MathMax(sprdPoints * InpMainChartOffsetMult, 12 * _Point);
        bool placeAbove = false;
        if(sigClr == clrLime || (sigClr == clrNONE && barPat == "┯"))
          placeAbove = false;
        else
          if(sigClr == clrRed || (sigClr == clrNONE && barPat == "┷"))
            placeAbove = true;
          else
            placeAbove = isBull;
        double yMainSig = placeAbove ? (high[i] + offset) : (low[i] - offset);
        double yMainPat = placeAbove ? (high[i] + offset * 1.6) : (low[i] - offset * 1.6);
        long anchorType = placeAbove ? ANCHOR_LOWER : ANCHOR_UPPER;
        // Prepare Tooltip String
        double volMult = (curMAV > 0) ? (curV / curMAV) : 1.0;
        string volTier = GetLevelText(volMult, InpMultVolumeLow, InpMultVolumeHigh, InpMultVolumeUltra);
        string tooltipText = StringFormat(
                               "VSA PATTERN: %s %s\n" +
                               "═════════════════════════════════════\n" +
                               "Time   : %s\n" +
                               "Volume : %.0f [%s - %.2fx MA]\n" +
                               "Spread : %.1f pts\n" +
                               "Candle : %s\n" +
                               "═════════════════════════════════════\n" +
                               "Reaction: %s",
                               (vsaSig != "" ? "(" + vsaSig + ")" : ""),
                               (vsaFull != "" ? vsaFull : patFull),
                               TimeToString(time[i], TIME_DATE | TIME_MINUTES),
                               curV, volTier, volMult,
                               sprdPoints / _Point,
                               (patFull != "" ? patFull : (isBull ? "Bullish Candle" : "Bearish Candle")),
                               (reaction != "" ? reaction : "Standard volume equilibrium.")
                             );
        // Pattern Shape Label (Yellow)
        if(barPat != "")
         {
          ObjectCreate(0, mPatName, OBJ_TEXT, 0, time[i], (vsaSig != "" ? yMainPat : yMainSig));
          ObjectSetInteger(0, mPatName, OBJPROP_COLOR, clrYellow);
          ObjectSetInteger(0, mPatName, OBJPROP_FONTSIZE, InpMainChartFontSize);
          ObjectSetString(0, mPatName, OBJPROP_FONT, "Segoe UI Bold");
          ObjectSetInteger(0, mPatName, OBJPROP_ANCHOR, anchorType);
          ObjectSetString(0, mPatName, OBJPROP_TEXT, barPat);
          ObjectSetString(0, mPatName, OBJPROP_TOOLTIP, tooltipText);
         }
        // VSA Signal Label (Green / Red / Blue)
        if(vsaSig != "")
         {
          ObjectCreate(0, mSigName, OBJ_TEXT, 0, time[i], yMainSig);
          ObjectSetInteger(0, mSigName, OBJPROP_COLOR, sigClr);
          ObjectSetInteger(0, mSigName, OBJPROP_FONTSIZE, InpMainChartFontSize);
          ObjectSetString(0, mSigName, OBJPROP_FONT, "Segoe UI Bold");
          ObjectSetInteger(0, mSigName, OBJPROP_ANCHOR, anchorType);
          ObjectSetString(0, mSigName, OBJPROP_TEXT, vsaSig);
          ObjectSetString(0, mSigName, OBJPROP_TOOLTIP, tooltipText);
         }
       }
     }
   }
//---------------------------------------------------------
// Live Forecast Badges Dynamic Positioning (~1 Inch from Live Candle)
//---------------------------------------------------------
  if(InpShowForecastBadges)
   {
    datetime barStart = time[0];
    int barSeconds = PeriodSeconds();
    int elapsedSec = (int)(TimeCurrent() - barStart);
    if(elapsedSec < 0)
      elapsedSec = 0;
    double elapsedPct = (barSeconds > 0) ? ((double)elapsedSec / (double)barSeconds) : 1.0;
    if(elapsedPct > 1.0)
      elapsedPct = 1.0;
    if(elapsedPct < 0.05)
      elapsedPct = 0.05;
    // Volume Forecast
    double curV = arrVol[0];
    double curAvgV = BufferVolMA[0];
    double curVMult = (curAvgV > 0) ? (curV / curAvgV) : 1.0;
    double projV = curV / elapsedPct;
    double projVMult = (curAvgV > 0) ? (projV / curAvgV) : 1.0;
    string txtVol = StringFormat("⏱️ %.0f%%  🔎 x%.2f %s  ✅ x%.2f %s",
                                 elapsedPct * 100.0,
                                 projVMult, GetLevelText(projVMult, InpMultVolumeLow, InpMultVolumeHigh, InpMultVolumeUltra),
                                 curVMult,  GetLevelText(curVMult,  InpMultVolumeLow, InpMultVolumeHigh, InpMultVolumeUltra));
    // Spread Forecast
    double curS = arrSpd[0];
    double curAvgS = CalculateMA(arrSpd, InpMALengthSpread, InpMATypeSpread, 0, rates_total);
    double curSMult = (curAvgS > 0) ? (curS / curAvgS) : 1.0;
    double projS = curS / MathPow(elapsedPct, 0.65);
    double projSMult = (curAvgS > 0) ? (projS / curAvgS) : 1.0;
    string txtSpd = StringFormat("⏱️ %.0f%%  🔎 x%.2f %s  ✅ x%.2f %s",
                                 elapsedPct * 100.0,
                                 projSMult, GetLevelText(projSMult, InpMultSpreadLow, InpMultSpreadHigh, InpMultSpreadUltra),
                                 curSMult,  GetLevelText(curSMult,  InpMultSpreadLow, InpMultSpreadHigh, InpMultSpreadUltra));
    // Convert Live Candle time[0] to Pixel X in subwindow
    int candlePixelX = 0, dummyY = 0;
    ChartTimePriceToXY(0, g_subwindow, time[0], 0, candlePixelX, dummyY);
    int badgeTargetX = candlePixelX + InpCandleDistancePx;
    PositionForecastBadge("VOL_PILL", badgeTargetX, 15, txtVol);
    PositionForecastBadge("SPD_PILL", badgeTargetX, 40, txtSpd);
   }
  return(rates_total);
 }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
