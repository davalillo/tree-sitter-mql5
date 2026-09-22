//+------------------------------------------------------------------+
//|                                         SmartSessionBreakout.mq4 |
//|                                Copyright 2026, Antonios Kokkalis |
//|                           https://www.mql5.com/en/users/palaki06 |
//+------------------------------------------------------------------+
//| Session range breakout with an ATR body-quality filter.           |
//| Signals are confirmed on bar close and do not repaint.            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antonios Kokkalis"
#property link      "https://www.mql5.com/en/users/palaki06"
#property version   "1.10"
#property strict
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_color1 clrLimeGreen  // Buy Signal Arrow
#property indicator_color2 clrRed        // Sell Signal Arrow
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

//+------------------------------------------------------------------+
//| Session & Range Settings                                         |
//+------------------------------------------------------------------+
input string   InpAsianStart    = "00:00";    // Session Start (Broker Server Time HH:MM)
input string   InpAsianEnd      = "08:00";    // Session End (Broker Server Time HH:MM)
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
input color    InpBoxColor      = C'30,50,90';  // Range Box Color
input bool     InpFillBox       = true;         // Fill Range Box
input color    InpUpperLineCol  = clrDodgerBlue;// Upper Line Color
input color    InpLowerLineCol  = clrDeepPink;  // Lower Line Color

//+------------------------------------------------------------------+
//| Dashboard Panel Settings                                         |
//+------------------------------------------------------------------+
input bool     InpShowDash      = true;         // Show On-Screen Dashboard Panel
input ENUM_BASE_CORNER InpCorner= CORNER_RIGHT_UPPER; // Panel Position Corner
input color    InpBgColor       = C'18,24,38';  // Dashboard Background Color
input color    InpTxtColor      = clrWhite;     // Dashboard Text Color
input color    InpAccentColor   = C'0,195,255'; // Dashboard Accent Highlight

//+------------------------------------------------------------------+
//| Notification Settings                                            |
//+------------------------------------------------------------------+
input bool     InpPopupAlert    = true;       // Enable Pop-up Alert
input bool     InpSoundAlert    = true;       // Enable Sound Alert
input bool     InpSendEmail     = false;      // Enable Email Alert
input bool     InpSendPush      = false;      // Enable Push Alert to Mobile

//--- Global Variables
string   g_prefix    = "SSB_";
double   g_pipSize   = 0.0001;
datetime g_lastAlertBar = 0;    // one alert per bar, whatever the mode

int      g_startSec  = 0;       // session start, seconds past midnight
int      g_sessionLen= 0;       // session length in seconds, always > 0

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
//--- "HH:MM" -> seconds past midnight, or -1 if it cannot be read.
//--- v1.00 fed the raw strings straight into StringToTime(); a typo there
//--- produced an empty chart with nothing explaining why.
int ParseHHMM(string s)
{
   string parts[];
   if(StringSplit(s, StringGetCharacter(":", 0), parts) != 2) return(-1);

   int h = (int)StringToInteger(parts[0]);
   int m = (int)StringToInteger(parts[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59) return(-1);

   return(h * 3600 + m * 60);
}

datetime MidnightOf(datetime t) { return((datetime)(t - (t % 86400))); }

bool IsRightCorner()
{
   return(InpCorner == CORNER_RIGHT_UPPER || InpCorner == CORNER_RIGHT_LOWER);
}

//--- X for a panel element, given the offset of its LEFT edge from the
//--- panel's left side. Labels and rectangle labels are both bound by
//--- their top-left corner and grow to the right, but on a right corner
//--- the distance is measured from the right edge of the chart and grows
//--- leftwards. Without mirroring, v1.00 drew the panel off the screen
//--- entirely on its own default corner.
int PanelX(int panelLeft, int panelWidth, int offsetFromLeft)
{
   return(IsRightCorner() ? (panelLeft + panelWidth - offsetFromLeft)
                          : (panelLeft + offsetFromLeft));
}

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   g_pipSize = (Digits == 3 || Digits == 5) ? Point * 10.0 : Point;

   g_startSec = ParseHHMM(InpAsianStart);
   int endSec = ParseHHMM(InpAsianEnd);
   if(g_startSec < 0 || endSec < 0)
   {
      Print("Smart Session Breakout: session times must be HH:MM in 24h form. Got '",
            InpAsianStart, "' and '", InpAsianEnd, "'.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   // Held as a length rather than an end time. v1.00 rebuilt both ends from
   // the current bar's own date, so a session running across midnight - say
   // 22:00 to 08:00 - never satisfied "bar time is past the session end" and
   // the indicator silently drew nothing at all.
   g_sessionLen = endSec - g_startSec;
   if(g_sessionLen <= 0) g_sessionLen += 86400;

   SetIndexBuffer(0, BufferBuy);
   SetIndexBuffer(1, BufferSell);
   SetIndexBuffer(2, BufferUpperLevel);
   SetIndexBuffer(3, BufferLowerLevel);

   SetIndexStyle(0, DRAW_ARROW, EMPTY, 2, clrLimeGreen);
   SetIndexArrow(0, 233);
   SetIndexLabel(0, "Buy Breakout Signal");

   SetIndexStyle(1, DRAW_ARROW, EMPTY, 2, clrRed);
   SetIndexArrow(1, 234);
   SetIndexLabel(1, "Sell Breakout Signal");

   SetIndexStyle(2, DRAW_LINE, STYLE_SOLID, 1, InpUpperLineCol);
   SetIndexLabel(2, "Session Resistance Level");

   SetIndexStyle(3, DRAW_LINE, STYLE_SOLID, 1, InpLowerLineCol);
   SetIndexLabel(3, "Session Support Level");

   IndicatorShortName("Smart Session Breakout (" + Symbol() + ")");
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
   if(limit > rates_total) limit = rates_total;

   if(InpMaxDays > 0)
   {
      int maxBars = iBarShift(NULL, 0, TimeCurrent() - InpMaxDays * 86400, false);
      if(maxBars > 0 && limit > maxBars) limit = maxBars;
   }

   // The range changes once per session, not once per bar. v1.00 ran two
   // iBarShift calls plus iHighest and iLowest for every bar in the loop,
   // which on a month of M15 data is a few thousand repeats of the same
   // answer. Caching it costs three variables.
   datetime cachedStart = 0;
   double   cachedHigh  = 0.0;
   double   cachedLow   = 0.0;
   bool     cachedValid = false;

   for(int i = limit - 1; i >= 0; i--)
   {
      BufferBuy[i]        = EMPTY_VALUE;
      BufferSell[i]       = EMPTY_VALUE;
      BufferUpperLevel[i] = EMPTY_VALUE;
      BufferLowerLevel[i] = EMPTY_VALUE;

      datetime barTime = time[i];

      // The most recently completed session at this bar. Stepping back one
      // day when the session has not closed yet is what makes a window that
      // crosses midnight work.
      datetime sessStart = MidnightOf(barTime) + g_startSec;
      datetime sessEnd   = sessStart + g_sessionLen;
      if(barTime < sessEnd)
      {
         sessStart -= 86400;
         sessEnd   -= 86400;
      }
      if(barTime < sessEnd) continue;

      if(sessStart != cachedStart)
      {
         cachedStart = sessStart;
         cachedValid = false;

         int barStart = iBarShift(NULL, 0, sessStart, false);
         int barEnd   = iBarShift(NULL, 0, sessEnd,   false);

         if(barStart > 0 && barEnd >= 0 && barStart > barEnd)
         {
            int count = barStart - barEnd + 1;
            int hiShift = iHighest(NULL, 0, MODE_HIGH, count, barEnd);
            int loShift = iLowest (NULL, 0, MODE_LOW,  count, barEnd);

            if(hiShift >= 0 && loShift >= 0)
            {
               double boxHigh = High[hiShift];
               double boxLow  = Low[loShift];
               double boxPips = (boxHigh - boxLow) / g_pipSize;

               if(boxPips >= InpMinBoxPips && boxPips <= InpMaxBoxPips)
               {
                  cachedHigh  = boxHigh;
                  cachedLow   = boxLow;
                  cachedValid = true;
                  DrawSessionBox(sessStart, sessEnd, boxHigh, boxLow);
               }
            }
         }
      }

      if(!cachedValid) continue;

      BufferUpperLevel[i] = cachedHigh;
      BufferLowerLevel[i] = cachedLow;

      // Non-repainting mode judges closed bars only.
      if(InpSignalOnClose && i < 1) continue;

      double atrVal     = iATR(NULL, 0, InpATRPeriod, i);
      double candleBody = MathAbs(close[i] - open[i]);
      bool   atrValid   = (!InpUseATRFilter) || (atrVal > 0.0 && candleBody >= atrVal * InpATRCoeff);
      if(!atrValid) continue;

      bool bull = (open[i] <= cachedHigh && close[i] > cachedHigh);
      bool bear = (open[i] >= cachedLow  && close[i] < cachedLow);
      if(!bull && !bear) continue;

      if(bull) BufferBuy[i]  = low[i]  - 10 * Point;
      else     BufferSell[i] = high[i] + 10 * Point;

      // The alert fires on the newest bar the current mode is allowed to
      // judge, once per bar. v1.00 hard-coded this to i == 1, so with
      // "Confirm Signal on Bar Close" switched off the arrows appeared but
      // no alert was ever sent.
      int alertIdx = InpSignalOnClose ? 1 : 0;
      if(i == alertIdx && time[i] != g_lastAlertBar)
      {
         g_lastAlertBar = time[i];
         TriggerAlert(StringFormat("%s Breakout Signal on %s %s",
                      bull ? "Bullish" : "Bearish", Symbol(), TimeframeStr()));
      }
   }

   if(InpShowDash) UpdateDashboard();

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Draw Session Rectangle Box                                       |
//+------------------------------------------------------------------+
void DrawSessionBox(datetime tStart, datetime tEnd, double highVal, double lowVal)
{
   // Named by the session's own start time. v1.00 combined day-of-month
   // with a date string, which was redundant and made the name harder to
   // match when the box needed moving.
   string boxName = g_prefix + "Box_" + TimeToStr(tStart, TIME_DATE|TIME_MINUTES);

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
//| Dashboard Panel                                                  |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   int x = 15, y = 25, w = 250;

   // A session shorter than a few bars cannot form a range. On a daily
   // chart the whole window falls inside one candle, so the indicator would
   // draw nothing while the panel reported business as usual.
   int barSecs       = Period() * 60;
   int barsInSession = (barSecs > 0) ? g_sessionLen / barSecs : 0;
   bool usable       = (barsInSession >= 4);

   DrawPanelBg(x, y, w, usable ? 165 : 78);

   int lx = PanelX(x, w, 12);

   CreateOrUpdateLabel("T1", "SMART SESSION BREAKOUT", lx, y + 12, InpAccentColor, 9, true);

   if(!usable)
   {
      CreateOrUpdateLabel("T2", StringFormat("Session spans %d bar(s) on %s",
                          barsInSession, TimeframeStr()), lx, y + 32, clrOrange, 8, true);
      CreateOrUpdateLabel("T3", "Use M5 to M30 for an intraday session",
                          lx, y + 50, clrSilver, 8, false);
      for(int d = 4; d <= 7; d++)
         ObjectDelete(0, g_prefix + "Lbl_T" + IntegerToString(d));
      return;
   }

   double curSpread = (double)MarketInfo(Symbol(), MODE_SPREAD) /
                      ((Digits == 3 || Digits == 5) ? 10.0 : 1.0);
   double atrPips   = iATR(NULL, 0, InpATRPeriod, 0) / g_pipSize;

   int remainingSec = (int)(Time[0] + Period() * 60 - TimeCurrent());
   if(remainingSec < 0) remainingSec = 0;

   // Phase is judged against the session running now, with the same
   // midnight-safe arithmetic the calculation loop uses.
   datetime now    = TimeCurrent();
   datetime sStart = MidnightOf(now) + g_startSec;
   if(now < sStart) sStart -= 86400;
   bool inSession = (now >= sStart && now < sStart + g_sessionLen);

   CreateOrUpdateLabel("T2", Symbol() + "  " + TimeframeStr(),
                       lx, y + 32, InpTxtColor, 8, false);
   CreateOrUpdateLabel("T3", inSession ? "Phase: range building"
                                       : "Phase: post-session expansion",
                       lx, y + 50, inSession ? clrOrange : InpAccentColor, 8, false);
   CreateOrUpdateLabel("T4", StringFormat("Spread %.1f pips", curSpread),
                       lx, y + 68, InpTxtColor, 8, false);
   CreateOrUpdateLabel("T5", StringFormat("ATR(%d) %.1f pips", InpATRPeriod, atrPips),
                       lx, y + 86, InpTxtColor, 8, false);
   CreateOrUpdateLabel("T6", StringFormat("Bar closes in %02d:%02d",
                       remainingSec / 60, remainingSec % 60),
                       lx, y + 104, InpAccentColor, 8, true);
   CreateOrUpdateLabel("T7", InpSignalOnClose ? "Signals confirmed on bar close"
                                              : "Signals live - may repaint",
                       lx, y + 126, InpSignalOnClose ? clrLimeGreen : clrOrange, 8, true);
}

//--- Panel background. Resized on every paint so the shortened panel does
//--- not leave an oversized box behind it.
void DrawPanelBg(int x, int y, int w, int h)
{
   string bgObj = g_prefix + "Dash_BG";
   if(ObjectFind(0, bgObj) < 0)
   {
      ObjectCreate(0, bgObj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgObj, OBJPROP_CORNER, InpCorner);
      ObjectSetInteger(0, bgObj, OBJPROP_BGCOLOR, InpBgColor);
      ObjectSetInteger(0, bgObj, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bgObj, OBJPROP_COLOR, InpAccentColor);
      ObjectSetInteger(0, bgObj, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, bgObj, OBJPROP_BACK, false);
      ObjectSetInteger(0, bgObj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bgObj, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, bgObj, OBJPROP_XDISTANCE, PanelX(x, w, 0));
   ObjectSetInteger(0, bgObj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, bgObj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, bgObj, OBJPROP_YSIZE, h);
}

//+------------------------------------------------------------------+
//| Create or update a label                                         |
//+------------------------------------------------------------------+
void CreateOrUpdateLabel(string id, string text, int x, int y,
                         color col, int fontSize=8, bool isBold=false)
{
   string name = g_prefix + "Lbl_" + id;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, InpCorner);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   // Position is refreshed every paint, not only on creation: v1.00 set it
   // once, so a panel that changed height left its rows where they were.
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_FONT, isBold ? "Segoe UI Bold" : "Segoe UI");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
}

string TimeframeStr()
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
   }
   return("TF" + IntegerToString(Period()));
}

//+------------------------------------------------------------------+
//| Multi-Channel Alert Handler                                      |
//+------------------------------------------------------------------+
void TriggerAlert(string msg)
{
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
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, g_prefix) == 0)
         ObjectDelete(0, name);
   }
}
//+------------------------------------------------------------------+
