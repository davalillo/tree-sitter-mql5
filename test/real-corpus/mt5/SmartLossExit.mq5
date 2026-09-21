//+------------------------------------------------------------------+
//|                                                SmartLossExit.mq5 |
//|                                                           Amul R |
//|                          https://www.mql5.com/en/users/amul1     |
//+------------------------------------------------------------------+
//| Early-exit manager for LOSING positions.                          |
//|                                                                  |
//| Attach to one chart. Works alongside manual trading and other     |
//| Expert Advisors: it only closes positions that are floating in    |
//| loss, it never opens any and it never touches a position that is  |
//| in profit. Every rule is an input and can be switched off.        |
//|                                                                  |
//|  1. ATR adverse excursion: the price has moved against the entry  |
//|     by more than N x ATR.                                         |
//|  2. Time in trade: the position is older than N minutes and still |
//|     losing.                                                       |
//|  3. Trend invalidation: fast EMA crossed the slow EMA against the |
//|     position on a closed bar.                                     |
//|  4. Momentum: RSI on a closed bar is beyond a level against the   |
//|     position.                                                     |
//|  5. Money cap: the floating loss reached a fixed amount.          |
//|  A grace period keeps every rule quiet for the first N minutes.   |
//|  Observe-only mode journals what WOULD be closed and closes       |
//|  nothing, so the rules can be tuned before they are switched on.  |
//|                                                                  |
//| Every exit is written to a CSV journal (MQL5\Files) with the rule |
//| that fired, the age of the trade and its maximum adverse          |
//| excursion, so the rules can be tuned from real data.              |
//+------------------------------------------------------------------+
#property copyright "Amul R"
#property link      "https://www.mql5.com/en/users/amul1"
#property version   "1.00"
#property description "Closes losing positions early: ATR adverse excursion, time in trade, EMA trend invalidation, RSI momentum, money cap. Never touches winners. CSV journal with the exit reason and MAE."
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
//--- inputs: scope
input group "Scope"
input bool             InpThisSymbolOnly =true;              // Only manage this chart's symbol
input long             InpMagic          =0;                 // Magic number to manage (0 = all, -1 = manual only)
input ENUM_TIMEFRAMES  InpTimeframe      =PERIOD_M15;        // Timeframe for ATR / EMA / RSI
input int              InpGraceMinutes   =5;                 // Grace period: no exit before this age (minutes)
input bool             InpObserveOnly    =false;             // Observe only: journal what would be closed, close nothing
//--- inputs: rules
input group "Rule 1 - ATR adverse excursion"
input bool             InpUseAtrExit     =true;              // Enable
input int              InpAtrPeriod      =14;                // ATR period
input double           InpAtrMultiple    =1.5;               // Exit when adverse move > N x ATR
input group "Rule 2 - Time in trade"
input bool             InpUseTimeExit    =true;              // Enable
input int              InpMaxMinutes     =240;               // Exit if still losing after N minutes
input group "Rule 3 - EMA trend invalidation"
input bool             InpUseEmaExit     =true;              // Enable
input int              InpEmaFast        =20;                // Fast EMA period
input int              InpEmaSlow        =50;                // Slow EMA period
input group "Rule 4 - RSI momentum"
input bool             InpUseRsiExit     =false;             // Enable
input int              InpRsiPeriod      =14;                // RSI period
input double           InpRsiBuyExit     =35.0;              // Close a losing BUY when RSI < this
input double           InpRsiSellExit    =65.0;              // Close a losing SELL when RSI > this
input group "Rule 5 - Money cap"
input bool             InpUseMoneyExit   =false;             // Enable
input double           InpMaxLossMoney   =50.0;              // Exit when floating loss > this (account currency)
//--- inputs: journal and display
input group "Journal and display"
input bool             InpJournal        =true;              // Write exits to a CSV journal
input string           InpJournalFile    ="SmartLossExit_journal.csv"; // Journal file (MQL5\Files)
input bool             InpAlerts         =true;              // Pop-up alert on every exit
input bool             InpShowPanel      =true;              // Show panel
input ENUM_BASE_CORNER InpCorner         =CORNER_LEFT_UPPER; // Panel corner
input int              InpFontSize       =10;                // Panel font size
//--- effective rule switches: copies of the inputs so a test harness can flip them
bool   g_use_atr, g_use_time, g_use_ema, g_use_rsi, g_use_money;
double g_atr_mult, g_max_loss;
int    g_max_minutes, g_grace;
//--- per-symbol indicator handles
struct SymbolHandles
  {
   string            symbol;
   int               atr;
   int               ema_fast;
   int               ema_slow;
   int               rsi;
  };
SymbolHandles g_handles[];
//--- per-position maximum adverse excursion (price units)
struct PositionTrack
  {
   ulong             ticket;
   double            mae;
   bool              noted;        // observe-only: "would close" already journaled
  };
PositionTrack g_track[];
//--- globals
CTrade        g_trade;             // trade helper
CPositionInfo g_position;          // position helper
string        g_prefix;            // chart-object name prefix
int           g_exits_today=0;     // exits performed since the last server day change
datetime      g_day=0;             // server date of the exit counter
string        g_last_exit="";      // last exit line for the panel
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_prefix="SLE_"+IntegerToString(ChartID())+"_";
   g_trade.SetAsyncMode(false);
//--- effective switches start as the inputs
   g_use_atr=InpUseAtrExit;
   g_use_time=InpUseTimeExit;
   g_use_ema=InpUseEmaExit;
   g_use_rsi=InpUseRsiExit;
   g_use_money=InpUseMoneyExit;
   g_atr_mult=InpAtrMultiple;
   g_max_loss=InpMaxLossMoney;
   g_max_minutes=InpMaxMinutes;
   g_grace=InpGraceMinutes;
   if(InpEmaFast>=InpEmaSlow)
     {
      Print("Smart Loss Exit: fast EMA must be shorter than slow EMA");
      return(INIT_PARAMETERS_INCORRECT);
     }
   g_day=ServerDate();
//--- this chart's symbol is always prepared; others are added on first sight
   if(HandlesFor(_Symbol)<0)
      return(INIT_FAILED);
   EventSetTimer(1);
   Refresh();
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i=0; i<ArraySize(g_handles); i++)
     {
      IndicatorRelease(g_handles[i].atr);
      IndicatorRelease(g_handles[i].ema_fast);
      IndicatorRelease(g_handles[i].ema_slow);
      IndicatorRelease(g_handles[i].rsi);
     }
   ObjectsDeleteAll(0,g_prefix);
   Comment("");
  }
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   Refresh();
  }
//+------------------------------------------------------------------+
//| Tick function                                                    |
//+------------------------------------------------------------------+
void OnTick()
  {
   Refresh();
  }
//+------------------------------------------------------------------+
//| Server date (midnight) of the current server time                |
//+------------------------------------------------------------------+
datetime ServerDate()
  {
   return((datetime)(TimeCurrent()/86400)*86400);
  }
//+------------------------------------------------------------------+
//| Is a position managed by this instance?                          |
//+------------------------------------------------------------------+
bool InScope(const string symbol,const long magic)
  {
   if(InpThisSymbolOnly && symbol!=_Symbol)
      return(false);
   if(InpMagic>0 && magic!=InpMagic)
      return(false);
   if(InpMagic<0 && magic!=0)
      return(false);
   return(true);
  }
//+------------------------------------------------------------------+
//| Pip size: 10 points on 3/5-digit quotes, 1 point otherwise       |
//+------------------------------------------------------------------+
double PipSize(const string symbol)
  {
   int    digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   if(digits==3 || digits==5)
      return(point*10.0);
   return(point);
  }
//+------------------------------------------------------------------+
//| Index of the handle set for a symbol, creating it on first use   |
//+------------------------------------------------------------------+
int HandlesFor(const string symbol)
  {
   for(int i=0; i<ArraySize(g_handles); i++)
      if(g_handles[i].symbol==symbol)
         return(i);
   SymbolHandles h;
   h.symbol=symbol;
   h.atr=iATR(symbol,InpTimeframe,InpAtrPeriod);
   h.ema_fast=iMA(symbol,InpTimeframe,InpEmaFast,0,MODE_EMA,PRICE_CLOSE);
   h.ema_slow=iMA(symbol,InpTimeframe,InpEmaSlow,0,MODE_EMA,PRICE_CLOSE);
   h.rsi=iRSI(symbol,InpTimeframe,InpRsiPeriod,PRICE_CLOSE);
   if(h.atr==INVALID_HANDLE || h.ema_fast==INVALID_HANDLE || h.ema_slow==INVALID_HANDLE || h.rsi==INVALID_HANDLE)
     {
      PrintFormat("Smart Loss Exit: indicator handle failed for %s (%d)",symbol,GetLastError());
      return(-1);
     }
   int n=ArraySize(g_handles);
   ArrayResize(g_handles,n+1);
   g_handles[n]=h;
   return(n);
  }
//+------------------------------------------------------------------+
//| Value of an indicator buffer on the last CLOSED bar (shift 1)    |
//+------------------------------------------------------------------+
double ClosedBarValue(const int handle)
  {
   double buf[1];
   if(CopyBuffer(handle,0,1,1,buf)!=1)
      return(0);
   return(buf[0]);
  }
//+------------------------------------------------------------------+
//| Tracked maximum adverse excursion for a ticket (price units)     |
//+------------------------------------------------------------------+
double UpdateMae(const ulong ticket,const double adverse)
  {
   int n=ArraySize(g_track);
   for(int i=0; i<n; i++)
      if(g_track[i].ticket==ticket)
        {
         if(adverse>g_track[i].mae)
            g_track[i].mae=adverse;
         return(g_track[i].mae);
        }
   ArrayResize(g_track,n+1);
   g_track[n].ticket=ticket;
   g_track[n].mae=MathMax(0,adverse);
   g_track[n].noted=false;
   return(g_track[n].mae);
  }
//+------------------------------------------------------------------+
//| Observe-only: has this ticket's "would close" been journaled?    |
//| Marks it on the first call and returns false; true afterwards.   |
//+------------------------------------------------------------------+
bool AlreadyNoted(const ulong ticket)
  {
   for(int i=0; i<ArraySize(g_track); i++)
      if(g_track[i].ticket==ticket)
        {
         if(g_track[i].noted)
            return(true);
         g_track[i].noted=true;
         return(false);
        }
   return(false);
  }
//+------------------------------------------------------------------+
//| Forget tickets that are no longer open                           |
//+------------------------------------------------------------------+
void PruneTracks()
  {
   for(int i=ArraySize(g_track)-1; i>=0; i--)
      if(!PositionSelectByTicket(g_track[i].ticket))
        {
         int last=ArraySize(g_track)-1;
         g_track[i]=g_track[last];
         ArrayResize(g_track,last);
        }
  }
//+------------------------------------------------------------------+
//| Log an exit, optionally with a terminal alert                    |
//+------------------------------------------------------------------+
void Notify(const string message)
  {
   Print("Smart Loss Exit: ",message);
   if(InpAlerts)
      Alert("Smart Loss Exit: ",message);
  }
//+------------------------------------------------------------------+
//| Append one exit to the CSV journal                               |
//+------------------------------------------------------------------+
void Journal(const string symbol,const ulong ticket,const string type,const double volume,
             const double open_price,const double close_price,const double profit,
             const int age_minutes,const double mae_pips,const double mae_atr,const string reason)
  {
   if(!InpJournal)
      return;
   bool fresh=!FileIsExist(InpJournalFile);
   int  h=FileOpen(InpJournalFile,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(h==INVALID_HANDLE)
     {
      PrintFormat("Smart Loss Exit: journal open failed (%d)",GetLastError());
      return;
     }
   FileSeek(h,0,SEEK_END);
   if(fresh)
      FileWrite(h,"time","symbol","ticket","type","volume","open","close","profit","age_min","mae_pips","mae_atr","reason");
   FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),symbol,IntegerToString((long)ticket),type,
             DoubleToString(volume,2),DoubleToString(open_price,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS)),
             DoubleToString(close_price,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS)),DoubleToString(profit,2),
             IntegerToString(age_minutes),DoubleToString(mae_pips,1),DoubleToString(mae_atr,2),reason);
   FileClose(h);
  }
//+------------------------------------------------------------------+
//| Decide whether a losing position must be closed; "" = keep       |
//+------------------------------------------------------------------+
string ExitReason(const string symbol,const bool is_buy,const double adverse,const double atr,
                  const int age_minutes,const int hidx)
  {
//--- 1. adverse excursion in ATR units
   if(g_use_atr && atr>0 && adverse>g_atr_mult*atr)
      return(StringFormat("ATR %.2fx > %.2fx",adverse/atr,g_atr_mult));
//--- 2. still losing after the time cap
   if(g_use_time && age_minutes>=g_max_minutes)
      return(StringFormat("TIME %d min >= %d",age_minutes,g_max_minutes));
//--- 3. trend invalidation on the closed bar
   if(g_use_ema)
     {
      double fast=ClosedBarValue(g_handles[hidx].ema_fast);
      double slow=ClosedBarValue(g_handles[hidx].ema_slow);
      if(fast>0 && slow>0 && ((is_buy && fast<slow) || (!is_buy && fast>slow)))
         return(StringFormat("EMA %d %s %d",InpEmaFast,(is_buy ? "<" : ">"),InpEmaSlow));
     }
//--- 4. momentum against the position on the closed bar
   if(g_use_rsi)
     {
      double rsi=ClosedBarValue(g_handles[hidx].rsi);
      if(rsi>0 && ((is_buy && rsi<InpRsiBuyExit) || (!is_buy && rsi>InpRsiSellExit)))
         return(StringFormat("RSI %.1f %s %.1f",rsi,(is_buy ? "<" : ">"),(is_buy ? InpRsiBuyExit : InpRsiSellExit)));
     }
//--- 5. money cap (checked by the caller with the actual P/L)
   return("");
  }
//+------------------------------------------------------------------+
//| Walk every managed position; close the losers that hit a rule    |
//+------------------------------------------------------------------+
void CheckPositions()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(!g_position.SelectByIndex(i))
         continue;
      string symbol=g_position.Symbol();
      if(!InScope(symbol,g_position.Magic()))
         continue;
      ulong  ticket=g_position.Ticket();
      bool   is_buy=(g_position.PositionType()==POSITION_TYPE_BUY);
      double open_price=g_position.PriceOpen();
      double now_price=g_position.PriceCurrent();
      double adverse=(is_buy ? open_price-now_price : now_price-open_price);
      double mae=UpdateMae(ticket,adverse);
      double profit=g_position.Profit()+g_position.Swap()+g_position.Commission();
      //--- winners are never touched
      if(profit>=0)
         continue;
      int age_minutes=(int)((TimeCurrent()-g_position.Time())/60);
      if(age_minutes<g_grace)
         continue;
      int hidx=HandlesFor(symbol);
      if(hidx<0)
         continue;
      double atr=ClosedBarValue(g_handles[hidx].atr);
      string reason=ExitReason(symbol,is_buy,adverse,atr,age_minutes,hidx);
      if(reason=="" && g_use_money && -profit>g_max_loss)
         reason=StringFormat("MONEY %.2f > %.2f",-profit,g_max_loss);
      if(reason=="")
         continue;
      double volume=g_position.Volume();
      double pip=PipSize(symbol);
      double mae_pips=mae/pip;
      double mae_atr=(atr>0 ? mae/atr : 0);
      string type=(is_buy ? "BUY" : "SELL");
      //--- observe only: journal the would-be exit once per ticket, close nothing
      if(InpObserveOnly)
        {
         if(AlreadyNoted(ticket))
            continue;
         Print("Smart Loss Exit: OBSERVE ",StringFormat("%s #%I64u %s %.2f would close at %.2f - %s (%d min, MAE %.1f pips)",
               symbol,ticket,type,volume,profit,reason,age_minutes,mae_pips));
         g_last_exit=StringFormat("(observe) %s %s %.2f  %s",symbol,type,profit,reason);
         Journal(symbol,ticket,type,volume,open_price,now_price,profit,age_minutes,mae_pips,mae_atr,"OBSERVE "+reason);
         continue;
        }
      //--- close and record
      bool ok=g_trade.PositionClose(ticket);
      Notify(StringFormat("%s #%I64u %s %.2f closed at %.2f loss - %s (%d min, MAE %.1f pips) %s",
                          symbol,ticket,type,volume,profit,reason,age_minutes,mae_pips,
                          ok ? "ok" : g_trade.ResultRetcodeDescription()));
      if(ok)
        {
         g_exits_today++;
         g_last_exit=StringFormat("%s %s %.2f  %s",symbol,type,profit,reason);
         Journal(symbol,ticket,type,volume,open_price,now_price,profit,age_minutes,mae_pips,mae_atr,reason);
        }
     }
   PruneTracks();
  }
//+------------------------------------------------------------------+
//| Main loop: roll the day counter, check positions, redraw         |
//+------------------------------------------------------------------+
void Refresh()
  {
   if(ServerDate()!=g_day)
     {
      g_day=ServerDate();
      g_exits_today=0;
     }
   CheckPositions();
   if(InpShowPanel)
      DrawPanel();
  }
//+------------------------------------------------------------------+
//| Create or update one panel text line                             |
//+------------------------------------------------------------------+
void PanelLine(const string name,const int line,const string text,const color clr)
  {
   string obj=g_prefix+name;
   if(ObjectFind(0,obj)<0)
     {
      ObjectCreate(0,obj,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,obj,OBJPROP_CORNER,InpCorner);
      ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,InpFontSize);
      ObjectSetString(0,obj,OBJPROP_FONT,"Consolas");
      ObjectSetInteger(0,obj,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,obj,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,obj,OBJPROP_BACK,false);
     }
   ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,14);
   ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,14+line*(InpFontSize+7));
   ObjectSetString(0,obj,OBJPROP_TEXT,text);
   ObjectSetInteger(0,obj,OBJPROP_COLOR,clr);
  }
//+------------------------------------------------------------------+
//| Draw the status panel                                            |
//+------------------------------------------------------------------+
void DrawPanel()
  {
//--- managed positions: count, losers, worst loser in ATR units
   int    managed=0,losing=0;
   double worst_atr=0,worst_profit=0;
   int    hidx=HandlesFor(_Symbol);
   double atr=(hidx>=0 ? ClosedBarValue(g_handles[hidx].atr) : 0);
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(!g_position.SelectByIndex(i) || !InScope(g_position.Symbol(),g_position.Magic()))
         continue;
      managed++;
      double profit=g_position.Profit()+g_position.Swap()+g_position.Commission();
      if(profit>=0)
         continue;
      losing++;
      if(profit<worst_profit)
         worst_profit=profit;
      if(g_position.Symbol()==_Symbol && atr>0)
        {
         bool   is_buy=(g_position.PositionType()==POSITION_TYPE_BUY);
         double adverse=(is_buy ? g_position.PriceOpen()-g_position.PriceCurrent() : g_position.PriceCurrent()-g_position.PriceOpen());
         worst_atr=MathMax(worst_atr,adverse/atr);
        }
     }
   string status=(losing>0 ? "WATCHING" : "IDLE");
   if(InpObserveOnly)
      status+="  (observe only)";
   color  clr=(losing>0 ? clrGold : clrLightGreen);
//--- background plate
   string bg=g_prefix+"bg";
   if(ObjectFind(0,bg)<0)
     {
      ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,bg,OBJPROP_CORNER,InpCorner);
      ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,6);
      ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,6);
      ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,C'12,16,20');
      ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,bg,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,bg,OBJPROP_BACK,false);
     }
//--- text lines
   string rules="";
   if(g_use_atr)   rules+=StringFormat("ATR>%.1fx ",g_atr_mult);
   if(g_use_time)  rules+=StringFormat("TIME>%dm ",g_max_minutes);
   if(g_use_ema)   rules+=StringFormat("EMA%d/%d ",InpEmaFast,InpEmaSlow);
   if(g_use_rsi)   rules+="RSI ";
   if(g_use_money) rules+=StringFormat("MONEY>%.0f ",g_max_loss);
   if(rules=="")   rules="(all rules off)";
   string lines[6];
   lines[0]="SMART LOSS EXIT  "+status;
   lines[1]="Rules   "+rules;
   lines[2]=StringFormat("Managed %d   losing %d   worst %+.2f",managed,losing,worst_profit);
   lines[3]=StringFormat("Worst adverse move   %.2f x ATR(%d)",worst_atr,InpAtrPeriod);
   lines[4]=StringFormat("Exits today   %d",g_exits_today);
   lines[5]="Last   "+(g_last_exit=="" ? "-" : g_last_exit);
//--- size the plate to the widest line
   int max_width=0;
   TextSetFont("Consolas",-InpFontSize*10);
   for(int i=0; i<6; i++)
     {
      uint w=0,h=0;
      TextGetSize(lines[i],w,h);
      if((int)w>max_width)
         max_width=(int)w;
     }
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,max_width+30);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,6*(InpFontSize+7)+16);
   ObjectSetInteger(0,bg,OBJPROP_COLOR,clr);
   PanelLine("l0",0,lines[0],clr);
   PanelLine("l1",1,lines[1],clrWhite);
   PanelLine("l2",2,lines[2],(losing>0 ? clrGold : clrWhite));
   PanelLine("l3",3,lines[3],clrWhite);
   PanelLine("l4",4,lines[4],clrWhite);
   PanelLine("l5",5,lines[5],clrWhite);
   ChartRedraw();
  }
//+------------------------------------------------------------------+
