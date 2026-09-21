//+------------------------------------------------------------------+
//|                                       Breaker_Block_Detector.mq4 |
//|                                     Forexobroker - Dominic Walsh |
//|                                     https://www.forexobroker.com |
//+------------------------------------------------------------------+
#property copyright "Forexobroker - Dominic Walsh"
#property link      "https://www.forexobroker.com"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property description "Detects breaker blocks - failed order blocks that flip polarity."
#property description "Bullish OB broken down becomes bearish breaker and vice versa."
#property description "Tracks mitigation when price returns to the breaker zone."
#property description ""
#property description "For professional Smart Money tools, visit MQL5 Market"
#property description "- products by Dominic Walsh."

//+------------------------------------------------------------------+
//| Enumerations                                                      |
//+------------------------------------------------------------------+
enum ENUM_MITIGATION_MODE
  {
   MITIGATION_REMOVE = 0, // Remove — delete breaker on mitigation
   MITIGATION_FADE   = 1, // Fade — reduce opacity on mitigation
   MITIGATION_KEEP   = 2  // Keep — mark but keep visible
  };

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input string   Sep1              = "";          // === Detection ===
input int      InpSwingStrength  = 5;           // Swing strength (bars each side)
input bool     InpShowBullish    = true;        // Show bullish breakers (support)
input bool     InpShowBearish    = true;        // Show bearish breakers (resistance)

input string   Sep2              = "";          // === Display ===
input color    InpBullColor      = C'0,180,100';   // Bullish breaker color (support)
input color    InpBearColor      = C'180,0,100';   // Bearish breaker color (resistance)
input bool     InpShowLabels     = true;        // Show labels on breakers
input ENUM_MITIGATION_MODE InpMitigationMode = MITIGATION_FADE; // Mitigation handling
input int      InpMaxBreakers    = 20;          // Max breakers displayed
input int      InpLookback       = 500;         // Lookback bars

input string   Sep3              = "";          // === Alerts ===
input bool     InpAlertNewBreaker      = false; // Alert on new breaker
input bool     InpAlertMitigation      = false; // Alert on breaker mitigation
input bool     InpPushNotification     = false; // Push notification

//+------------------------------------------------------------------+
//| Structures                                                        |
//+------------------------------------------------------------------+
struct OrderBlockInfo
  {
   double         upper;         // Upper boundary (max of open/close)
   double         lower;         // Lower boundary (min of open/close)
   datetime       startTime;     // Candle time of the OB
   int            startBar;      // Bar index when detected
   bool           isBullishOB;   // true = bullish OB (bearish candle before up move)
   bool           isBroken;      // Has this OB been broken?
  };

struct BreakerInfo
  {
   double         upper;         // Upper boundary
   double         lower;         // Lower boundary
   datetime       startTime;     // Time origin (from failed OB)
   bool           isBullish;     // true = bullish breaker (support), false = bearish (resistance)
   bool           isMitigated;   // Has price returned to test the zone?
   string         rectName;      // Rectangle object name
   string         labelName;     // Label object name
  };

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
OrderBlockInfo g_orderBlocks[];
BreakerInfo    g_breakers[];
int            g_obCount       = 0;
int            g_brkCount      = 0;
datetime       g_lastBarTime   = 0;
string         g_prefix        = "BRK_";
int            g_uniqueId      = 0;

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpSwingStrength < 1)
     {
      Print("Swing strength must be >= 1");
      return(INIT_PARAMETERS_INCORRECT);
     }

   CleanupObjects();
   ArrayResize(g_orderBlocks, 0);
   ArrayResize(g_breakers, 0);
   g_obCount     = 0;
   g_brkCount    = 0;
   g_lastBarTime = 0;
   g_uniqueId    = 0;

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinitialization                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   CleanupObjects();
  }

//+------------------------------------------------------------------+
//| Main calculation                                                  |
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
   if(rates_total < InpSwingStrength * 2 + 5)
      return(rates_total);

//--- Full recalculation on first run or history change
   if(prev_calculated == 0)
     {
      CleanupObjects();
      ArrayResize(g_orderBlocks, 0);
      ArrayResize(g_breakers, 0);
      g_obCount     = 0;
      g_brkCount    = 0;
      g_lastBarTime = 0;
      g_uniqueId    = 0;

      FullScan(rates_total);
      DrawAllBreakers();
      return(rates_total);
     }

//--- Incremental: process on new bar only
   if(Time[0] != g_lastBarTime)
     {
      g_lastBarTime = Time[0];
      IncrementalUpdate(rates_total);
     }

//--- Check mitigation on every tick (current price)
   CheckMitigationLive();

//--- Extend active breaker rectangles to current time
   ExtendBreakers();

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Full historical scan                                              |
//+------------------------------------------------------------------+
void FullScan(int rates_total)
  {
   int lookback = MathMin(InpLookback, rates_total - InpSwingStrength - 1);
   int startBar = lookback;

//--- Phase 1: Detect swing highs and lows, then find order blocks
   for(int i = startBar; i >= InpSwingStrength + 1; i--)
     {
      //--- Check for swing high at bar i
      if(IsSwingHigh(i))
        {
         //--- Look for bearish OB: last bullish candle before the bearish impulse
         //    that broke below the previous swing low
         //    Actually for BOS-based OB: we need the impulse that broke structure
         //    Swing high identified — look for bearish OB formed before this swing
         int obBar = FindBearishOBCandle(i);
         if(obBar > 0)
            AddOrderBlock(obBar, false); // false = bearish OB (bullish candle before down move)
        }

      //--- Check for swing low at bar i
      if(IsSwingLow(i))
        {
         //--- Look for bullish OB: last bearish candle before the bullish impulse
         int obBar = FindBullishOBCandle(i);
         if(obBar > 0)
            AddOrderBlock(obBar, true); // true = bullish OB (bearish candle before up move)
        }
     }

//--- Phase 2: Check which OBs have been broken (creating breakers)
   for(int i = g_obCount - 1; i >= 0; i--)
     {
      if(!g_orderBlocks[i].isBroken)
         CheckOBBroken(i, rates_total);
     }

//--- Phase 3: Check mitigation of breakers
   for(int i = 0; i < g_brkCount; i++)
     {
      if(!g_breakers[i].isMitigated)
         CheckBreakerMitigatedHistorical(i, rates_total);
     }
  }

//+------------------------------------------------------------------+
//| Incremental update on new bar                                     |
//+------------------------------------------------------------------+
void IncrementalUpdate(int rates_total)
  {
   int checkBar = InpSwingStrength + 1;

   if(checkBar >= rates_total)
      return;

//--- Check for new swing high confirmed at checkBar
   if(IsSwingHigh(checkBar))
     {
      int obBar = FindBearishOBCandle(checkBar);
      if(obBar > 0)
         AddOrderBlock(obBar, false);
     }

//--- Check for new swing low confirmed at checkBar
   if(IsSwingLow(checkBar))
     {
      int obBar = FindBullishOBCandle(checkBar);
      if(obBar > 0)
         AddOrderBlock(obBar, true);
     }

//--- Check if any active OBs just got broken
   for(int i = g_obCount - 1; i >= 0; i--)
     {
      if(!g_orderBlocks[i].isBroken)
        {
         //--- Check bar index 1 (just closed bar)
         if(CheckOBBrokenAtBar(i, 1))
           {
            g_orderBlocks[i].isBroken = true;
            CreateBreaker(i);
           }
        }
     }

//--- Check mitigation of breakers at the just-closed bar
   for(int i = 0; i < g_brkCount; i++)
     {
      if(!g_breakers[i].isMitigated)
        {
         if(CheckBreakerMitigatedAtBar(i, 1))
           {
            MitigateBreaker(i, false);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Check mitigation on live tick                                     |
//+------------------------------------------------------------------+
void CheckMitigationLive()
  {
   double bid = Bid;

   for(int i = 0; i < g_brkCount; i++)
     {
      if(g_breakers[i].isMitigated)
         continue;

      //--- Bullish breaker (support): mitigated when price drops into zone
      //--- Bearish breaker (resistance): mitigated when price rises into zone
      if(bid >= g_breakers[i].lower && bid <= g_breakers[i].upper)
        {
         MitigateBreaker(i, true);
        }
     }
  }

//+------------------------------------------------------------------+
//| Swing detection                                                   |
//+------------------------------------------------------------------+
bool IsSwingHigh(int bar)
  {
   if(bar < InpSwingStrength || bar + InpSwingStrength >= Bars)
      return(false);

   double highVal = High[bar];

   for(int j = 1; j <= InpSwingStrength; j++)
     {
      if(High[bar - j] >= highVal)
         return(false);
      if(High[bar + j] >= highVal)
         return(false);
     }

   return(true);
  }

bool IsSwingLow(int bar)
  {
   if(bar < InpSwingStrength || bar + InpSwingStrength >= Bars)
      return(false);

   double lowVal = Low[bar];

   for(int j = 1; j <= InpSwingStrength; j++)
     {
      if(Low[bar - j] <= lowVal)
         return(false);
      if(Low[bar + j] <= lowVal)
         return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Find the bullish OB candle before a swing low                     |
//| Bullish OB = last bearish candle before the bullish impulse move  |
//| that eventually created the swing low (price reversed up from it) |
//+------------------------------------------------------------------+
int FindBullishOBCandle(int swingLowBar)
  {
   //--- Walk left from the swing low to find the impulse start
   //--- The OB is the last bearish candle before price dropped to the swing low
   //--- Actually: Bullish OB sits below the swing low area.
   //--- It is the last bearish candle in the down-leg leading to the swing low.
   //--- When price reverses up and breaks a prior swing high, the OB is confirmed.

   //--- For simplicity and robustness: find the last bearish candle
   //--- at or just before the swing low (the demand zone origin)
   for(int i = swingLowBar; i <= swingLowBar + InpSwingStrength * 2; i++)
     {
      if(i >= Bars)
         break;

      if(Close[i] < Open[i]) // Bearish candle
        {
         //--- Verify this isn't a duplicate
         if(!IsDuplicateOB(Time[i]))
            return(i);
        }
     }

   return(-1);
  }

//+------------------------------------------------------------------+
//| Find the bearish OB candle before a swing high                    |
//| Bearish OB = last bullish candle before the bearish impulse move  |
//+------------------------------------------------------------------+
int FindBearishOBCandle(int swingHighBar)
  {
   //--- Find the last bullish candle at or just before the swing high
   for(int i = swingHighBar; i <= swingHighBar + InpSwingStrength * 2; i++)
     {
      if(i >= Bars)
         break;

      if(Close[i] > Open[i]) // Bullish candle
        {
         if(!IsDuplicateOB(Time[i]))
            return(i);
        }
     }

   return(-1);
  }

//+------------------------------------------------------------------+
//| Check for duplicate OB at same time                               |
//+------------------------------------------------------------------+
bool IsDuplicateOB(datetime t)
  {
   for(int i = 0; i < g_obCount; i++)
     {
      if(g_orderBlocks[i].startTime == t)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Add order block to tracking array                                 |
//+------------------------------------------------------------------+
void AddOrderBlock(int bar, bool isBullishOB)
  {
   g_obCount++;
   ArrayResize(g_orderBlocks, g_obCount);

   OrderBlockInfo ob;
   ob.upper       = MathMax(Open[bar], Close[bar]);
   ob.lower       = MathMin(Open[bar], Close[bar]);
   ob.startTime   = Time[bar];
   ob.startBar    = bar;
   ob.isBullishOB = isBullishOB;
   ob.isBroken    = false;

   g_orderBlocks[g_obCount - 1] = ob;
  }

//+------------------------------------------------------------------+
//| Check if an OB has been broken across all history                 |
//+------------------------------------------------------------------+
void CheckOBBroken(int obIndex, int rates_total)
  {
   int obBar = iBarShift(Symbol(), Period(), g_orderBlocks[obIndex].startTime, false);
   if(obBar < 0)
      return;

   //--- Scan bars from OB forward (newer bars = smaller index)
   for(int i = obBar - 1; i >= 1; i--)
     {
      if(CheckOBBrokenAtBar(obIndex, i))
        {
         g_orderBlocks[obIndex].isBroken = true;
         CreateBreaker(obIndex);
         break;
        }
     }
  }

//+------------------------------------------------------------------+
//| Check if OB is broken at a specific bar                           |
//+------------------------------------------------------------------+
bool CheckOBBrokenAtBar(int obIndex, int bar)
  {
   if(bar < 0 || bar >= Bars)
      return(false);

   if(g_orderBlocks[obIndex].isBullishOB)
     {
      //--- Bullish OB breaks when price closes BELOW the OB lower
      if(Close[bar] < g_orderBlocks[obIndex].lower)
         return(true);
     }
   else
     {
      //--- Bearish OB breaks when price closes ABOVE the OB upper
      if(Close[bar] > g_orderBlocks[obIndex].upper)
         return(true);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Create a breaker block from a broken OB                           |
//+------------------------------------------------------------------+
void CreateBreaker(int obIndex)
  {
   //--- Polarity flip: bullish OB that failed → bearish breaker
   bool isBullishBreaker = !g_orderBlocks[obIndex].isBullishOB;

   //--- Check if we should show this type
   if(isBullishBreaker && !InpShowBullish)
      return;
   if(!isBullishBreaker && !InpShowBearish)
      return;

   //--- Enforce max breakers limit — remove oldest if needed
   if(g_brkCount >= InpMaxBreakers)
      RemoveOldestBreaker();

   g_uniqueId++;
   string rectName  = g_prefix + "R_" + IntegerToString(g_uniqueId);
   string labelName = g_prefix + "L_" + IntegerToString(g_uniqueId);

   g_brkCount++;
   ArrayResize(g_breakers, g_brkCount);

   BreakerInfo brk;
   brk.upper       = g_orderBlocks[obIndex].upper;
   brk.lower       = g_orderBlocks[obIndex].lower;
   brk.startTime   = g_orderBlocks[obIndex].startTime;
   brk.isBullish   = isBullishBreaker;
   brk.isMitigated = false;
   brk.rectName    = rectName;
   brk.labelName   = labelName;

   g_breakers[g_brkCount - 1] = brk;

   //--- Draw the breaker
   DrawBreaker(g_brkCount - 1);

   //--- Alert
   if(InpAlertNewBreaker)
     {
      string direction = isBullishBreaker ? "BULLISH" : "BEARISH";
      string msg = Symbol() + " " + PeriodToStr() + ": New " + direction + " Breaker Block at "
                   + DoubleToStr(brk.lower, Digits) + " - " + DoubleToStr(brk.upper, Digits);
      Alert(msg);
      if(InpPushNotification)
         SendNotification(msg);
     }
  }

//+------------------------------------------------------------------+
//| Draw a single breaker block                                       |
//+------------------------------------------------------------------+
void DrawBreaker(int index)
  {
   if(index < 0 || index >= g_brkCount)
      return;

   BreakerInfo brk = g_breakers[index];
   color clr = brk.isBullish ? InpBullColor : InpBearColor;

   datetime endTime = Time[0] + PeriodSeconds() * 10;

   //--- Rectangle zone
   if(ObjectFind(0, brk.rectName) < 0)
     {
      ObjectCreate(0, brk.rectName, OBJ_RECTANGLE, 0,
                   brk.startTime, brk.upper,
                   endTime, brk.lower);
     }

   ObjectSetInteger(0, brk.rectName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, brk.rectName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, brk.rectName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, brk.rectName, OBJPROP_FILL, true);
   ObjectSetInteger(0, brk.rectName, OBJPROP_BACK, true);
   ObjectSetInteger(0, brk.rectName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, brk.rectName, OBJPROP_HIDDEN, true);

   //--- Apply transparency for non-mitigated (semi-transparent fill)
   if(!brk.isMitigated)
     {
      //--- MQL4 uses OBJPROP_COLOR for fill; we keep it as-is
      //--- The fill property already provides semi-transparent appearance
     }

   //--- Label
   if(InpShowLabels)
     {
      string labelText = brk.isBullish ? "Bull Breaker" : "Bear Breaker";
      double labelPrice = brk.upper;

      if(ObjectFind(0, brk.labelName) < 0)
        {
         ObjectCreate(0, brk.labelName, OBJ_TEXT, 0,
                      brk.startTime, labelPrice);
        }

      ObjectSetString(0, brk.labelName, OBJPROP_TEXT, labelText);
      ObjectSetInteger(0, brk.labelName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, brk.labelName, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, brk.labelName, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, brk.labelName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, brk.labelName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, brk.labelName, OBJPROP_HIDDEN, true);
     }
  }

//+------------------------------------------------------------------+
//| Draw all breakers (after full scan)                               |
//+------------------------------------------------------------------+
void DrawAllBreakers()
  {
   for(int i = 0; i < g_brkCount; i++)
      DrawBreaker(i);
  }

//+------------------------------------------------------------------+
//| Extend active breaker rectangles to current time                  |
//+------------------------------------------------------------------+
void ExtendBreakers()
  {
   datetime endTime = Time[0] + PeriodSeconds() * 10;

   for(int i = 0; i < g_brkCount; i++)
     {
      if(ObjectFind(0, g_breakers[i].rectName) >= 0)
        {
         ObjectSetInteger(0, g_breakers[i].rectName, OBJPROP_TIME2, (long)endTime);
        }
     }
  }

//+------------------------------------------------------------------+
//| Check breaker mitigation historically                             |
//+------------------------------------------------------------------+
void CheckBreakerMitigatedHistorical(int brkIndex, int rates_total)
  {
   int startBar = iBarShift(Symbol(), Period(), g_breakers[brkIndex].startTime, false);
   if(startBar < 0)
      return;

   for(int i = startBar - 1; i >= 1; i--)
     {
      if(CheckBreakerMitigatedAtBar(brkIndex, i))
        {
         MitigateBreaker(brkIndex, false);
         break;
        }
     }
  }

//+------------------------------------------------------------------+
//| Check if breaker is mitigated at specific bar                     |
//+------------------------------------------------------------------+
bool CheckBreakerMitigatedAtBar(int brkIndex, int bar)
  {
   if(bar < 0 || bar >= Bars)
      return(false);

   double upper = g_breakers[brkIndex].upper;
   double lower = g_breakers[brkIndex].lower;

   //--- Mitigation: price enters the breaker zone
   //--- For bullish breaker (support): low penetrates into zone
   //--- For bearish breaker (resistance): high penetrates into zone
   if(g_breakers[brkIndex].isBullish)
     {
      //--- Price comes down to test bullish breaker (support)
      if(Low[bar] <= upper && Low[bar] >= lower)
         return(true);
      if(Close[bar] >= lower && Close[bar] <= upper)
         return(true);
     }
   else
     {
      //--- Price comes up to test bearish breaker (resistance)
      if(High[bar] >= lower && High[bar] <= upper)
         return(true);
      if(Close[bar] >= lower && Close[bar] <= upper)
         return(true);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Handle breaker mitigation                                         |
//+------------------------------------------------------------------+
void MitigateBreaker(int index, bool isLive)
  {
   if(index < 0 || index >= g_brkCount)
      return;

   if(g_breakers[index].isMitigated)
      return;

   g_breakers[index].isMitigated = true;

   string direction = g_breakers[index].isBullish ? "BULLISH" : "BEARISH";

   switch(InpMitigationMode)
     {
      case MITIGATION_REMOVE:
         //--- Delete the objects entirely
         ObjectDelete(0, g_breakers[index].rectName);
         ObjectDelete(0, g_breakers[index].labelName);
         break;

      case MITIGATION_FADE:
         //--- Change to dotted outline, remove fill
         if(ObjectFind(0, g_breakers[index].rectName) >= 0)
           {
            ObjectSetInteger(0, g_breakers[index].rectName, OBJPROP_FILL, false);
            ObjectSetInteger(0, g_breakers[index].rectName, OBJPROP_STYLE, STYLE_DOT);
            ObjectSetInteger(0, g_breakers[index].rectName, OBJPROP_WIDTH, 1);
           }
         //--- Update label to show mitigated
         if(InpShowLabels && ObjectFind(0, g_breakers[index].labelName) >= 0)
           {
            string txt = g_breakers[index].isBullish ? "Bull Brk [M]" : "Bear Brk [M]";
            ObjectSetString(0, g_breakers[index].labelName, OBJPROP_TEXT, txt);
            ObjectSetInteger(0, g_breakers[index].labelName, OBJPROP_COLOR, clrGray);
           }
         break;

      case MITIGATION_KEEP:
         //--- Just update the label, keep visual the same
         if(InpShowLabels && ObjectFind(0, g_breakers[index].labelName) >= 0)
           {
            string txt = g_breakers[index].isBullish ? "Bull Brk [M]" : "Bear Brk [M]";
            ObjectSetString(0, g_breakers[index].labelName, OBJPROP_TEXT, txt);
           }
         break;
     }

   //--- Alert on mitigation (only for live/new bar events, not historical)
   if(isLive && InpAlertMitigation)
     {
      string msg = Symbol() + " " + PeriodToStr() + ": " + direction + " Breaker MITIGATED at "
                   + DoubleToStr(g_breakers[index].lower, Digits) + " - "
                   + DoubleToStr(g_breakers[index].upper, Digits);
      Alert(msg);
      if(InpPushNotification)
         SendNotification(msg);
     }
  }

//+------------------------------------------------------------------+
//| Remove the oldest breaker to make room                            |
//+------------------------------------------------------------------+
void RemoveOldestBreaker()
  {
   if(g_brkCount <= 0)
      return;

   //--- Delete objects of the oldest breaker (index 0)
   ObjectDelete(0, g_breakers[0].rectName);
   ObjectDelete(0, g_breakers[0].labelName);

   //--- Shift array left
   for(int i = 0; i < g_brkCount - 1; i++)
      g_breakers[i] = g_breakers[i + 1];

   g_brkCount--;
   ArrayResize(g_breakers, g_brkCount);
  }

//+------------------------------------------------------------------+
//| Cleanup all indicator objects                                     |
//+------------------------------------------------------------------+
void CleanupObjects()
  {
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, g_prefix) == 0)
         ObjectDelete(0, name);
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
      case PERIOD_MN1: return("MN1");
      default:         return("M" + IntegerToString(Period()));
     }
  }
//+------------------------------------------------------------------+
