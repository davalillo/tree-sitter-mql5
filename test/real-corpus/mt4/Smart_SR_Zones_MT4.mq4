//+------------------------------------------------------------------+
//|                                           Smart_SR_Zones_MT4.mq4 |
//|                                Copyright 2026, Antonios Kokkalis |
//|                           https://www.mql5.com/en/users/palaki06 |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property copyright   "Copyright 2026, Antonios Kokkalis"
#property link        "https://www.mql5.com/en/users/palaki06"
#property version     "1.00"
#property description "Smart S/R Zones — swing-pivot support/resistance zones, clustered and ranked"
#property description "by touch count, with optional higher-timeframe context zones."
#property description "Zones are filtered to stay near current price and capped in number to avoid"
#property description "chart clutter. For information purposes only - not financial advice."

//+------------------------------------------------------------------+
//| Inputs                                                             |
//+------------------------------------------------------------------+
input string          _hdr1_               = "";  // ══════ Zone Detection ══════
input int              InpPivotStrength     = 3;    // Swing Strength (bars on each side)
input int              InpLookbackBars      = 300;  // Bars Scanned for Pivots
input double           InpZoneMergeATR      = 0.5;  // Merge Pivots Within (x ATR)
input int              InpMinTouches        = 2;    // Min Touches to Display a Zone

input string          _hdr2_               = "";  // ══════ Relevance Filter ══════
input double           InpMaxZoneDistATR    = 15.0; // Hide Zones Farther Than (x ATR from price)
input int              InpMaxZonesShown     = 6;    // Max Zones Shown (current TF)

input string          _hdr3_               = "";  // ══════ Higher Timeframe Context ══════
input bool             InpShowHTF           = true;         // Show Higher-Timeframe Zones
input ENUM_TIMEFRAMES  InpHTF               = PERIOD_H4;     // Higher Timeframe
input int              InpMaxZonesShownHTF  = 4;    // Max HTF Zones Shown

input string          _hdr4_               = "";  // ══════ Alerts ══════
input bool             InpAlertOnApproach   = true;  // Alert When Price Enters a Zone
input double           InpAlertDistATR      = 0.3;  // Alert Distance (x ATR)
input bool             InpPopupAlert        = true;
input bool             InpSoundAlert        = true;

input string          _hdr5_               = "";  // ══════ Visuals ══════
input color            InpClrSupport        = clrDodgerBlue;
input color            InpClrResistance     = clrOrangeRed;
input color            InpClrHTF            = clrGoldenrod;
input double           InpZoneHalfATR       = 0.35; // Zone Thickness (x ATR, half-width)
input bool             InpShowTouchLabel    = true;

//+------------------------------------------------------------------+
//| Zone storage                                                       |
//+------------------------------------------------------------------+
struct SRZone
{
   double   price;
   int      touches;
   datetime firstTime;
   datetime lastTime;
};

SRZone   g_zonesCur[];
SRZone   g_zonesHtf[];
datetime g_lastBarCur;
datetime g_lastBarHtf;
datetime g_alertCooldown;
string   g_pfx = "SRZ_";

//+------------------------------------------------------------------+
//| Init / Deinit                                                      |
//+------------------------------------------------------------------+
int OnInit()
{
   g_lastBarCur = 0;
   g_lastBarHtf = 0;
   g_alertCooldown = 0;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, g_pfx);
}

//+------------------------------------------------------------------+
//| Swing pivot detection (timeframe-aware)                            |
//+------------------------------------------------------------------+
bool IsSwingHighTF(ENUM_TIMEFRAMES tf, int shift, int strength)
{
   int bars = iBars(NULL, tf);
   if(shift - strength < 0 || shift + strength >= bars) return false;
   double h = iHigh(NULL, tf, shift);
   for(int i = 1; i <= strength; i++)
   {
      if(iHigh(NULL, tf, shift - i) > h) return false;
      if(iHigh(NULL, tf, shift + i) > h) return false;
   }
   return true;
}

bool IsSwingLowTF(ENUM_TIMEFRAMES tf, int shift, int strength)
{
   int bars = iBars(NULL, tf);
   if(shift - strength < 0 || shift + strength >= bars) return false;
   double l = iLow(NULL, tf, shift);
   for(int i = 1; i <= strength; i++)
   {
      if(iLow(NULL, tf, shift - i) < l) return false;
      if(iLow(NULL, tf, shift + i) < l) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Zone clustering                                                    |
//+------------------------------------------------------------------+
//--- Merges a new pivot into an existing zone (running weighted-average
//--- price) if it falls within mergeDist, otherwise starts a new zone.
void AddOrMergeZone(SRZone &zones[], double price, datetime t, double mergeDist)
{
   int n = ArraySize(zones);
   for(int i = 0; i < n; i++)
   {
      if(MathAbs(zones[i].price - price) <= mergeDist)
      {
         zones[i].price   = (zones[i].price * zones[i].touches + price) / (zones[i].touches + 1);
         zones[i].touches++;
         if(zones[i].firstTime == 0 || t < zones[i].firstTime) zones[i].firstTime = t;
         if(t > zones[i].lastTime) zones[i].lastTime = t;
         return;
      }
   }
   ArrayResize(zones, n + 1);
   zones[n].price     = price;
   zones[n].touches   = 1;
   zones[n].firstTime = t;
   zones[n].lastTime  = t;
}

//--- Scans InpLookbackBars pivots on the given timeframe and rebuilds
//--- its zone list from scratch. Only called on a new bar of that TF.
void BuildZones(ENUM_TIMEFRAMES tf, SRZone &zones[])
{
   ArrayResize(zones, 0);
   double atr = iATR(NULL, tf, 14, 1);
   if(atr <= 0) return;
   double mergeDist = InpZoneMergeATR * atr;

   int barsAvail = iBars(NULL, tf);
   int maxShift  = MathMin(InpLookbackBars, barsAvail - InpPivotStrength - 1);

   for(int shift = InpPivotStrength; shift <= maxShift; shift++)
   {
      if(IsSwingHighTF(tf, shift, InpPivotStrength))
         AddOrMergeZone(zones, iHigh(NULL, tf, shift), iTime(NULL, tf, shift), mergeDist);
      if(IsSwingLowTF(tf, shift, InpPivotStrength))
         AddOrMergeZone(zones, iLow(NULL, tf, shift), iTime(NULL, tf, shift), mergeDist);
   }
}

//--- Keeps only zones that are (a) touched enough times and (b) still
//--- close enough to current price to matter, then keeps the strongest
//--- maxShown by touch count. This is the declutter + "stale zone" filter -
//--- simpler and safer than trying to detect a directional "break" event.
void FilterAndRank(SRZone &zones[], double refPrice, double atr, int maxShown)
{
   int n = ArraySize(zones);
   double maxDist = InpMaxZoneDistATR * atr;

   SRZone kept[];
   for(int i = 0; i < n; i++)
   {
      if(zones[i].touches < InpMinTouches) continue;
      if(atr > 0 && MathAbs(zones[i].price - refPrice) > maxDist) continue;
      int k = ArraySize(kept);
      ArrayResize(kept, k + 1);
      kept[k] = zones[i];
   }

   // Selection-sort by touches descending (small N, fine).
   int kn = ArraySize(kept);
   for(int a = 0; a < kn - 1; a++)
   {
      int best = a;
      for(int b = a + 1; b < kn; b++)
         if(kept[b].touches > kept[best].touches) best = b;
      if(best != a)
      {
         SRZone tmp = kept[a]; kept[a] = kept[best]; kept[best] = tmp;
      }
   }

   int finalN = MathMin(kn, maxShown);
   ArrayResize(zones, finalN);
   for(int i = 0; i < finalN; i++) zones[i] = kept[i];
}

//+------------------------------------------------------------------+
//| Drawing                                                             |
//+------------------------------------------------------------------+
void DrawZone(string id, SRZone &z, double half, color clr, bool dashed)
{
   string rectName = g_pfx + "R_" + id;
   string lblName  = g_pfx + "L_" + id;
   if(half <= 0) half = _Point * 10;

   datetime tEnd = TimeCurrent() + PeriodSeconds() * 20;

   if(ObjectFind(0, rectName) < 0)
      ObjectCreate(0, rectName, OBJ_RECTANGLE, 0, z.firstTime, z.price - half, tEnd, z.price + half);
   ObjectSetInteger(0, rectName, OBJPROP_TIME1, z.firstTime);
   ObjectSetDouble(0,  rectName, OBJPROP_PRICE1, z.price - half);
   ObjectSetInteger(0, rectName, OBJPROP_TIME2, tEnd);
   ObjectSetDouble(0,  rectName, OBJPROP_PRICE2, z.price + half);
   ObjectSetInteger(0, rectName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, rectName, OBJPROP_FILL, true);
   ObjectSetInteger(0, rectName, OBJPROP_BACK, true);
   ObjectSetInteger(0, rectName, OBJPROP_STYLE, dashed ? STYLE_DASH : STYLE_SOLID);
   ObjectSetInteger(0, rectName, OBJPROP_SELECTABLE, false);

   if(InpShowTouchLabel)
   {
      if(ObjectFind(0, lblName) < 0) ObjectCreate(0, lblName, OBJ_TEXT, 0, tEnd, z.price);
      ObjectSetInteger(0, lblName, OBJPROP_TIME1, tEnd);
      ObjectSetDouble(0,  lblName, OBJPROP_PRICE1, z.price);
      ObjectSetString(0,  lblName, OBJPROP_TEXT, " x" + IntegerToString(z.touches));
      ObjectSetInteger(0, lblName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, lblName, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, lblName, OBJPROP_SELECTABLE, false);
   }
}

//--- Caps the desired half-width so it can never exceed a safe fraction of
//--- the tightest gap between any two zones actually being shown. Without
//--- this, a fixed ATR-based thickness looks fine on H1/H4 (widely spaced
//--- zones) but merges adjacent zones into one solid blob on lower
//--- timeframes where pivots sit closer together.
double SafeHalfWidth(SRZone &zones[], double desiredHalf)
{
   int n = ArraySize(zones);
   double minGap = -1;
   for(int i = 0; i < n; i++)
      for(int j = i + 1; j < n; j++)
      {
         double gap = MathAbs(zones[i].price - zones[j].price);
         if(minGap < 0 || gap < minGap) minGap = gap;
      }
   if(minGap < 0) return desiredHalf;
   return MathMin(desiredHalf, minGap * 0.4);
}

void RenderZones(SRZone &zones[], double atr, double refPrice, bool isHtf)
{
   string prefix = isHtf ? "H" : "C";
   double desiredHalf = InpZoneHalfATR * atr;
   double half = SafeHalfWidth(zones, desiredHalf);
   for(int i = 0; i < ArraySize(zones); i++)
   {
      color clr = isHtf ? InpClrHTF : (zones[i].price >= refPrice ? InpClrResistance : InpClrSupport);
      DrawZone(prefix + IntegerToString(i), zones[i], half, clr, isHtf);
   }
}

void ClearZoneObjects(string prefix)
{
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
   {
      string name = ObjectName(i);
      if(StringFind(name, g_pfx + "R_" + prefix) == 0 || StringFind(name, g_pfx + "L_" + prefix) == 0)
         ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| Alerts                                                              |
//+------------------------------------------------------------------+
void CheckZoneAlerts(SRZone &zones[], double atr, double refPrice)
{
   if(!InpAlertOnApproach) return;
   if(TimeCurrent() - g_alertCooldown < 60) return;

   double dist = InpAlertDistATR * atr;
   for(int i = 0; i < ArraySize(zones); i++)
   {
      if(MathAbs(zones[i].price - refPrice) <= dist)
      {
         string msg = StringFormat("Smart S/R Zones | %s approaching zone %s (x%d touches)",
                                    Symbol(), DoubleToString(zones[i].price, Digits), zones[i].touches);
         if(InpPopupAlert) Alert(msg);
         if(InpSoundAlert) PlaySound("alert.wav");
         g_alertCooldown = TimeCurrent();
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Main                                                                |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[],
                const double &close[], const long &tick_volume[], const long &volume[], const int &spread[])
{
   double refPrice = Close[0];
   double atrCur   = iATR(NULL, 0, 14, 1);

   // Rebuild current-TF zones only on a new bar - the pivots don't change intrabar.
   datetime curBarTime = Time[0];
   if(curBarTime != g_lastBarCur)
   {
      g_lastBarCur = curBarTime;
      BuildZones(PERIOD_CURRENT, g_zonesCur);
      FilterAndRank(g_zonesCur, refPrice, atrCur, InpMaxZonesShown);
      ClearZoneObjects("C");
      RenderZones(g_zonesCur, atrCur, refPrice, false);
   }

   // If InpHTF isn't actually higher than the chart it's attached to (e.g.
   // default H4 dropped on an H4 chart), the "higher timeframe" layer is
   // just a redundant duplicate of the current-TF zones - skip it instead
   // of drawing two overlapping sets of near-identical lines.
   bool htfIsHigher = (InpHTF > Period());

   if(InpShowHTF && htfIsHigher)
   {
      datetime htfBarTime = iTime(NULL, InpHTF, 0);
      if(htfBarTime != g_lastBarHtf)
      {
         g_lastBarHtf = htfBarTime;
         double atrHtf = iATR(NULL, InpHTF, 14, 1);
         BuildZones(InpHTF, g_zonesHtf);
         FilterAndRank(g_zonesHtf, refPrice, atrHtf, InpMaxZonesShownHTF);
         ClearZoneObjects("H");
         RenderZones(g_zonesHtf, atrHtf, refPrice, true);
      }
   }
   else if(ArraySize(g_zonesHtf) > 0)
   {
      ArrayResize(g_zonesHtf, 0);
      ClearZoneObjects("H");
   }

   CheckZoneAlerts(g_zonesCur, atrCur, refPrice);
   if(InpShowHTF && htfIsHigher) CheckZoneAlerts(g_zonesHtf, atrCur, refPrice);

   return rates_total;
}
//+------------------------------------------------------------------+
