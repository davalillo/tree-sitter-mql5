//+------------------------------------------------------------------+
//|                                   Fibonacci_Confluence_Zones.mq4 |
//|                                     Forexobroker - Dominic Walsh |
//|                                     https://www.forexobroker.com |
//+------------------------------------------------------------------+
#property copyright "Forexobroker - Dominic Walsh"
#property link      "https://www.forexobroker.com"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property description "Fibonacci Confluence Zones - finds where multiple Fib levels"
#property description "from different swings cluster at the same price. Confluence"
#property description "zones are dramatically stronger than single levels."
#property description ""
#property description "For professional Fibonacci tools, visit MQL5 Market - Dominic Walsh."

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input string   Sep1                    = "";          // === Swing Detection ===
input int      InpSwingLookback        = 10;          // Swing lookback (bars each side)
input int      InpMaxLookbackBars      = 500;         // Max lookback bars for analysis

input string   Sep2                    = "";          // === Fibonacci Levels ===
input bool     InpShow382              = true;        // Show 38.2% level
input bool     InpShow500              = true;        // Show 50.0% level
input bool     InpShow618              = true;        // Show 61.8% level
input bool     InpShow786              = true;        // Show 78.6% level

input string   Sep3                    = "";          // === Clustering ===
input double   InpTolerancePips        = 10.0;        // Cluster tolerance (pips)
input int      InpMinLevelsForCluster  = 2;           // Minimum levels for a cluster
input int      InpMaxZones             = 10;          // Maximum zones displayed

input string   Sep4                    = "";          // === Display ===
input color    InpColor2Level          = clrYellow;   // 2-level confluence color
input color    InpColor3Level          = clrOrange;   // 3-level confluence color
input color    InpColor4Level          = clrRed;      // 4+ level confluence color
input bool     InpShowStrengthLabel    = true;        // Show strength labels
input bool     InpShowIndividualFibs   = false;       // Show individual Fib lines

input string   Sep5                    = "";          // === Alerts ===
input bool     InpAlertStrongZone      = true;        // Alert when price enters strong zone (3+)
input bool     InpPushNotification     = false;       // Push notification

//+------------------------------------------------------------------+
//| Constants                                                         |
//+------------------------------------------------------------------+
#define PREFIX          "FIBC_"
#define MAX_SWINGS      5
#define MAX_FIB_LEVELS  4
#define MAX_RAW_FIBS    100

//+------------------------------------------------------------------+
//| Structures                                                        |
//+------------------------------------------------------------------+
struct SwingPoint
  {
   double         price;         // Swing high or low price
   datetime       time;          // Bar time of the swing
   int            barIndex;      // Bar index of the swing
   bool           isHigh;        // true = swing high, false = swing low
  };

struct FibLevel
  {
   double         price;         // Price of the Fib level
   double         ratio;         // Fib ratio (0.382, 0.5, 0.618, 0.786)
   int            swingPairIdx;  // Index of the swing pair that produced this level
   datetime       earliestTime;  // Time of the earlier swing in the pair
  };

struct ConfluenceZone
  {
   double         centerPrice;   // Center price of the cluster
   double         upperPrice;    // Upper bound of the zone
   double         lowerPrice;    // Lower bound of the zone
   int            strength;      // Number of overlapping Fib levels
   string         levelDesc;     // Description of which levels converge
   datetime       earliestTime;  // Earliest contributing swing time
   string         rectName;      // Rectangle object name
   string         labelName;     // Label object name
  };

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
SwingPoint     g_swings[];
int            g_swingCount     = 0;

FibLevel       g_fibLevels[];
int            g_fibCount       = 0;

ConfluenceZone g_zones[];
int            g_zoneCount      = 0;

datetime       g_lastBarTime    = 0;
double         g_tolerancePrice = 0;   // Tolerance in price units
bool           g_alertedZones[];       // Track which zones have been alerted

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpSwingLookback < 2)
     {
      Alert("Swing lookback must be at least 2");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpMinLevelsForCluster < 2)
     {
      Alert("Minimum levels for cluster must be at least 2");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpMaxZones < 1)
     {
      Alert("Max zones must be at least 1");
      return(INIT_PARAMETERS_INCORRECT);
     }

   // Calculate tolerance in price terms
   double pipSize = GetPipSize();
   g_tolerancePrice = InpTolerancePips * pipSize;

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   CleanupAllObjects();
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
   // Only recalculate on new bars (or first run)
   if(rates_total < InpSwingLookback * 2 + 1)
      return(rates_total);

   datetime currentBarTime = Time[0];

   if(g_lastBarTime == currentBarTime && prev_calculated > 0)
     {
      // No new bar -- just check alerts on current tick
      CheckAlerts();
      return(rates_total);
     }

   g_lastBarTime = currentBarTime;

   // Recalculate tolerance in case symbol changed
   double pipSize = GetPipSize();
   g_tolerancePrice = InpTolerancePips * pipSize;

   // Step 1: Find swing points
   FindSwingPoints();

   if(g_swingCount < 2)
      return(rates_total);

   // Step 2: Calculate all Fib levels from adjacent swing pairs
   CalculateAllFibLevels();

   if(g_fibCount < InpMinLevelsForCluster)
      return(rates_total);

   // Step 3: Find clusters (confluence zones)
   FindConfluenceZones();

   // Step 4: Draw everything
   CleanupAllObjects();
   DrawConfluenceZones();

   if(InpShowIndividualFibs)
      DrawIndividualFibLines();

   // Step 5: Check alerts
   CheckAlerts();

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Get pip size for the current symbol                               |
//+------------------------------------------------------------------+
double GetPipSize()
  {
   double pipSize;
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);

   if(digits == 3 || digits == 5)
      pipSize = Point * 10;
   else
      pipSize = Point;

   return(pipSize);
  }

//+------------------------------------------------------------------+
//| Find significant swing highs and lows                             |
//+------------------------------------------------------------------+
void FindSwingPoints()
  {
   g_swingCount = 0;
   ArrayResize(g_swings, 0);

   int maxBar = MathMin(InpMaxLookbackBars, Bars - InpSwingLookback - 1);
   if(maxBar < InpSwingLookback)
      return;

   // Temporary arrays for all detected swings
   SwingPoint tmpSwings[];
   int tmpCount = 0;

   for(int i = InpSwingLookback; i <= maxBar; i++)
     {
      // Check for swing high
      if(IsSwingHigh(i))
        {
         ArrayResize(tmpSwings, tmpCount + 1);
         tmpSwings[tmpCount].price    = High[i];
         tmpSwings[tmpCount].time     = Time[i];
         tmpSwings[tmpCount].barIndex = i;
         tmpSwings[tmpCount].isHigh   = true;
         tmpCount++;
        }

      // Check for swing low
      if(IsSwingLow(i))
        {
         ArrayResize(tmpSwings, tmpCount + 1);
         tmpSwings[tmpCount].price    = Low[i];
         tmpSwings[tmpCount].time     = Time[i];
         tmpSwings[tmpCount].barIndex = i;
         tmpSwings[tmpCount].isHigh   = false;
         tmpCount++;
        }
     }

   if(tmpCount == 0)
      return;

   // Sort by bar index (most recent first) and take the most significant ones
   // We want alternating highs/lows for clean swing pairs
   SelectSignificantSwings(tmpSwings, tmpCount);
  }

//+------------------------------------------------------------------+
//| Check if bar is a swing high (higher than N bars on each side)    |
//+------------------------------------------------------------------+
bool IsSwingHigh(int bar)
  {
   double highVal = High[bar];

   for(int j = 1; j <= InpSwingLookback; j++)
     {
      if(High[bar - j] >= highVal)
         return(false);
      if(High[bar + j] >= highVal)
         return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Check if bar is a swing low (lower than N bars on each side)      |
//+------------------------------------------------------------------+
bool IsSwingLow(int bar)
  {
   double lowVal = Low[bar];

   for(int j = 1; j <= InpSwingLookback; j++)
     {
      if(Low[bar - j] <= lowVal)
         return(false);
      if(Low[bar + j] <= lowVal)
         return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Select the most significant alternating swings                    |
//+------------------------------------------------------------------+
void SelectSignificantSwings(SwingPoint &allSwings[], int total)
  {
   // Sort by bar index ascending (oldest first)
   SortSwingsByBar(allSwings, total);

   // Build alternating sequence: ensure we alternate H-L-H-L
   // Take the most extreme swing when consecutive same-type swings appear
   SwingPoint alternating[];
   int altCount = 0;

   for(int i = 0; i < total; i++)
     {
      if(altCount == 0)
        {
         ArrayResize(alternating, altCount + 1);
         alternating[altCount] = allSwings[i];
         altCount++;
         continue;
        }

      // If same type as last, keep the more extreme one
      if(allSwings[i].isHigh == alternating[altCount - 1].isHigh)
        {
         if(allSwings[i].isHigh && allSwings[i].price > alternating[altCount - 1].price)
            alternating[altCount - 1] = allSwings[i];
         else if(!allSwings[i].isHigh && allSwings[i].price < alternating[altCount - 1].price)
            alternating[altCount - 1] = allSwings[i];
        }
      else
        {
         // Different type -- add it
         ArrayResize(alternating, altCount + 1);
         alternating[altCount] = allSwings[i];
         altCount++;
        }
     }

   // Take up to MAX_SWINGS most recent swings from the alternating sequence
   int startIdx = MathMax(0, altCount - MAX_SWINGS);
   g_swingCount = altCount - startIdx;
   ArrayResize(g_swings, g_swingCount);

   for(int i = 0; i < g_swingCount; i++)
      g_swings[i] = alternating[startIdx + i];
  }

//+------------------------------------------------------------------+
//| Sort swings by bar index (ascending = oldest first)               |
//+------------------------------------------------------------------+
void SortSwingsByBar(SwingPoint &arr[], int count)
  {
   // Simple insertion sort (small array)
   for(int i = 1; i < count; i++)
     {
      SwingPoint key = arr[i];
      int j = i - 1;

      while(j >= 0 && arr[j].barIndex > key.barIndex)
        {
         arr[j + 1] = arr[j];
         j--;
        }
      arr[j + 1] = key;
     }
  }

//+------------------------------------------------------------------+
//| Calculate Fib levels for all adjacent swing pairs                 |
//+------------------------------------------------------------------+
void CalculateAllFibLevels()
  {
   g_fibCount = 0;
   ArrayResize(g_fibLevels, 0);

   // Fibonacci ratios to use
   double ratios[];
   string ratioNames[];
   int ratioCount = 0;

   if(InpShow382)  { AddRatio(ratios, ratioNames, ratioCount, 0.382, "38.2"); }
   if(InpShow500)  { AddRatio(ratios, ratioNames, ratioCount, 0.500, "50.0"); }
   if(InpShow618)  { AddRatio(ratios, ratioNames, ratioCount, 0.618, "61.8"); }
   if(InpShow786)  { AddRatio(ratios, ratioNames, ratioCount, 0.786, "78.6"); }

   if(ratioCount == 0)
      return;

   // For each pair of adjacent swings, calculate Fib retracement levels
   for(int p = 0; p < g_swingCount - 1; p++)
     {
      double swingHigh, swingLow;
      datetime earlierTime;

      // Determine high and low of the pair
      if(g_swings[p].price > g_swings[p + 1].price)
        {
         swingHigh = g_swings[p].price;
         swingLow  = g_swings[p + 1].price;
        }
      else
        {
         swingHigh = g_swings[p + 1].price;
         swingLow  = g_swings[p].price;
        }

      // Earlier time is the one with the larger bar index (further back)
      earlierTime = (g_swings[p].barIndex > g_swings[p + 1].barIndex)
                    ? g_swings[p].time : g_swings[p + 1].time;

      double range = swingHigh - swingLow;
      if(range < Point)
         continue;   // Skip negligible swings

      // Calculate each Fib level as retracement from the swing
      for(int r = 0; r < ratioCount; r++)
        {
         double fibPrice;

         // If swing goes up (p is low, p+1 is high or vice versa),
         // retracement is from high downward. We calculate both ways:
         // retracement from high: High - range * ratio
         // This gives a price between low and high
         fibPrice = swingHigh - range * ratios[r];

         ArrayResize(g_fibLevels, g_fibCount + 1);
         g_fibLevels[g_fibCount].price        = NormalizeDouble(fibPrice, Digits);
         g_fibLevels[g_fibCount].ratio        = ratios[r];
         g_fibLevels[g_fibCount].swingPairIdx = p;
         g_fibLevels[g_fibCount].earliestTime = earlierTime;
         g_fibCount++;
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper: add a ratio to the working arrays                         |
//+------------------------------------------------------------------+
void AddRatio(double &ratios[], string &names[], int &count,
              double ratio, string name)
  {
   ArrayResize(ratios, count + 1);
   ArrayResize(names, count + 1);
   ratios[count] = ratio;
   names[count]  = name;
   count++;
  }

//+------------------------------------------------------------------+
//| Find confluence zones by clustering nearby Fib levels             |
//+------------------------------------------------------------------+
void FindConfluenceZones()
  {
   g_zoneCount = 0;
   ArrayResize(g_zones, 0);

   if(g_fibCount < InpMinLevelsForCluster)
      return;

   // Sort Fib levels by price ascending
   SortFibsByPrice();

   // Boolean array to mark Fib levels already assigned to a cluster
   bool used[];
   ArrayResize(used, g_fibCount);
   ArrayInitialize(used, false);

   // Scan for clusters: for each unused fib, gather all fibs within tolerance
   for(int i = 0; i < g_fibCount; i++)
     {
      if(used[i])
         continue;

      // Start a new potential cluster anchored on this fib
      double clusterPrices[];
      double clusterRatios[];
      int    clusterPairIdx[];
      datetime clusterTimes[];
      int    clusterSize = 0;

      // Add the anchor
      AddToCluster(clusterPrices, clusterRatios, clusterPairIdx, clusterTimes,
                   clusterSize, g_fibLevels[i]);

      // Scan forward for nearby levels (already sorted by price)
      for(int j = i + 1; j < g_fibCount; j++)
        {
         if(used[j])
            continue;

         // Check if this fib is within tolerance of the cluster center
         double currentCenter = 0;
         for(int k = 0; k < clusterSize; k++)
            currentCenter += clusterPrices[k];
         currentCenter /= clusterSize;

         if(MathAbs(g_fibLevels[j].price - currentCenter) <= g_tolerancePrice)
           {
            // Verify it comes from a DIFFERENT swing pair to be meaningful
            bool fromDifferentPair = false;
            for(int k = 0; k < clusterSize; k++)
              {
               if(clusterPairIdx[k] != g_fibLevels[j].swingPairIdx)
                 {
                  fromDifferentPair = true;
                  break;
                 }
              }

            if(fromDifferentPair)
              {
               AddToCluster(clusterPrices, clusterRatios, clusterPairIdx,
                            clusterTimes, clusterSize, g_fibLevels[j]);
               used[j] = true;
              }
           }
         else
           {
            // Since sorted by price, no more will be within tolerance
            break;
           }
        }

      used[i] = true;

      // Only keep if meeting minimum strength
      if(clusterSize >= InpMinLevelsForCluster)
        {
         // Calculate zone properties
         double centerPrice = 0;
         datetime earliest = TimeCurrent();

         for(int k = 0; k < clusterSize; k++)
           {
            centerPrice += clusterPrices[k];
            if(clusterTimes[k] < earliest)
               earliest = clusterTimes[k];
           }
         centerPrice /= clusterSize;

         // Build description of converging levels
         string desc = BuildClusterDescription(clusterRatios, clusterSize);

         ArrayResize(g_zones, g_zoneCount + 1);
         g_zones[g_zoneCount].centerPrice  = NormalizeDouble(centerPrice, Digits);
         g_zones[g_zoneCount].upperPrice   = NormalizeDouble(centerPrice + g_tolerancePrice / 2.0, Digits);
         g_zones[g_zoneCount].lowerPrice   = NormalizeDouble(centerPrice - g_tolerancePrice / 2.0, Digits);
         g_zones[g_zoneCount].strength     = clusterSize;
         g_zones[g_zoneCount].levelDesc    = desc;
         g_zones[g_zoneCount].earliestTime = earliest;
         g_zones[g_zoneCount].rectName     = "";
         g_zones[g_zoneCount].labelName    = "";
         g_zoneCount++;
        }
     }

   // Sort zones by strength descending, keep top MaxZones
   SortZonesByStrength();

   if(g_zoneCount > InpMaxZones)
      g_zoneCount = InpMaxZones;

   // Reset alert tracking
   ArrayResize(g_alertedZones, g_zoneCount);
   ArrayInitialize(g_alertedZones, false);
  }

//+------------------------------------------------------------------+
//| Add a fib level to a cluster working array                        |
//+------------------------------------------------------------------+
void AddToCluster(double &prices[], double &ratios[], int &pairIdx[],
                  datetime &times[], int &size, const FibLevel &fib)
  {
   ArrayResize(prices,  size + 1);
   ArrayResize(ratios,  size + 1);
   ArrayResize(pairIdx, size + 1);
   ArrayResize(times,   size + 1);

   prices[size]  = fib.price;
   ratios[size]  = fib.ratio;
   pairIdx[size] = fib.swingPairIdx;
   times[size]   = fib.earliestTime;
   size++;
  }

//+------------------------------------------------------------------+
//| Sort Fib levels by price ascending                                |
//+------------------------------------------------------------------+
void SortFibsByPrice()
  {
   // Insertion sort (array is typically < 50 elements)
   for(int i = 1; i < g_fibCount; i++)
     {
      FibLevel key = g_fibLevels[i];
      int j = i - 1;

      while(j >= 0 && g_fibLevels[j].price > key.price)
        {
         g_fibLevels[j + 1] = g_fibLevels[j];
         j--;
        }
      g_fibLevels[j + 1] = key;
     }
  }

//+------------------------------------------------------------------+
//| Sort confluence zones by strength descending                      |
//+------------------------------------------------------------------+
void SortZonesByStrength()
  {
   for(int i = 1; i < g_zoneCount; i++)
     {
      ConfluenceZone key = g_zones[i];
      int j = i - 1;

      while(j >= 0 && g_zones[j].strength < key.strength)
        {
         g_zones[j + 1] = g_zones[j];
         j--;
        }
      g_zones[j + 1] = key;
     }
  }

//+------------------------------------------------------------------+
//| Build description string for a cluster                            |
//+------------------------------------------------------------------+
string BuildClusterDescription(double &ratios[], int count)
  {
   string desc = "";

   // Collect unique ratio names
   string uniqueNames[];
   int uniqueCount = 0;

   for(int i = 0; i < count; i++)
     {
      string ratioName = RatioToString(ratios[i]);
      bool found = false;

      for(int j = 0; j < uniqueCount; j++)
        {
         if(uniqueNames[j] == ratioName)
           {
            found = true;
            break;
           }
        }

      if(!found)
        {
         ArrayResize(uniqueNames, uniqueCount + 1);
         uniqueNames[uniqueCount] = ratioName;
         uniqueCount++;
        }
     }

   // Build string like "38.2+50.0+61.8"
   for(int i = 0; i < uniqueCount; i++)
     {
      if(i > 0)
         desc += "+";
      desc += uniqueNames[i];
     }

   return(desc);
  }

//+------------------------------------------------------------------+
//| Convert ratio to display string                                   |
//+------------------------------------------------------------------+
string RatioToString(double ratio)
  {
   if(MathAbs(ratio - 0.382) < 0.001)  return("38.2");
   if(MathAbs(ratio - 0.500) < 0.001)  return("50.0");
   if(MathAbs(ratio - 0.618) < 0.001)  return("61.8");
   if(MathAbs(ratio - 0.786) < 0.001)  return("78.6");
   return(DoubleToStr(ratio * 100, 1));
  }

//+------------------------------------------------------------------+
//| Clean up all chart objects created by this indicator               |
//+------------------------------------------------------------------+
void CleanupAllObjects()
  {
   int total = ObjectsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(i);
      if(StringFind(name, PREFIX) == 0)
         ObjectDelete(name);
     }
  }

//+------------------------------------------------------------------+
//| Draw all confluence zones on the chart                            |
//+------------------------------------------------------------------+
void DrawConfluenceZones()
  {
   datetime rightEdge = Time[0] + PeriodSeconds() * 20;  // Extend 20 bars right

   for(int i = 0; i < g_zoneCount; i++)
     {
      // Determine color based on strength
      color zoneColor = GetZoneColor(g_zones[i].strength);

      // Create rectangle name
      string rectName = PREFIX + "Zone_" + IntegerToString(i);
      string labelName = PREFIX + "Label_" + IntegerToString(i);

      g_zones[i].rectName  = rectName;
      g_zones[i].labelName = labelName;

      // Draw rectangle zone
      if(ObjectCreate(rectName, OBJ_RECTANGLE, 0,
                      g_zones[i].earliestTime, g_zones[i].upperPrice,
                      rightEdge, g_zones[i].lowerPrice))
        {
         ObjectSetInteger(0, rectName, OBJPROP_COLOR, zoneColor);
         ObjectSetInteger(0, rectName, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, rectName, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, rectName, OBJPROP_BACK, true);
         ObjectSetInteger(0, rectName, OBJPROP_FILL, true);
         ObjectSetInteger(0, rectName, OBJPROP_SELECTABLE, false);
        }

      // Draw strength label
      if(InpShowStrengthLabel)
        {
         string labelText = "FIB x" + IntegerToString(g_zones[i].strength)
                            + " (" + g_zones[i].levelDesc + ") "
                            + DoubleToStr(g_zones[i].centerPrice, Digits);

         if(ObjectCreate(labelName, OBJ_TEXT, 0,
                         rightEdge, g_zones[i].centerPrice))
           {
            ObjectSetString(0, labelName, OBJPROP_TEXT, labelText);
            ObjectSetString(0, labelName, OBJPROP_FONT, "Arial Bold");
            ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
            ObjectSetInteger(0, labelName, OBJPROP_COLOR, zoneColor);
            ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Draw individual Fib level lines (optional)                        |
//+------------------------------------------------------------------+
void DrawIndividualFibLines()
  {
   datetime rightEdge = Time[0] + PeriodSeconds() * 10;

   for(int i = 0; i < g_fibCount; i++)
     {
      string lineName = PREFIX + "Fib_" + IntegerToString(i);

      if(ObjectCreate(lineName, OBJ_TREND, 0,
                      g_fibLevels[i].earliestTime, g_fibLevels[i].price,
                      rightEdge, g_fibLevels[i].price))
        {
         ObjectSetInteger(0, lineName, OBJPROP_COLOR, clrDarkGray);
         ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, lineName, OBJPROP_BACK, true);
         ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);

         string tipText = RatioToString(g_fibLevels[i].ratio) + "% = "
                          + DoubleToStr(g_fibLevels[i].price, Digits);
         ObjectSetString(0, lineName, OBJPROP_TOOLTIP, tipText);
        }
     }
  }

//+------------------------------------------------------------------+
//| Get zone color based on confluence strength                       |
//+------------------------------------------------------------------+
color GetZoneColor(int strength)
  {
   if(strength >= 4)
      return(InpColor4Level);
   if(strength == 3)
      return(InpColor3Level);

   return(InpColor2Level);
  }

//+------------------------------------------------------------------+
//| Check alerts when price enters a strong confluence zone           |
//+------------------------------------------------------------------+
void CheckAlerts()
  {
   if(!InpAlertStrongZone && !InpPushNotification)
      return;

   double bid = Bid;

   for(int i = 0; i < g_zoneCount; i++)
     {
      // Only alert on strong zones (3+ levels)
      if(g_zones[i].strength < 3)
         continue;

      // Check if price is inside the zone
      if(bid >= g_zones[i].lowerPrice && bid <= g_zones[i].upperPrice)
        {
         if(i < ArraySize(g_alertedZones) && !g_alertedZones[i])
           {
            g_alertedZones[i] = true;

            string alertMsg = Symbol() + " " + PeriodToStr()
                              + ": Price entered FIB x"
                              + IntegerToString(g_zones[i].strength)
                              + " confluence zone at "
                              + DoubleToStr(g_zones[i].centerPrice, Digits)
                              + " (" + g_zones[i].levelDesc + ")";

            if(InpAlertStrongZone)
               Alert(alertMsg);

            if(InpPushNotification)
               SendNotification(alertMsg);
           }
        }
      else
        {
         // Price left the zone -- reset alert so it can fire again on re-entry
         if(i < ArraySize(g_alertedZones))
            g_alertedZones[i] = false;
        }
     }
  }

//+------------------------------------------------------------------+
//| Convert period to readable string                                 |
//+------------------------------------------------------------------+
string PeriodToStr()
  {
   switch(Period())
     {
      case PERIOD_M1:  return("M1");
      case PERIOD_M5:  return("M5");
      case PERIOD_M15: return("M15");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H4:  return("H4");
      case PERIOD_D1:  return("D1");
      case PERIOD_W1:  return("W1");
      case PERIOD_MN1: return("MN");
      default:         return("TF" + IntegerToString(Period()));
     }
  }
//+------------------------------------------------------------------+
