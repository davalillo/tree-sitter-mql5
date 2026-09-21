//+------------------------------------------------------------------+
//|                                         SessionCandleCounter.mq5 |
//|                                                    Timon Krueger |
//|                     https://www.mql5.com/en/users/sg_mephisot    |
//+------------------------------------------------------------------+
#property copyright "Timon Krueger"
#property link "https://www.mql5.com/en/users/sg_mephisot"
#property version "1.00"
#property description "Numbers every candle since the cash open of a chosen exchange session."
#property description "Frankfurt, London, New York and Tokyo anchors are converted from exchange"
#property description "local time to broker server time with automatic daylight saving."
#property description "Display only: the indicator draws text objects, it never places an order."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots 0

//--- session anchor selected by the user
enum ENUM_SC_SESSION
  {
   SC_AUTO=0, // Auto (from symbol name)
   SC_EU=1, // Frankfurt 09:00 local
   SC_UK=2, // London 08:00 local
   SC_US=3, // New York 09:30 local
   SC_TOKYO=4, // Tokyo 09:00 local
   SC_MANUAL=5 // Manual time in server time
  };

input ENUM_SC_SESSION  InpSession          =SC_AUTO;             // Count candles from
input string           InpManualOpen       ="09:00";             // Manual open HH:MM (server time, used by Manual)
input int              InpLabelEvery       =1;                   // Label every N candles (1 labels all)
input int              InpMaxLabels        =500;                 // Maximum labels on the chart
input int              InpDaysBack         =10;                  // Only label the last N calendar days (0 = no limit)
input color            InpLabelColor       =clrDimGray;          // Label colour
input int              InpFontSize         =7;                   // Label font size
input double           InpLabelOffsetPct   =1.5;                 // Label distance below the low in percent of the visible range
input bool             InpShowOpenLine     =true;                // Draw a vertical line at every session open
input color            InpOpenLineColor    =clrSilver;           // Session open line colour
input bool             InpShowInfo         =true;                // Show the info label
input ENUM_BASE_CORNER InpInfoCorner       =CORNER_LEFT_UPPER;   // Info label corner
input int              InpInfoX            =10;                  // Info label X offset in pixels
input int              InpInfoY            =20;                  // Info label Y offset in pixels

//--- object prefix keeps several instances on one chart apart
string   g_prefix="";
datetime g_lastBarTime=0;
int      g_lastFirstVisible=-1;
int      g_lastVisibleBars=-1;

//+------------------------------------------------------------------+
//| Build a UTC datetime from calendar fields                        |
//+------------------------------------------------------------------+
datetime MakeUtc(const int year,const int month,const int day,const int hour,const int minute=0)
  {
   MqlDateTime st;
   ZeroMemory(st);
//--- StructToTime works on plain fields, the value is read as UTC by the callers
   st.year=year;
   st.mon=month;
   st.day=day;
   st.hour=hour;
   st.min=minute;
   return StructToTime(st);
  }

//+------------------------------------------------------------------+
//| Day of the last Sunday in a month                                |
//+------------------------------------------------------------------+
int LastSundayOf(const int year,const int month)
  {
//--- step back one day from the first of the next month
   datetime lastDay=(month==12) ? MakeUtc(year+1,1,1,0)-86400 : MakeUtc(year,month+1,1,0)-86400;
   MqlDateTime st;
   TimeToStruct(lastDay,st);
   return st.day-st.day_of_week;
  }

//+------------------------------------------------------------------+
//| Day of the n-th Sunday in a month                                |
//+------------------------------------------------------------------+
int NthSundayOf(const int year,const int month,const int n)
  {
   MqlDateTime st;
   TimeToStruct(MakeUtc(year,month,1,0),st);
//--- day_of_week of the first day tells how far the first Sunday is away
   return 1+(7-st.day_of_week)%7+7*(n-1);
  }

//+------------------------------------------------------------------+
//| Central European offset to UTC in hours                          |
//+------------------------------------------------------------------+
int EuropeOffsetHours(const datetime utc)
  {
   MqlDateTime st;
   TimeToStruct(utc,st);
//--- summer time runs from the last Sunday of March to the last Sunday of October
   datetime start=MakeUtc(st.year,3,LastSundayOf(st.year,3),1);
   datetime end=MakeUtc(st.year,10,LastSundayOf(st.year,10),1);
   return (utc>=start && utc<end) ? 2 : 1;
  }

//+------------------------------------------------------------------+
//| London offset to UTC in hours                                    |
//+------------------------------------------------------------------+
int LondonOffsetHours(const datetime utc)
  {
//--- London follows the same switching dates as the continent, one hour behind
   return EuropeOffsetHours(utc)-1;
  }

//+------------------------------------------------------------------+
//| New York offset to UTC in hours                                  |
//+------------------------------------------------------------------+
int NewYorkOffsetHours(const datetime utc)
  {
   MqlDateTime st;
   TimeToStruct(utc,st);
//--- daylight saving runs from the second Sunday of March to the first Sunday of November
   datetime start=MakeUtc(st.year,3,NthSundayOf(st.year,3,2),7);
   datetime end=MakeUtc(st.year,11,NthSundayOf(st.year,11,1),6);
   return (utc>=start && utc<end) ? -4 :-5;
  }

//+------------------------------------------------------------------+
//| Broker server offset to UTC in seconds                           |
//+------------------------------------------------------------------+
int ServerOffsetSec()
  {
//--- rounded to half hours, that covers every server time zone in use
   long diff=(long)TimeTradeServer()-(long)TimeGMT();
   return (int)(MathRound((double)diff/1800.0)*1800.0);
  }

//+------------------------------------------------------------------+
//| Session guessed from the symbol name                             |
//+------------------------------------------------------------------+
ENUM_SC_SESSION DetectSession()
  {
   string name=_Symbol;
   StringToUpper(name);

//--- British indices open in London
   if(StringFind(name,"UK100")>=0 || StringFind(name,"FTSE")>=0)
      return SC_UK;

//--- continental European indices open in Frankfurt or at the same minute
   if(StringFind(name,"GER")>=0 || StringFind(name,"DAX")>=0 || StringFind(name,"DE40")>=0 ||
      StringFind(name,"DE30")>=0 || StringFind(name,"FRA40")>=0 || StringFind(name,"CAC")>=0 ||
      StringFind(name,"SPA35")>=0 || StringFind(name,"IBEX")>=0 || StringFind(name,"SWI20")>=0 ||
      StringFind(name,"SMI")>=0 || StringFind(name,"EUSTX")>=0 || StringFind(name,"EU50")>=0 ||
      StringFind(name,"ITA40")>=0 || StringFind(name,"NED25")>=0)
      return SC_EU;

//--- Japanese index first, its name contains no US or EU token
   if(StringFind(name,"JP225")>=0 || StringFind(name,"NIKKEI")>=0 || StringFind(name,"JPN225")>=0)
      return SC_TOKYO;

//--- Russell before the other US tokens, US2000 contains neither US30 nor US100
   if(StringFind(name,"US2000")>=0 || StringFind(name,"RUSSELL")>=0 || StringFind(name,"RUT")>=0 ||
      StringFind(name,"US30")>=0 || StringFind(name,"DJ30")>=0 || StringFind(name,"DOW")>=0 ||
      StringFind(name,"NAS")>=0 || StringFind(name,"US100")>=0 || StringFind(name,"USTEC")>=0 ||
      StringFind(name,"NDX")>=0 || StringFind(name,"US500")>=0 || StringFind(name,"SP500")>=0 ||
      StringFind(name,"SPX")>=0)
      return SC_US;

//--- unknown symbols fall back to Frankfurt, the info label marks the guess
   return SC_EU;
  }

//+------------------------------------------------------------------+
//| Session actually used after the Auto choice is resolved          |
//+------------------------------------------------------------------+
ENUM_SC_SESSION EffectiveSession()
  {
   if(InpSession!=SC_AUTO)
      return InpSession;
   return DetectSession();
  }

//+------------------------------------------------------------------+
//| Exchange local open in minutes and offset for one session        |
//+------------------------------------------------------------------+
void SessionLocalOpen(const ENUM_SC_SESSION session,const datetime dayUtc,int &localMinutes,int &offsetHours)
  {
//--- every anchor is the cash open of the exchange, not the futures open
   switch(session)
     {
      case SC_UK:
         localMinutes=8*60;
         offsetHours=LondonOffsetHours(dayUtc);
         break;
      case SC_US:
         localMinutes=9*60+30;
         offsetHours=NewYorkOffsetHours(dayUtc);
         break;
      case SC_TOKYO:
         localMinutes=9*60;
         offsetHours=9;
         break;
      default:
         localMinutes=9*60;
         offsetHours=EuropeOffsetHours(dayUtc);
         break;
     }
  }

//+------------------------------------------------------------------+
//| Minutes after server midnight of the manual open                 |
//+------------------------------------------------------------------+
int ManualOpenMinutes()
  {
//--- the string is read defensively, a malformed entry falls back to midnight
   int hour=(int)StringToInteger(StringSubstr(InpManualOpen,0,2));
   int minute=(int)StringToInteger(StringSubstr(InpManualOpen,3,2));
   if(hour<0 || hour>23)
      hour=0;
   if(minute<0 || minute>59)
      minute=0;
   return hour*60+minute;
  }

//+------------------------------------------------------------------+
//| Session open in server time on the calendar day of a bar         |
//+------------------------------------------------------------------+
datetime SessionOpenOfDay(const datetime barTime)
  {
   MqlDateTime st;
   TimeToStruct(barTime,st);
   int totalMinutes;

   ENUM_SC_SESSION session=EffectiveSession();
   if(session==SC_MANUAL)
      totalMinutes=ManualOpenMinutes();
   else
     {
      //--- midday avoids the ambiguous hour on the switching weekend
      datetime dayUtc=MakeUtc(st.year,st.mon,st.day,12);
      int localMinutes,offsetHours;
      SessionLocalOpen(session,dayUtc,localMinutes,offsetHours);
      //--- exchange local time to UTC to server time
      totalMinutes=localMinutes-offsetHours*60+ServerOffsetSec()/60;
     }

//--- wrap into the day, a session can start before server midnight
   totalMinutes=((totalMinutes%1440)+1440)%1440;
   st.hour=totalMinutes/60;
   st.min=totalMinutes%60;
   st.sec=0;
   return StructToTime(st);
  }

//+------------------------------------------------------------------+
//| Short name of the session in use                                 |
//+------------------------------------------------------------------+
string SessionName()
  {
   ENUM_SC_SESSION session=EffectiveSession();
   string name;
   switch(session)
     {
      case SC_UK:
         name="London 08:00";
         break;
      case SC_US:
         name="New York 09:30";
         break;
      case SC_TOKYO:
         name="Tokyo 09:00";
         break;
      case SC_MANUAL:
         name="Manual "+InpManualOpen;
         break;
      default:
         name="Frankfurt 09:00";
         break;
     }
//--- a guessed session is marked, the reader should never take it for a setting
   if(InpSession==SC_AUTO)
      name=name+" (auto)";
   return name;
  }

//+------------------------------------------------------------------+
//| Remove every object this instance created                        |
//+------------------------------------------------------------------+
void DeleteOwnObjects()
  {
   ObjectsDeleteAll(0,g_prefix);
  }

//+------------------------------------------------------------------+
//| Write or update the info label in the chart corner               |
//+------------------------------------------------------------------+
void UpdateInfoLabel(const int lastCount,const datetime lastOpen)
  {
   string name=g_prefix+"INFO";
   if(!InpShowInfo)
     {
      ObjectDelete(0,name);
      return;
     }

   if(ObjectFind(0,name)<0)
     {
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_FONT,"Arial");
     }

//--- corner, offsets and colour follow the inputs on every call
   ObjectSetInteger(0,name,OBJPROP_CORNER,InpInfoCorner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,InpInfoX);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,InpInfoY);
   ObjectSetInteger(0,name,OBJPROP_COLOR,InpLabelColor);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,InpFontSize+2);

   string text=SessionName();
   if(lastOpen>0)
      text=text+", open "+TimeToString(lastOpen,TIME_MINUTES)+" server, bar "+IntegerToString(lastCount);
   else
      text=text+", session not started on this chart";
   ObjectSetString(0,name,OBJPROP_TEXT,text);
  }

//+------------------------------------------------------------------+
//| Draw the vertical line of one session open                       |
//+------------------------------------------------------------------+
void DrawOpenLine(const datetime sessionOpen)
  {
   if(!InpShowOpenLine)
      return;

   string name=g_prefix+"OPEN_"+IntegerToString((long)sessionOpen);
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_VLINE,0,sessionOpen,0);
   ObjectSetInteger(0,name,OBJPROP_TIME,sessionOpen);
   ObjectSetInteger(0,name,OBJPROP_COLOR,InpOpenLineColor);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

//+------------------------------------------------------------------+
//| Number the candles of every session in the visible range         |
//+------------------------------------------------------------------+
void DrawCounter()
  {
   DeleteOwnObjects();

   int firstVisible=(int)ChartGetInteger(0,CHART_FIRST_VISIBLE_BAR);
   int visibleBars=(int)ChartGetInteger(0,CHART_VISIBLE_BARS);
   if(firstVisible<=0 || visibleBars<=0)
      return;

//--- labels are created for the visible range only, thousands of objects make scrolling crawl
   int from=firstVisible;
   int to=MathMax(0,firstVisible-visibleBars+1);
   int limit=(InpMaxLabels>0) ? InpMaxLabels : 500;
   if(from-to+1>limit)
      to=from-limit+1;

//--- vertical distance of the label, taken from the visible price range
   double priceMax=ChartGetDouble(0,CHART_PRICE_MAX);
   double priceMin=ChartGetDouble(0,CHART_PRICE_MIN);
   double offset=(priceMax-priceMin)*InpLabelOffsetPct/100.0;
   if(offset<=0.0)
      offset=_Point*10;

   int bars=Bars(_Symbol,PERIOD_CURRENT);
   if(bars<=0)
      return;

//--- optional age limit, counted in calendar days back from the newest bar
   datetime oldestAllowed=0;
   if(InpDaysBack>0)
     {
      datetime newest=iTime(_Symbol,PERIOD_CURRENT,0);
      if(newest>0)
         oldestAllowed=newest-InpDaysBack*86400;
     }

   int step=(InpLabelEvery>0) ? InpLabelEvery : 1;
   datetime cachedOpen=0;
   int cachedOpenBar=-1;
   int lastCount=0;
   datetime lastOpen=0;

   for(int i=from; i>=to; i--)
     {
      datetime barTime=iTime(_Symbol,PERIOD_CURRENT,i);
      if(barTime<=0)
         continue;
      if(oldestAllowed>0 && barTime<oldestAllowed)
         continue;

      datetime sessionOpen=SessionOpenOfDay(barTime);
      //--- bars before the cash open of their own day stay unlabelled
      if(barTime<sessionOpen)
         continue;

      if(sessionOpen!=cachedOpen)
        {
         cachedOpen=sessionOpen;
         int openBar=iBarShift(_Symbol,PERIOD_CURRENT,sessionOpen,false);
         //--- iBarShift returns the bar at or before the open, the first session bar is the next younger one
         if(openBar>=0 && iTime(_Symbol,PERIOD_CURRENT,openBar)<sessionOpen)
            openBar--;
         cachedOpenBar=(openBar>=0 && openBar<bars) ? openBar :-1;
         if(cachedOpenBar>=0)
            DrawOpenLine(sessionOpen);
        }
      if(cachedOpenBar<0 || i>cachedOpenBar)
         continue;

      int number=cachedOpenBar-i+1;
      if(number>lastCount)
        {
         lastCount=number;
         lastOpen=sessionOpen;
        }
      //--- thinning keeps M1 charts readable, the first candle is always labelled
      if(step>1 && number!=1 && number%step!=0)
         continue;

      double low=iLow(_Symbol,PERIOD_CURRENT,i);
      if(low<=0.0)
         continue;

      string name=g_prefix+"NUM_"+IntegerToString(i);
      if(ObjectFind(0,name)<0)
         ObjectCreate(0,name,OBJ_TEXT,0,barTime,low-offset);
      ObjectSetInteger(0,name,OBJPROP_TIME,barTime);
      ObjectSetDouble(0,name,OBJPROP_PRICE,low-offset);
      ObjectSetString(0,name,OBJPROP_TEXT,IntegerToString(number));
      ObjectSetInteger(0,name,OBJPROP_COLOR,InpLabelColor);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,InpFontSize);
      ObjectSetString(0,name,OBJPROP_FONT,"Arial");
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_UPPER);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
     }

//--- the newest visible session drives the info label
   UpdateInfoLabel(lastCount,lastOpen);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- one prefix per chart and timeframe, several instances never fight over objects
   g_prefix="SCC_"+IntegerToString((int)ChartID())+"_";
   IndicatorSetString(INDICATOR_SHORTNAME,"Session Candle Counter ("+SessionName()+")");

   if(InpLabelEvery<1)
      Print("SessionCandleCounter: InpLabelEvery below 1 is treated as 1.");
   if(InpMaxLabels<1)
      Print("SessionCandleCounter: InpMaxLabels below 1 is treated as 500.");

//--- initialization never fails, a bad input is corrected and reported instead
   g_lastBarTime=0;
   return INIT_SUCCEEDED;
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
   if(rates_total<=0)
      return 0;

//--- the drawing is redone on a new bar and on the first call, not on every tick
   datetime currentBar=iTime(_Symbol,PERIOD_CURRENT,0);
   if(prev_calculated==0 || currentBar!=g_lastBarTime)
     {
      g_lastBarTime=currentBar;
      DrawCounter();
     }
   return rates_total;
  }

//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id!=CHARTEVENT_CHART_CHANGE)
      return;

//--- scrolling and zooming change the visible range, the labels follow it
   int firstVisible=(int)ChartGetInteger(0,CHART_FIRST_VISIBLE_BAR);
   int visibleBars=(int)ChartGetInteger(0,CHART_VISIBLE_BARS);
   if(firstVisible==g_lastFirstVisible && visibleBars==g_lastVisibleBars)
      return;

   g_lastFirstVisible=firstVisible;
   g_lastVisibleBars=visibleBars;
   DrawCounter();
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- the chart is left exactly as it was found
   DeleteOwnObjects();
   ChartRedraw(0);
  }
//+------------------------------------------------------------------+
