//+------------------------------------------------------------------+
//|                                RangeCompressionPercentile.mq5    |
//|                                  Copyright 2026, Adesewa Gbadebo |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Adesewa Gbadebo"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Ranks the current period's range-so-far against the full historical "
#property description "distribution of past ranges (a true percentile, not just a comparison "
#property description "to the average like ADR%), flagging statistical compression or expansion."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0
#property strict

//+------------------------------------------------------------------+
//| Input parameters                                                  |
//+------------------------------------------------------------------+
input group "=== Range Settings ==="
input ENUM_TIMEFRAMES InpRangePeriod    = PERIOD_D1; // Range Period (which timeframe defines one "range")
input int              InpLookbackPeriods = 100;      // Lookback (completed periods used to build the distribution)

input group "=== Thresholds ==="
input double InpCompressionPercentile = 20.0; // Compression Threshold (percentile at/below = "COMPRESSED")
input double InpExpansionPercentile   = 80.0; // Expansion Threshold (percentile at/above = "EXPANDED")

input group "=== Update ==="
input bool InpUpdateOnNewBarOnly = true; // Recalculate Only on a New Chart Bar

input group "=== Panel Layout ==="
input ENUM_BASE_CORNER InpPanelCorner    = CORNER_LEFT_UPPER; // Panel Corner
input int               InpPanelXDistance = 12;   // Panel X Distance (pixels)
input int               InpPanelYDistance = 18;   // Panel Y Distance (pixels)
input int               InpFontSize       = 9;    // Font Size
input int               InpGaugeWidth     = 160;  // Gauge Track Width (pixels)
input int               InpGaugeHeight    = 10;   // Gauge Track Height (pixels)

input group "=== Colors ==="
input color InpCompressedColor = clrDeepSkyBlue; // Color — Compressed (low percentile)
input color InpNormalColor     = clrSilver;      // Color — Normal (mid-range percentile)
input color InpExpandedColor   = clrRed;         // Color — Expanded (high percentile)
input color InpPanelTextColor  = clrWhite;       // Title / Static Text Color
input color InpPanelBgColor    = C'20,20,20';    // Panel Background Color

//+------------------------------------------------------------------+
//| Global variables                                                  |
//+------------------------------------------------------------------+
string g_Prefix = "RCP_";

string g_PanelBgName;
string g_LineNames[5];   // one label object per row — never a single multi-line label
string g_GaugeTrackName;
string g_GaugeMarkerName;

int g_LineHeight   = 0;
int g_PanelPadTop  = 6;
int g_PanelPadSide = 8;

datetime g_LastBarTime = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                        |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpLookbackPeriods < 10)
     {
      Alert("RangeCompressionPercentile: 'Lookback' must be at least 10 periods.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpCompressionPercentile < 0.0 || InpCompressionPercentile > 100.0 ||
      InpExpansionPercentile < 0.0 || InpExpansionPercentile > 100.0 ||
      InpCompressionPercentile >= InpExpansionPercentile)
     {
      Alert("RangeCompressionPercentile: thresholds must be between 0 and 100, with Compression < Expansion.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   IndicatorSetString(INDICATOR_SHORTNAME, "Range Compression Percentile");

   g_PanelBgName      = g_Prefix + "PanelBG";
   g_GaugeTrackName   = g_Prefix + "GaugeTrack";
   g_GaugeMarkerName  = g_Prefix + "GaugeMarker";

   for(int i = 0; i < 5; i++)
      g_LineNames[i] = g_Prefix + "Line" + IntegerToString(i);

   g_LineHeight = InpFontSize + 8;

   CreatePanel();
   g_LastBarTime = 0; // forces a full refresh on the very first OnCalculate call

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- remove every chart object this indicator has created, identified by its unique prefix
   ObjectsDeleteAll(0, g_Prefix);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                             |
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
   if(rates_total < 1)
      return(0);

//--- the percentile calculation reads a small, fixed number of bars on
//--- InpRangePeriod (bounded by InpLookbackPeriods), never the current
//--- chart's own history, so its cost per refresh is small and constant;
//--- InpUpdateOnNewBarOnly simply throttles how often that refresh runs
   bool shouldUpdate = true;

   if(InpUpdateOnNewBarOnly)
     {
      datetime currentBarTime = time[rates_total - 1];
      shouldUpdate = (prev_calculated == 0 || currentBarTime != g_LastBarTime);
      g_LastBarTime = currentBarTime;
     }

   if(shouldUpdate)
      RecalculateAndUpdatePanel();

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Pulls the current + historical ranges on InpRangePeriod, computes|
//| the percentile rank, and refreshes every panel object            |
//+------------------------------------------------------------------+
void RecalculateAndUpdatePanel()
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int needed = InpLookbackPeriods + 1; // +1 for the current, still-forming period
   int copied = CopyRates(_Symbol, InpRangePeriod, 0, needed, rates);

   if(copied < 10)
      return; // not enough history loaded yet for this timeframe

   int histCount = copied - 1; // everything except rates[0], the current period
   double currentRange = rates[0].high - rates[0].low;

   int countBelowOrEqual = 0;
   for(int i = 1; i < copied; i++)
     {
      double histRange = rates[i].high - rates[i].low;
      if(histRange <= currentRange)
         countBelowOrEqual++;
     }

   double percentile = (histCount > 0) ? (double)countBelowOrEqual / histCount * 100.0 : 50.0;

   string status;
   color statusColor;

   if(percentile <= InpCompressionPercentile)
     {
      status = "COMPRESSED";
      statusColor = InpCompressedColor;
     }
   else
      if(percentile >= InpExpansionPercentile)
        {
         status = "EXPANDED";
         statusColor = InpExpandedColor;
        }
      else
        {
         status = "NORMAL";
         statusColor = InpNormalColor;
        }

   long rangePoints = (_Point > 0) ? (long)MathRound(currentRange / _Point) : 0;

//--- build each row as its own array entry — one item per line, matching
//--- the panel's fixed per-row label objects
   string lines[5];
   lines[0] = "RANGE COMPRESSION";
   lines[1] = "Period: " + PeriodToString(InpRangePeriod);
   lines[2] = "Range: " + IntegerToString((int)rangePoints) + " pts (so far)";
   lines[3] = "Percentile: " + DoubleToString(percentile, 1) + "%";
   lines[4] = "Status: " + status;

   int maxWidthPx = 0;
   for(int i = 0; i < 5; i++)
     {
      color rowColor = (i == 4) ? statusColor : InpPanelTextColor;
      ObjectSetString(0, g_LineNames[i], OBJPROP_TEXT, lines[i]);
      ObjectSetInteger(0, g_LineNames[i], OBJPROP_COLOR, rowColor);

      int w = EstimateTextWidthPx(lines[i]);
      if(w > maxWidthPx)
         maxWidthPx = w;
     }

   int gaugeBlockWidth = InpGaugeWidth + g_PanelPadSide * 2;
   int panelWidth  = MathMax(gaugeBlockWidth, maxWidthPx + g_PanelPadSide * 2);
   int panelHeight = 5 * g_LineHeight + InpGaugeHeight + g_PanelPadTop * 3;

   ObjectSetInteger(0, g_PanelBgName, OBJPROP_XSIZE, panelWidth);
   ObjectSetInteger(0, g_PanelBgName, OBJPROP_YSIZE, panelHeight);

//--- position the gauge track just below the five text rows
   int gaugeY = InpPanelYDistance + 5 * g_LineHeight + g_PanelPadTop;
   ObjectSetInteger(0, g_GaugeTrackName, OBJPROP_YDISTANCE, gaugeY);
   ObjectSetInteger(0, g_GaugeTrackName, OBJPROP_XSIZE, InpGaugeWidth);
   ObjectSetInteger(0, g_GaugeTrackName, OBJPROP_YSIZE, InpGaugeHeight);

//--- the marker's horizontal position along the track represents the
//--- percentile itself (0% = far left, 100% = far right)
   int markerX = InpPanelXDistance + (int)MathRound((percentile / 100.0) * (InpGaugeWidth - 4));
   ObjectSetInteger(0, g_GaugeMarkerName, OBJPROP_XDISTANCE, markerX);
   ObjectSetInteger(0, g_GaugeMarkerName, OBJPROP_YDISTANCE, gaugeY - 2);
   ObjectSetInteger(0, g_GaugeMarkerName, OBJPROP_YSIZE, InpGaugeHeight + 4);
   ObjectSetInteger(0, g_GaugeMarkerName, OBJPROP_BGCOLOR, statusColor);

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Creates the background rectangle, the five text rows, and the    |
//| gauge track/marker — all created once and reused every refresh   |
//+------------------------------------------------------------------+
void CreatePanel()
  {
   if(ObjectFind(0, g_PanelBgName) < 0)
     {
      ObjectCreate(0, g_PanelBgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, g_PanelBgName, OBJPROP_CORNER, InpPanelCorner);
      ObjectSetInteger(0, g_PanelBgName, OBJPROP_XDISTANCE, InpPanelXDistance - g_PanelPadSide);
      ObjectSetInteger(0, g_PanelBgName, OBJPROP_YDISTANCE, InpPanelYDistance - g_PanelPadTop);
      ObjectSetInteger(0, g_PanelBgName, OBJPROP_XSIZE, InpGaugeWidth + g_PanelPadSide * 2);
      ObjectSetInteger(0, g_PanelBgName, OBJPROP_YSIZE, 5 * g_LineHeight + InpGaugeHeight + g_PanelPadTop * 3);
      ObjectSetInteger(0, g_PanelBgName, OBJPROP_BGCOLOR, InpPanelBgColor);
      ObjectSetInteger(0, g_PanelBgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, g_PanelBgName, OBJPROP_COLOR, clrDimGray);
      ObjectSetInteger(0, g_PanelBgName, OBJPROP_BACK, false);
      ObjectSetInteger(0, g_PanelBgName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, g_PanelBgName, OBJPROP_HIDDEN, true);
     }

   for(int i = 0; i < 5; i++)
     {
      string lineName = g_LineNames[i];
      int rowY = InpPanelYDistance + i * g_LineHeight;

      if(ObjectFind(0, lineName) < 0)
         ObjectCreate(0, lineName, OBJ_LABEL, 0, 0, 0);

      ObjectSetInteger(0, lineName, OBJPROP_CORNER, InpPanelCorner);
      ObjectSetInteger(0, lineName, OBJPROP_XDISTANCE, InpPanelXDistance);
      ObjectSetInteger(0, lineName, OBJPROP_YDISTANCE, rowY);
      ObjectSetInteger(0, lineName, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetString(0, lineName, OBJPROP_FONT, (i == 0) ? "Consolas Bold" : "Consolas");
      ObjectSetInteger(0, lineName, OBJPROP_COLOR, InpPanelTextColor);
      ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, lineName, OBJPROP_HIDDEN, true);
      ObjectSetString(0, lineName, OBJPROP_TEXT, "");
     }

//--- gauge track: a static background bar spanning the full 0-100 scale
   if(ObjectFind(0, g_GaugeTrackName) < 0)
     {
      ObjectCreate(0, g_GaugeTrackName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, g_GaugeTrackName, OBJPROP_CORNER, InpPanelCorner);
      ObjectSetInteger(0, g_GaugeTrackName, OBJPROP_XDISTANCE, InpPanelXDistance);
      ObjectSetInteger(0, g_GaugeTrackName, OBJPROP_BGCOLOR, clrGray);
      ObjectSetInteger(0, g_GaugeTrackName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, g_GaugeTrackName, OBJPROP_COLOR, clrDimGray);
      ObjectSetInteger(0, g_GaugeTrackName, OBJPROP_BACK, false);
      ObjectSetInteger(0, g_GaugeTrackName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, g_GaugeTrackName, OBJPROP_HIDDEN, true);
     }

//--- gauge marker: a thin vertical block that slides along the track to
//--- the current percentile position
   if(ObjectFind(0, g_GaugeMarkerName) < 0)
     {
      ObjectCreate(0, g_GaugeMarkerName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, g_GaugeMarkerName, OBJPROP_CORNER, InpPanelCorner);
      ObjectSetInteger(0, g_GaugeMarkerName, OBJPROP_XSIZE, 4);
      ObjectSetInteger(0, g_GaugeMarkerName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, g_GaugeMarkerName, OBJPROP_COLOR, clrBlack);
      ObjectSetInteger(0, g_GaugeMarkerName, OBJPROP_BACK, false);
      ObjectSetInteger(0, g_GaugeMarkerName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, g_GaugeMarkerName, OBJPROP_HIDDEN, true);
     }
  }

//+------------------------------------------------------------------+
//| Rough monospace-font width estimate, in pixels, for a given text |
//+------------------------------------------------------------------+
int EstimateTextWidthPx(const string text)
  {
   return (int)MathRound(StringLen(text) * (InpFontSize * 0.62));
  }

//+------------------------------------------------------------------+
//| Returns a short, readable name for a timeframe constant           |
//+------------------------------------------------------------------+
string PeriodToString(const ENUM_TIMEFRAMES tf)
  {
   string full = EnumToString(tf);
   if(StringFind(full, "PERIOD_") == 0)
      return(StringSubstr(full, 7));
   return(full);
  }
//+------------------------------------------------------------------+
