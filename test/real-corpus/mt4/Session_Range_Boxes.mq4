//+------------------------------------------------------------------+
//|                                          Session_Range_Boxes.mq4 |
//|                                     Forexobroker - Dominic Walsh |
//|                                     https://www.forexobroker.com |
//+------------------------------------------------------------------+
#property copyright "Forexobroker - Dominic Walsh"
#property link      "https://www.forexobroker.com"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property description "Draws Asian, London, and New York session range boxes on chart."
#property description "Customize session times, colors, and display options."
#property description ""
#property description "For professional multi-symbol pattern scanning, visit MQL5 Market"
#property description "and search for Dashboard indicators by Dominic Walsh."

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_LINE_STYLE_EXT
{
   LINE_SOLID = STYLE_SOLID,     // Solid
   LINE_DASH  = STYLE_DASH,      // Dash
   LINE_DOT   = STYLE_DOT        // Dot
};

//+------------------------------------------------------------------+
//| Input Parameters - General                                       |
//+------------------------------------------------------------------+
input string InpSep0          = "";            // ─── General Settings ───
input int    InpGmtOffset     = 0;             // GMT Offset (hours)
input int    InpDaysToShow    = 5;             // Number of Days to Show
input bool   InpShowLabels    = true;          // Show Session Labels
input bool   InpShowExtLines  = true;          // Show Range Extension Lines
input ENUM_LINE_STYLE_EXT InpExtLineStyle = LINE_DASH; // Extension Line Style
input int    InpExtLineWidth  = 1;             // Extension Line Width

//+------------------------------------------------------------------+
//| Input Parameters - Asian Session                                 |
//+------------------------------------------------------------------+
input string InpSep1          = "";            // ─── Asian Session ───
input bool   InpAsianEnabled  = true;          // Enable Asian Session
input int    InpAsianStart    = 0;             // Asian Start Hour (GMT)
input int    InpAsianEnd      = 8;             // Asian End Hour (GMT)
input color  InpAsianBoxColor = clrDarkSlateGray; // Asian Box Color
input color  InpAsianLineColor= clrTeal;       // Asian Extension Line Color
input bool   InpAsianFill     = true;          // Asian Box Filled

//+------------------------------------------------------------------+
//| Input Parameters - London Session                                |
//+------------------------------------------------------------------+
input string InpSep2          = "";            // ─── London Session ───
input bool   InpLondonEnabled = true;          // Enable London Session
input int    InpLondonStart   = 8;             // London Start Hour (GMT)
input int    InpLondonEnd     = 16;            // London End Hour (GMT)
input color  InpLondonBoxColor= clrMidnightBlue; // London Box Color
input color  InpLondonLineColor= clrRoyalBlue; // London Extension Line Color
input bool   InpLondonFill    = true;          // London Box Filled

//+------------------------------------------------------------------+
//| Input Parameters - New York Session                              |
//+------------------------------------------------------------------+
input string InpSep3          = "";            // ─── New York Session ───
input bool   InpNewYorkEnabled= true;          // Enable New York Session
input int    InpNewYorkStart  = 13;            // New York Start Hour (GMT)
input int    InpNewYorkEnd    = 21;            // New York End Hour (GMT)
input color  InpNewYorkBoxColor= clrMaroon;    // New York Box Color
input color  InpNewYorkLineColor= clrCrimson;  // New York Extension Line Color
input bool   InpNewYorkFill   = true;          // New York Box Filled

//+------------------------------------------------------------------+
//| Global Constants and Variables                                   |
//+------------------------------------------------------------------+
#define PREFIX "SRB_"              // Unique object name prefix

//--- Session identifiers
#define SESSION_ASIAN   0
#define SESSION_LONDON  1
#define SESSION_NEWYORK 2

//--- Cached chart ID for performance
long g_chartId;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Validate input parameters
   if(InpDaysToShow < 1 || InpDaysToShow > 100)
   {
      Print("Session Range Boxes: Days to show must be between 1 and 100");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(!ValidateSessionHours(InpAsianStart, InpAsianEnd, "Asian"))
      return(INIT_PARAMETERS_INCORRECT);
   if(!ValidateSessionHours(InpLondonStart, InpLondonEnd, "London"))
      return(INIT_PARAMETERS_INCORRECT);
   if(!ValidateSessionHours(InpNewYorkStart, InpNewYorkEnd, "New York"))
      return(INIT_PARAMETERS_INCORRECT);

   //--- Cache chart ID
   g_chartId = ChartID();

   //--- Initial drawing
   DrawAllSessions();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization - clean up all drawn objects                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteAllObjects();
}

//+------------------------------------------------------------------+
//| Main calculation function                                        |
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
   //--- Redraw on first calculation or when new bars appear
   if(prev_calculated == 0 || rates_total != prev_calculated)
   {
      DrawAllSessions();
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Respond to chart events (e.g., scrolling, zooming)               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   //--- Redraw if chart properties change (scroll, zoom, resize)
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      DrawAllSessions();
   }
}

//+------------------------------------------------------------------+
//| Validate session hour inputs                                     |
//+------------------------------------------------------------------+
bool ValidateSessionHours(int startHour, int endHour, string sessionName)
{
   if(startHour < 0 || startHour > 23 || endHour < 0 || endHour > 23)
   {
      PrintFormat("Session Range Boxes: %s session hours must be 0-23", sessionName);
      return(false);
   }
   if(startHour == endHour)
   {
      PrintFormat("Session Range Boxes: %s start and end hours cannot be equal", sessionName);
      return(false);
   }
   return(true);
}

//+------------------------------------------------------------------+
//| Delete all indicator objects from chart                          |
//+------------------------------------------------------------------+
void DeleteAllObjects()
{
   int totalObjects = ObjectsTotal(g_chartId);

   for(int i = totalObjects - 1; i >= 0; i--)
   {
      string objName = ObjectName(g_chartId, i);
      if(StringFind(objName, PREFIX) == 0)
      {
         ObjectDelete(g_chartId, objName);
      }
   }
}

//+------------------------------------------------------------------+
//| Master drawing function - iterates days and draws all sessions   |
//+------------------------------------------------------------------+
void DrawAllSessions()
{
   //--- Delete existing objects to redraw cleanly
   DeleteAllObjects();

   //--- Determine the date range to process
   int totalBars = Bars;
   if(totalBars < 2) return;

   //--- Get server time and calculate the starting date
   datetime currentTime = TimeCurrent();
   MqlDateTime dtCurrent;
   TimeToStruct(currentTime, dtCurrent);

   //--- Process each day
   for(int day = 0; day < InpDaysToShow; day++)
   {
      //--- Calculate the target date (going backwards from today)
      datetime dayStart = StringToTime(TimeToString(currentTime - day * 86400, TIME_DATE));

      //--- Draw each enabled session for this day
      if(InpAsianEnabled)
         DrawSessionBox(SESSION_ASIAN, dayStart, day);

      if(InpLondonEnabled)
         DrawSessionBox(SESSION_LONDON, dayStart, day);

      if(InpNewYorkEnabled)
         DrawSessionBox(SESSION_NEWYORK, dayStart, day);
   }

   ChartRedraw(g_chartId);
}

//+------------------------------------------------------------------+
//| Draw a single session box with extension lines and label         |
//+------------------------------------------------------------------+
void DrawSessionBox(int sessionId, datetime dayDate, int dayIndex)
{
   //--- Get session parameters
   int startHour, endHour;
   color boxColor, lineColor;
   bool filled;
   string sessionName;

   GetSessionParams(sessionId, startHour, endHour, boxColor, lineColor, filled, sessionName);

   //--- Apply GMT offset to convert GMT hours to server time
   //--- ServerTime = GMT + InpGmtOffset means GMT = ServerTime - InpGmtOffset
   //--- So if session starts at GMT startHour, in server time it's startHour + InpGmtOffset
   int adjustedStart = startHour + InpGmtOffset;
   int adjustedEnd   = endHour + InpGmtOffset;

   //--- Calculate session start and end datetimes
   datetime sessionStart, sessionEnd;

   //--- Handle sessions that might wrap across midnight due to GMT offset
   MqlDateTime dtDay;
   TimeToStruct(dayDate, dtDay);
   dtDay.hour = 0;
   dtDay.min  = 0;
   dtDay.sec  = 0;
   datetime baseDayTime = StructToTime(dtDay);

   //--- Handle hour wrapping (negative or > 23)
   int startDayShift = 0;
   int endDayShift   = 0;

   if(adjustedStart < 0)
   {
      adjustedStart += 24;
      startDayShift = -1;
   }
   else if(adjustedStart >= 24)
   {
      adjustedStart -= 24;
      startDayShift = 1;
   }

   if(adjustedEnd < 0)
   {
      adjustedEnd += 24;
      endDayShift = -1;
   }
   else if(adjustedEnd >= 24)
   {
      adjustedEnd -= 24;
      endDayShift = 1;
   }

   sessionStart = baseDayTime + startDayShift * 86400 + adjustedStart * 3600;
   sessionEnd   = baseDayTime + endDayShift * 86400 + adjustedEnd * 3600;

   //--- Ensure session end is after session start
   if(sessionEnd <= sessionStart)
      sessionEnd += 86400;

   //--- Skip if session is in the future (no data yet)
   if(sessionStart > TimeCurrent())
      return;

   //--- Find the bar indices for session boundaries
   int barStart = iBarShift(Symbol(), Period(), sessionStart, false);
   int barEnd   = iBarShift(Symbol(), Period(), sessionEnd, false);

   //--- Validate bar indices
   if(barStart < 0 || barEnd < 0 || barStart >= Bars)
      return;

   //--- Ensure barStart > barEnd (barStart is older = higher index)
   if(barStart < barEnd)
   {
      int temp = barStart;
      barStart = barEnd;
      barEnd   = temp;
   }

   //--- Find session high and low
   double sessionHigh = -DBL_MAX;
   double sessionLow  = DBL_MAX;

   for(int i = barStart; i >= barEnd; i--)
   {
      if(i < 0 || i >= Bars) continue;

      if(High[i] > sessionHigh)
         sessionHigh = High[i];
      if(Low[i] < sessionLow)
         sessionLow = Low[i];
   }

   //--- Validate that we found valid prices
   if(sessionHigh <= -DBL_MAX || sessionLow >= DBL_MAX)
      return;

   //--- Normalize prices
   sessionHigh = NormalizeDouble(sessionHigh, Digits);
   sessionLow  = NormalizeDouble(sessionLow, Digits);

   //--- Get actual bar times for precise positioning
   datetime timeStart = Time[barStart];
   datetime timeEnd   = (barEnd > 0) ? Time[barEnd] : Time[0];

   //--- Clamp session end to current time if session is still active
   if(sessionEnd > TimeCurrent())
      timeEnd = Time[0];

   //--- Generate unique object names
   string suffix = IntegerToString(dayIndex) + "_" + IntegerToString(sessionId);
   string boxName     = PREFIX + "BOX_" + suffix;
   string highLineName = PREFIX + "HLN_" + suffix;
   string lowLineName  = PREFIX + "LLN_" + suffix;
   string labelName    = PREFIX + "LBL_" + suffix;

   //--- Draw the session box (rectangle)
   DrawRectangle(boxName, timeStart, sessionHigh, timeEnd, sessionLow, boxColor, filled);

   //--- Draw extension lines if enabled
   if(InpShowExtLines)
   {
      //--- Extension lines go from session end to the right edge
      datetime extEnd = GetExtensionEndTime(sessionEnd, sessionId, dayIndex);

      if(extEnd > timeEnd)
      {
         DrawExtensionLine(highLineName, timeEnd, sessionHigh, extEnd, sessionHigh, lineColor);
         DrawExtensionLine(lowLineName, timeEnd, sessionLow, extEnd, sessionLow, lineColor);
      }
   }

   //--- Draw session label if enabled
   if(InpShowLabels)
   {
      string labelText = sessionName + " (" +
                         DoubleToString((sessionHigh - sessionLow) / Point, 0) + " pts)";
      DrawLabel(labelName, timeStart, sessionHigh, labelText, boxColor);
   }
}

//+------------------------------------------------------------------+
//| Get session parameters by ID                                     |
//+------------------------------------------------------------------+
void GetSessionParams(int sessionId, int &startHour, int &endHour,
                      color &boxClr, color &lineClr, bool &filled,
                      string &name)
{
   switch(sessionId)
   {
      case SESSION_ASIAN:
         startHour = InpAsianStart;
         endHour   = InpAsianEnd;
         boxClr    = InpAsianBoxColor;
         lineClr   = InpAsianLineColor;
         filled    = InpAsianFill;
         name      = "Asian";
         break;

      case SESSION_LONDON:
         startHour = InpLondonStart;
         endHour   = InpLondonEnd;
         boxClr    = InpLondonBoxColor;
         lineClr   = InpLondonLineColor;
         filled    = InpLondonFill;
         name      = "London";
         break;

      case SESSION_NEWYORK:
         startHour = InpNewYorkStart;
         endHour   = InpNewYorkEnd;
         boxClr    = InpNewYorkBoxColor;
         lineClr   = InpNewYorkLineColor;
         filled    = InpNewYorkFill;
         name      = "New York";
         break;
   }
}

//+------------------------------------------------------------------+
//| Calculate extension line end time                                |
//| Lines extend to the start of the next occurrence of the same     |
//| session, or to the right edge of the chart if none               |
//+------------------------------------------------------------------+
datetime GetExtensionEndTime(datetime sessionEnd, int sessionId, int dayIndex)
{
   //--- Extend to end of current day (midnight next day) or to the
   //--- start of the next session on the following day
   if(dayIndex > 0)
   {
      //--- For past days, extend until next day's session start
      int startHour, endHour;
      color dummyC1, dummyC2;
      bool dummyB;
      string dummyS;

      GetSessionParams(sessionId, startHour, endHour, dummyC1, dummyC2, dummyB, dummyS);

      int adjustedNextStart = startHour + InpGmtOffset;
      if(adjustedNextStart < 0) adjustedNextStart += 24;
      else if(adjustedNextStart >= 24) adjustedNextStart -= 24;

      //--- Next day's session start
      datetime nextSessionStart = sessionEnd + (24 - (endHour - startHour)) * 3600;

      //--- Clamp to not go past current time
      if(nextSessionStart > TimeCurrent())
         nextSessionStart = TimeCurrent();

      return(nextSessionStart);
   }
   else
   {
      //--- For today, extend to current bar (right edge)
      return(Time[0] + Period() * 60);
   }
}

//+------------------------------------------------------------------+
//| Draw a filled or unfilled rectangle on the chart                 |
//+------------------------------------------------------------------+
void DrawRectangle(string name, datetime time1, double price1,
                   datetime time2, double price2,
                   color clr, bool filled)
{
   if(ObjectFind(g_chartId, name) < 0)
   {
      ObjectCreate(g_chartId, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2);
   }
   else
   {
      ObjectSetInteger(g_chartId, name, OBJPROP_TIME, 0, time1);
      ObjectSetDouble(g_chartId, name, OBJPROP_PRICE, 0, price1);
      ObjectSetInteger(g_chartId, name, OBJPROP_TIME, 1, time2);
      ObjectSetDouble(g_chartId, name, OBJPROP_PRICE, 1, price2);
   }

   ObjectSetInteger(g_chartId, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(g_chartId, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(g_chartId, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(g_chartId, name, OBJPROP_FILL, filled);
   ObjectSetInteger(g_chartId, name, OBJPROP_BACK, true);
   ObjectSetInteger(g_chartId, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(g_chartId, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Draw a horizontal extension line (trend line)                    |
//+------------------------------------------------------------------+
void DrawExtensionLine(string name, datetime time1, double price1,
                       datetime time2, double price2,
                       color clr)
{
   if(ObjectFind(g_chartId, name) < 0)
   {
      ObjectCreate(g_chartId, name, OBJ_TREND, 0, time1, price1, time2, price2);
   }
   else
   {
      ObjectSetInteger(g_chartId, name, OBJPROP_TIME, 0, time1);
      ObjectSetDouble(g_chartId, name, OBJPROP_PRICE, 0, price1);
      ObjectSetInteger(g_chartId, name, OBJPROP_TIME, 1, time2);
      ObjectSetDouble(g_chartId, name, OBJPROP_PRICE, 1, price2);
   }

   ObjectSetInteger(g_chartId, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(g_chartId, name, OBJPROP_STYLE, (int)InpExtLineStyle);
   ObjectSetInteger(g_chartId, name, OBJPROP_WIDTH, InpExtLineWidth);
   ObjectSetInteger(g_chartId, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(g_chartId, name, OBJPROP_BACK, false);
   ObjectSetInteger(g_chartId, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(g_chartId, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Draw a text label above the session box                          |
//+------------------------------------------------------------------+
void DrawLabel(string name, datetime time, double price, string text, color clr)
{
   if(ObjectFind(g_chartId, name) < 0)
   {
      ObjectCreate(g_chartId, name, OBJ_TEXT, 0, time, price);
   }
   else
   {
      ObjectSetInteger(g_chartId, name, OBJPROP_TIME, 0, time);
      ObjectSetDouble(g_chartId, name, OBJPROP_PRICE, 0, price);
   }

   ObjectSetString(g_chartId, name, OBJPROP_TEXT, text);
   ObjectSetInteger(g_chartId, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(g_chartId, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(g_chartId, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(g_chartId, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(g_chartId, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(g_chartId, name, OBJPROP_HIDDEN, true);
}
//+------------------------------------------------------------------+
