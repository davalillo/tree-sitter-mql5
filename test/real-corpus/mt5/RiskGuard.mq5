//+------------------------------------------------------------------+
//|                                                    RiskGuard.mq5 |
//|                                                           Amul R |
//|                     https://www.mql5.com/en/users/amulravikumar |
//+------------------------------------------------------------------+
//| Account risk enforcement Expert Advisor.                          |
//|                                                                  |
//| Attach to ONE chart per account. Works alongside manual trading   |
//| and other Expert Advisors: it only reacts to positions, it never  |
//| opens any. Every rule is an input and can be switched off.        |
//|                                                                  |
//|  1. Shows the lot size that matches your risk (percent of balance |
//|     or a fixed amount) for a given stop distance.                 |
//|  2. Daily loss limit: when today's closed + floating P/L reaches  |
//|     the limit, all positions are closed and every new position is |
//|     closed on arrival until the next server day. The lock is kept |
//|     in a terminal global variable, so it survives a restart.      |
//|  3. Maximum number of open positions (newest over the cap closed).|
//|  4. Oversized-trade trim: a new position that risks more than the |
//|     per-trade limit at its stop-loss has the excess volume closed.|
//|  5. A protective stop-loss is added to any position opened        |
//|     without one.                                                  |
//|  6. Spread warning on the panel.                                  |
//+------------------------------------------------------------------+
#property copyright "Amul R"
#property link      "https://www.mql5.com/en/users/amulravikumar"
#property version   "1.00"
#property description "Risk enforcement: risk-based lot size, daily loss lock, max positions, oversized-trade trim, forced stop-loss, spread warning."
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
//--- risk mode
enum ENUM_RISK_MODE
  {
   RISK_PERCENT=0,   // Percent of balance
   RISK_MONEY  =1    // Fixed amount
  };
//--- inputs: position sizing
input group "Position sizing"
input ENUM_RISK_MODE   InpRiskMode       =RISK_PERCENT;      // Risk mode
input double           InpRiskPercent    =1.0;               // Risk % of balance
input double           InpFixedRisk      =50.0;              // Fixed risk (account currency)
input double           InpStopPips       =20.0;              // Stop distance (pips) for the lot calc
//--- inputs: limits
input group "Limits"
input bool             InpUseDailyLimit  =true;              // Enable daily loss limit
input double           InpDailyLossMoney =0.0;               // Daily loss limit (money, 0 = use %)
input double           InpDailyLossPct   =3.0;               // Daily loss limit (% of start-of-day balance)
input bool             InpCloseAllAtLimit=true;              // Close all positions at limit
input int              InpMaxPositions   =3;                 // Max open positions (0 = off)
input double           InpMaxSpreadPips  =3.0;               // Max spread (pips, 0 = off)
//--- inputs: protection
input group "Protection"
input bool             InpForceSL        =true;              // Add SL to positions opened without one
input double           InpForcedSlPips   =30.0;              // Forced SL distance (pips)
input bool             InpTrimOversized  =true;              // Trim positions that risk more than the limit
input bool             InpThisSymbolOnly =false;             // Only guard this chart's symbol
input bool             InpAlerts         =true;              // Pop-up alert on every enforcement
//--- inputs: display
input group "Display"
input bool             InpShowPanel      =true;              // Show panel
input ENUM_BASE_CORNER InpCorner         =CORNER_LEFT_UPPER; // Panel corner
input int              InpFontSize       =10;                // Panel font size
//--- globals
CTrade        g_trade;             // trade helper
CPositionInfo g_position;          // position helper
datetime      g_day=0;             // server date of the current session
double        g_start_balance=0;   // balance at the start of the day
bool          g_locked=false;      // daily limit hit
string        g_prefix;            // chart-object name prefix
string        g_gv_lock;           // global-variable name holding the lock day
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- names for chart objects and the persisted lock
   g_prefix="RG_"+IntegerToString(ChartID())+"_";
   g_gv_lock="RiskGuard_Lock_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   g_trade.SetAsyncMode(false);
//--- start the session and the 1-second timer
   StartNewDay(true);
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
//| Start a new trading day; restore the lock after a restart        |
//+------------------------------------------------------------------+
void StartNewDay(const bool from_init)
  {
   g_day=ServerDate();
   g_start_balance=AccountInfoDouble(ACCOUNT_BALANCE);
   g_locked=false;
//--- a lock stored for today survives a restart
   if(from_init && GlobalVariableCheck(g_gv_lock) && (datetime)GlobalVariableGet(g_gv_lock)==g_day)
     {
      g_locked=true;
      PrintFormat("Risk Guard: restart on a locked day %s - lock kept",TimeToString(g_day,TIME_DATE));
     }
//--- a lock from an earlier day is stale
   else
      if(GlobalVariableCheck(g_gv_lock) && (datetime)GlobalVariableGet(g_gv_lock)!=g_day)
         GlobalVariableDel(g_gv_lock);
   PrintFormat("Risk Guard: new day %s, start balance %.2f",TimeToString(g_day,TIME_DATE),g_start_balance);
  }
//+------------------------------------------------------------------+
//| Roll the session when the server date changes                    |
//+------------------------------------------------------------------+
void RollDayIfNeeded()
  {
   if(ServerDate()!=g_day)
      StartNewDay(false);
  }
//+------------------------------------------------------------------+
//| Money at risk per trade                                          |
//+------------------------------------------------------------------+
double RiskMoney()
  {
   if(InpRiskMode==RISK_PERCENT)
      return(AccountInfoDouble(ACCOUNT_BALANCE)*InpRiskPercent/100.0);
   return(InpFixedRisk);
  }
//+------------------------------------------------------------------+
//| Daily loss limit in account currency                             |
//+------------------------------------------------------------------+
double DailyLimitMoney()
  {
   if(InpDailyLossMoney>0)
      return(InpDailyLossMoney);
   return(g_start_balance*InpDailyLossPct/100.0);
  }
//+------------------------------------------------------------------+
//| Is a symbol guarded by this instance?                            |
//+------------------------------------------------------------------+
bool InScope(const string symbol)
  {
   return(!InpThisSymbolOnly || symbol==_Symbol);
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
//| Money lost per 1.0 lot for a 1-pip adverse move                  |
//+------------------------------------------------------------------+
double PipValuePerLot(const string symbol)
  {
   double tick_value=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick_value<=0)
      tick_value=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
   if(tick_size<=0 || tick_value<=0)
      return(0);
   return(tick_value*(PipSize(symbol)/tick_size));
  }
//+------------------------------------------------------------------+
//| Round a volume down to the symbol's step, inside min..max        |
//+------------------------------------------------------------------+
double NormalizeLots(const string symbol,double lots)
  {
   double vol_min=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double vol_max=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double vol_step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(vol_step<=0)
      vol_step=(vol_min>0 ? vol_min : 0.01);
   lots=MathFloor(lots/vol_step+1e-9)*vol_step;
   lots=MathMax(vol_min,MathMin(vol_max,lots));
   return(NormalizeDouble(lots,8));
  }
//+------------------------------------------------------------------+
//| Lots so that a stop of stop_pips loses exactly RiskMoney()       |
//+------------------------------------------------------------------+
double LotsForRisk(const string symbol,const double stop_pips)
  {
   double pip_value=PipValuePerLot(symbol);
   if(stop_pips<=0 || pip_value<=0)
      return(0);
   return(NormalizeLots(symbol,RiskMoney()/(stop_pips*pip_value)));
  }
//+------------------------------------------------------------------+
//| Current spread in pips                                           |
//+------------------------------------------------------------------+
double SpreadPips(const string symbol)
  {
   return(SymbolInfoInteger(symbol,SYMBOL_SPREAD)*SymbolInfoDouble(symbol,SYMBOL_POINT)/PipSize(symbol));
  }
//+------------------------------------------------------------------+
//| Closed P/L (profit + swap + commission) since server midnight    |
//+------------------------------------------------------------------+
double TodayClosedPnl()
  {
   double sum=0;
   if(!HistorySelect(g_day,TimeCurrent()+60))
      return(0);
//--- only exit deals realise P/L
   int total=HistoryDealsTotal();
   for(int i=0; i<total; i++)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0)
         continue;
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_INOUT && entry!=DEAL_ENTRY_OUT_BY)
         continue;
      if(!InScope(HistoryDealGetString(ticket,DEAL_SYMBOL)))
         continue;
      sum+=HistoryDealGetDouble(ticket,DEAL_PROFIT)+HistoryDealGetDouble(ticket,DEAL_SWAP)+HistoryDealGetDouble(ticket,DEAL_COMMISSION);
     }
   return(sum);
  }
//+------------------------------------------------------------------+
//| Floating P/L of guarded positions                                |
//+------------------------------------------------------------------+
double OpenPnl()
  {
   double sum=0;
   for(int i=PositionsTotal()-1; i>=0; i--)
      if(g_position.SelectByIndex(i) && InScope(g_position.Symbol()))
         sum+=g_position.Profit()+g_position.Swap();
   return(sum);
  }
//+------------------------------------------------------------------+
//| Number of guarded open positions                                 |
//+------------------------------------------------------------------+
int OpenCount()
  {
   int count=0;
   for(int i=PositionsTotal()-1; i>=0; i--)
      if(g_position.SelectByIndex(i) && InScope(g_position.Symbol()))
         count++;
   return(count);
  }
//+------------------------------------------------------------------+
//| Today's closed + floating P/L                                    |
//+------------------------------------------------------------------+
double TodayPnl()
  {
   return(TodayClosedPnl()+OpenPnl());
  }
//+------------------------------------------------------------------+
//| Log an enforcement action, optionally with a terminal alert      |
//+------------------------------------------------------------------+
void Notify(const string message)
  {
   Print("Risk Guard: ",message);
   if(InpAlerts)
      Alert("Risk Guard: ",message);
  }
//+------------------------------------------------------------------+
//| TradeTransaction function: react to every new position           |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
//--- only entry deals open positions
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_IN)
      return;
   ulong ticket=HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   if(!g_position.SelectByTicket(ticket))
      return;
   OnPositionOpened(ticket);
  }
//+------------------------------------------------------------------+
//| Enforce the rules on a freshly opened position                   |
//+------------------------------------------------------------------+
void OnPositionOpened(const ulong ticket)
  {
   string symbol=g_position.Symbol();
   if(!InScope(symbol))
      return;
   RollDayIfNeeded();
//--- locked for the day: nothing may stay open
   if(g_locked)
     {
      Notify(StringFormat("daily limit active - closing %s #%I64u",symbol,ticket));
      g_trade.PositionClose(ticket);
      return;
     }
//--- position cap: the newest one over the cap is closed
   if(InpMaxPositions>0)
     {
      int open=OpenCount();
      if(open>InpMaxPositions)
        {
         Notify(StringFormat("%d open > max %d - closing newest #%I64u",open,InpMaxPositions,ticket));
         g_trade.PositionClose(ticket);
         return;
        }
     }
   double sl_price=g_position.StopLoss();
   double entry_price=g_position.PriceOpen();
   double pip=PipSize(symbol);
   int    digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
//--- forced stop-loss
   if(InpForceSL && sl_price==0)
     {
      if(g_position.PositionType()==POSITION_TYPE_BUY)
         sl_price=entry_price-InpForcedSlPips*pip;
      else
         sl_price=entry_price+InpForcedSlPips*pip;
      sl_price=NormalizeDouble(sl_price,digits);
      bool ok=g_trade.PositionModify(ticket,sl_price,g_position.TakeProfit());
      Notify(StringFormat("forced SL on #%I64u at %s - %s",ticket,DoubleToString(sl_price,digits),ok ? "ok" : g_trade.ResultRetcodeDescription()));
     }
//--- oversized-trade trim: compare the volume with what the SL distance allows
   if(InpTrimOversized && sl_price>0)
     {
      double stop_pips=MathAbs(entry_price-sl_price)/pip;
      double allowed=LotsForRisk(symbol,stop_pips);
      double volume=g_position.Volume();
      if(allowed>0 && volume>allowed+1e-9)
        {
         double excess=NormalizeLots(symbol,volume-allowed);
         double vol_min=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
         if(allowed<vol_min || volume-excess<vol_min)
           {
            Notify(StringFormat("#%I64u %.2f lots risks more than the limit at its SL (max %.2f) - closing",ticket,volume,allowed));
            g_trade.PositionClose(ticket);
           }
         else
           {
            bool ok=g_trade.PositionClosePartial(ticket,excess);
            Notify(StringFormat("#%I64u %.2f lots > max %.2f for a %.1f-pip SL - trimmed %.2f (%s)",ticket,volume,allowed,stop_pips,excess,ok ? "ok" : g_trade.ResultRetcodeDescription()));
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Engage the daily lock when today's P/L reaches the limit         |
//+------------------------------------------------------------------+
void CheckDailyLimit()
  {
   if(!InpUseDailyLimit || g_locked)
      return;
   double pnl=TodayPnl();
   double limit=DailyLimitMoney();
   if(limit>0 && pnl<=-limit)
     {
      g_locked=true;
      GlobalVariableSet(g_gv_lock,(double)g_day);
      Notify(StringFormat("DAILY LOSS LIMIT HIT - P/L %.2f, limit %.2f. No new positions until tomorrow.",pnl,limit));
      //--- flatten the account
      if(InpCloseAllAtLimit)
         for(int i=PositionsTotal()-1; i>=0; i--)
            if(g_position.SelectByIndex(i) && InScope(g_position.Symbol()))
               g_trade.PositionClose(g_position.Ticket());
     }
  }
//+------------------------------------------------------------------+
//| Main loop: roll the day, check the limit, redraw the panel       |
//+------------------------------------------------------------------+
void Refresh()
  {
   RollDayIfNeeded();
   CheckDailyLimit();
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
   double pnl=TodayPnl();
   double limit=DailyLimitMoney();
   double lots=LotsForRisk(_Symbol,InpStopPips);
   double spread=SpreadPips(_Symbol);
   int    open=OpenCount();
   string currency=AccountInfoString(ACCOUNT_CURRENCY);
//--- status line and colour
   string status="OK";
   if(g_locked)
      status="LOCKED - daily limit hit";
   else
      if(InpMaxSpreadPips>0 && spread>InpMaxSpreadPips)
         status="WAIT - spread too wide";
   color clr=(g_locked ? clrOrangeRed : (status=="OK" ? clrLightGreen : clrGold));
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
   string mode=(InpRiskMode==RISK_PERCENT ? DoubleToString(InpRiskPercent,2)+"% of balance" : "fixed");
   string lines[6];
   lines[0]="RISK GUARD  "+status;
   lines[1]=StringFormat("Risk per trade   %.2f %s  (%s)",RiskMoney(),currency,mode);
   lines[2]=StringFormat("Lot for %.0f pip SL   %.2f lots",InpStopPips,lots);
   lines[3]=StringFormat("Today P/L   %+.2f  /  limit -%.2f",pnl,limit);
   lines[4]=StringFormat("Open positions   %d%s",open,(InpMaxPositions>0 ? " / "+IntegerToString(InpMaxPositions) : ""));
   lines[5]=StringFormat("Spread   %.1f pips%s",spread,(InpMaxSpreadPips>0 ? "  (max "+DoubleToString(InpMaxSpreadPips,1)+")" : ""));
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
   PanelLine("l2",2,lines[2],clrWhite);
   PanelLine("l3",3,lines[3],(pnl<0 ? clrGold : clrWhite));
   PanelLine("l4",4,lines[4],clrWhite);
   PanelLine("l5",5,lines[5],clrWhite);
   ChartRedraw();
  }
//+------------------------------------------------------------------+
