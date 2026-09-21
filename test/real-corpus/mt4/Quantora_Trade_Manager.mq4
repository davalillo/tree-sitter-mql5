//+------------------------------------------------------------------+
//|                                       Quantora Trade Manager MT4 |
//|                    Professional Trading Utility for MetaTrader 4 |
//|                                                                  |
//| Copyright © 2026 Quantora                                        |
//| https://www.mql5.com/en/users/quantora/seller                    |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2026 Quantora"
#property link      "https://www.mql5.com/en/users/quantora/seller"
#property version   "1.00"
#property strict
#property description "Professional automatic trade management utility for MetaTrader 4."
#property description "Automatic SL/TP, break-even, trailing stop and account protection."

//============================== ENUMS ======================================
enum ENUM_Q_SCOPE
  {
   Q_CURRENT_SYMBOL = 0,
   Q_ALL_SYMBOLS    = 1
  };

enum ENUM_Q_MAGIC_FILTER
  {
   Q_MANUAL_ONLY    = 0,
   Q_ALL_TRADES     = 1,
   Q_SPECIFIC_MAGIC = 2
  };

//============================== INPUTS =====================================
input string              InpScopeHeader             = "========== TRADE SCOPE ==========";
input ENUM_Q_SCOPE        InpScope                   = Q_CURRENT_SYMBOL;
input ENUM_Q_MAGIC_FILTER InpMagicFilter             = Q_MANUAL_ONLY;
input int                 InpSpecificMagic           = 0;
input bool                InpManageBuyTrades         = true;
input bool                InpManageSellTrades        = true;

input string              InpStopsHeader             = "========== AUTOMATIC SL / TP ==========";
input bool                InpSetMissingStopLoss      = true;
input int                 InpStopLossPoints          = 500;
input bool                InpSetMissingTakeProfit    = true;
input int                 InpTakeProfitPoints        = 1000;

input string              InpBreakEvenHeader         = "========== BREAK EVEN ==========";
input bool                InpUseBreakEven            = true;
input int                 InpBreakEvenTriggerPoints  = 400;
input int                 InpBreakEvenOffsetPoints   = 30;

input string              InpTrailingHeader          = "========== TRAILING STOP ==========";
input bool                InpUseTrailingStop         = true;
input int                 InpTrailingStartPoints     = 600;
input int                 InpTrailingDistancePoints  = 350;
input int                 InpTrailingStepPoints      = 50;

input string              InpProtectionHeader        = "========== ACCOUNT PROTECTION ==========";
input bool                InpUseDailyLossLimit       = false;
input double              InpDailyLossLimitMoney     = 100.0;
input bool                InpCloseAllAtDailyLoss     = false;
input bool                InpUseDailyProfitTarget    = false;
input double              InpDailyProfitTargetMoney  = 200.0;
input bool                InpCloseAllAtDailyProfit   = false;

input string              InpExecutionHeader         = "========== EXECUTION ==========";
input int                 InpSlippagePoints          = 30;
input int                 InpTimerSeconds            = 1;
input bool                InpEnablePrintLog          = true;

input string              InpPanelHeader             = "========== QUANTORA PANEL ==========";
input bool                InpShowPanel               = true;
input ENUM_BASE_CORNER    InpPanelCorner             = CORNER_LEFT_UPPER;
input int                 InpPanelX                  = 15;
input int                 InpPanelY                  = 145;

//============================== CONSTANTS ==================================
#define Q_VERSION "1.00"
#define Q_PREFIX  "QTM4_"

color Q_NAVY  = C'8,23,38';
color Q_GOLD  = C'212,175,55';
color Q_WHITE = C'245,245,245';
color Q_GRAY  = C'169,176,184';
color Q_GREEN = C'0,200,83';
color Q_RED   = C'255,82,82';

//============================== STATE ======================================
bool     g_manager_enabled = true;
bool     g_protection_hit  = false;
datetime g_day_start       = 0;
double   g_day_balance     = 0.0;
string   g_status          = "ACTIVE";

//============================== LOGGING ====================================
void QLog(string message)
  {
   if(InpEnablePrintLog)
      Print("Quantora Trade Manager MT4 | ",message);
  }

//============================== TIME / ACCOUNT =============================
datetime StartOfDay(datetime value)
  {
   return StringToTime(TimeToString(value,TIME_DATE));
  }

void RefreshDayState()
  {
   datetime today=StartOfDay(TimeCurrent());
   if(today!=g_day_start)
     {
      g_day_start=today;
      g_day_balance=AccountBalance();
      g_protection_hit=false;
      if(g_manager_enabled)
         g_status="ACTIVE";
     }
  }

double DailyResult()
  {
   RefreshDayState();
   double result=0.0;

   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY))
         continue;
      if(OrderCloseTime()<g_day_start)
         break;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL)
         continue;
      result+=OrderProfit()+OrderSwap()+OrderCommission();
     }

   for(int j=OrdersTotal()-1;j>=0;j--)
     {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES))
         continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL)
         continue;
      result+=OrderProfit()+OrderSwap()+OrderCommission();
     }

   return result;
  }

//============================== SYMBOL HELPERS =============================
double SymbolPointValue(string symbol)
  {
   return MarketInfo(symbol,MODE_POINT);
  }

int SymbolDigitsValue(string symbol)
  {
   return (int)MarketInfo(symbol,MODE_DIGITS);
  }

double NormalizeSymbolPrice(string symbol,double price)
  {
   return NormalizeDouble(price,SymbolDigitsValue(symbol));
  }

double MinimumStopDistance(string symbol)
  {
   double point=SymbolPointValue(symbol);
   double stop_level=MarketInfo(symbol,MODE_STOPLEVEL)*point;
   double freeze_level=MarketInfo(symbol,MODE_FREEZELEVEL)*point;
   return MathMax(stop_level,freeze_level);
  }

double CurrentBid(string symbol)
  {
   return MarketInfo(symbol,MODE_BID);
  }

double CurrentAsk(string symbol)
  {
   return MarketInfo(symbol,MODE_ASK);
  }

//============================== FILTERING ==================================
bool IsMarketTradeType(int type)
  {
   return (type==OP_BUY || type==OP_SELL);
  }

bool MatchesSelectedOrder()
  {
   int type=OrderType();
   if(!IsMarketTradeType(type))
      return false;

   if(InpScope==Q_CURRENT_SYMBOL && OrderSymbol()!=Symbol())
      return false;

   if(type==OP_BUY && !InpManageBuyTrades)
      return false;
   if(type==OP_SELL && !InpManageSellTrades)
      return false;

   int magic=OrderMagicNumber();
   if(InpMagicFilter==Q_MANUAL_ONLY && magic!=0)
      return false;
   if(InpMagicFilter==Q_SPECIFIC_MAGIC && magic!=InpSpecificMagic)
      return false;

   return true;
  }

string ScopeText()
  {
   return (InpScope==Q_CURRENT_SYMBOL ? "CURRENT SYMBOL" : "ALL SYMBOLS");
  }

string FilterText()
  {
   if(InpMagicFilter==Q_MANUAL_ONLY)
      return "MANUAL ONLY";
   if(InpMagicFilter==Q_SPECIFIC_MAGIC)
      return "MAGIC "+IntegerToString(InpSpecificMagic);
   return "ALL TRADES";
  }

//============================== ORDER OPERATIONS ===========================
bool ModifySelectedOrder(double stop_loss,double take_profit,string reason)
  {
   string symbol=OrderSymbol();
   int ticket=OrderTicket();

   stop_loss=(stop_loss>0.0 ? NormalizeSymbolPrice(symbol,stop_loss) : 0.0);
   take_profit=(take_profit>0.0 ? NormalizeSymbolPrice(symbol,take_profit) : 0.0);

   ResetLastError();
   bool modified=OrderModify(ticket,OrderOpenPrice(),stop_loss,take_profit,0,clrNONE);
   if(!modified)
     {
      int error=GetLastError();
      QLog(reason+" modify failed. Ticket="+IntegerToString(ticket)+
           " Symbol="+symbol+" Error="+IntegerToString(error));
      ResetLastError();
      return false;
     }

   QLog(reason+" applied. Ticket="+IntegerToString(ticket)+" Symbol="+symbol);
   return true;
  }

bool CloseSelectedOrder(string reason)
  {
   int type=OrderType();
   string symbol=OrderSymbol();
   double price=(type==OP_BUY ? CurrentBid(symbol) : CurrentAsk(symbol));
   price=NormalizeSymbolPrice(symbol,price);

   ResetLastError();
   bool closed=OrderClose(OrderTicket(),OrderLots(),price,InpSlippagePoints,clrNONE);
   if(!closed)
     {
      int error=GetLastError();
      QLog(reason+" close failed. Ticket="+IntegerToString(OrderTicket())+
           " Error="+IntegerToString(error));
      ResetLastError();
      return false;
     }

   QLog(reason+" closed ticket "+IntegerToString(OrderTicket()));
   return true;
  }

//============================== TRADE MANAGEMENT ===========================
void EnsureInitialStops()
  {
   string symbol=OrderSymbol();
   int type=OrderType();
   double point=SymbolPointValue(symbol);
   double minimum=MinimumStopDistance(symbol);
   double open=OrderOpenPrice();
   double old_sl=OrderStopLoss();
   double old_tp=OrderTakeProfit();
   double new_sl=old_sl;
   double new_tp=old_tp;

   if(InpSetMissingStopLoss && old_sl<=0.0 && InpStopLossPoints>0)
     {
      double distance=MathMax(InpStopLossPoints*point,minimum);
      new_sl=(type==OP_BUY ? open-distance : open+distance);
     }

   if(InpSetMissingTakeProfit && old_tp<=0.0 && InpTakeProfitPoints>0)
     {
      double distance=MathMax(InpTakeProfitPoints*point,minimum);
      new_tp=(type==OP_BUY ? open+distance : open-distance);
     }

   if(MathAbs(new_sl-old_sl)>point/2.0 || MathAbs(new_tp-old_tp)>point/2.0)
      ModifySelectedOrder(new_sl,new_tp,"Initial SL/TP");
  }

void ApplyBreakEven()
  {
   if(!InpUseBreakEven || InpBreakEvenTriggerPoints<=0)
      return;

   string symbol=OrderSymbol();
   int type=OrderType();
   double point=SymbolPointValue(symbol);
   double bid=CurrentBid(symbol);
   double ask=CurrentAsk(symbol);
   double open=OrderOpenPrice();
   double old_sl=OrderStopLoss();
   double tp=OrderTakeProfit();
   double profit_points=(type==OP_BUY ? (bid-open)/point : (open-ask)/point);

   if(profit_points<InpBreakEvenTriggerPoints)
      return;

   double candidate=(type==OP_BUY ? open+InpBreakEvenOffsetPoints*point
                                  : open-InpBreakEvenOffsetPoints*point);
   double minimum=MinimumStopDistance(symbol);
   if(type==OP_BUY)
      candidate=MathMin(candidate,bid-minimum);
   else
      candidate=MathMax(candidate,ask+minimum);

   candidate=NormalizeSymbolPrice(symbol,candidate);
   bool improves=(type==OP_BUY ? (old_sl<=0.0 || candidate>old_sl+point/2.0)
                               : (old_sl<=0.0 || candidate<old_sl-point/2.0));
   if(improves)
      ModifySelectedOrder(candidate,tp,"Break even");
  }

void ApplyTrailingStop()
  {
   if(!InpUseTrailingStop || InpTrailingStartPoints<=0 || InpTrailingDistancePoints<=0)
      return;

   string symbol=OrderSymbol();
   int type=OrderType();
   double point=SymbolPointValue(symbol);
   double bid=CurrentBid(symbol);
   double ask=CurrentAsk(symbol);
   double open=OrderOpenPrice();
   double old_sl=OrderStopLoss();
   double tp=OrderTakeProfit();
   double profit_points=(type==OP_BUY ? (bid-open)/point : (open-ask)/point);

   if(profit_points<InpTrailingStartPoints)
      return;

   double minimum=MinimumStopDistance(symbol);
   double distance=MathMax(InpTrailingDistancePoints*point,minimum);
   double candidate=(type==OP_BUY ? bid-distance : ask+distance);
   candidate=NormalizeSymbolPrice(symbol,candidate);

   double step=MathMax(0,InpTrailingStepPoints)*point;
   bool improves=false;
   if(type==OP_BUY)
      improves=(old_sl<=0.0 || candidate>=old_sl+step);
   else
      improves=(old_sl<=0.0 || candidate<=old_sl-step);

   if(improves)
      ModifySelectedOrder(candidate,tp,"Trailing stop");
  }

void ManageTrades()
  {
   if(!g_manager_enabled || g_protection_hit)
      return;

   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;
      if(!MatchesSelectedOrder())
         continue;

      EnsureInitialStops();

      // Reselect because OrderModify can invalidate cached values.
      int ticket=OrderTicket();
      if(!OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES))
         continue;
      ApplyBreakEven();

      if(!OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES))
         continue;
      ApplyTrailingStop();
     }
  }

void BreakEvenAllNow()
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES) || !MatchesSelectedOrder())
         continue;

      string symbol=OrderSymbol();
      int type=OrderType();
      double point=SymbolPointValue(symbol);
      double old_sl=OrderStopLoss();
      double candidate=(type==OP_BUY ? OrderOpenPrice()+InpBreakEvenOffsetPoints*point
                                     : OrderOpenPrice()-InpBreakEvenOffsetPoints*point);
      double minimum=MinimumStopDistance(symbol);
      if(type==OP_BUY)
         candidate=MathMin(candidate,CurrentBid(symbol)-minimum);
      else
         candidate=MathMax(candidate,CurrentAsk(symbol)+minimum);

      bool improves=(type==OP_BUY ? (old_sl<=0.0 || candidate>old_sl)
                                  : (old_sl<=0.0 || candidate<old_sl));
      if(improves)
         ModifySelectedOrder(candidate,OrderTakeProfit(),"Manual break even");
     }
  }

void CloseMatchedTrades(string reason)
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES) || !MatchesSelectedOrder())
         continue;
      CloseSelectedOrder(reason);
     }
  }

//============================== ACCOUNT PROTECTION =========================
void CheckAccountProtection()
  {
   RefreshDayState();
   if(g_protection_hit)
      return;

   double daily=DailyResult();

   if(InpUseDailyLossLimit && InpDailyLossLimitMoney>0.0 && daily<=-InpDailyLossLimitMoney)
     {
      g_protection_hit=true;
      g_manager_enabled=false;
      g_status="DAILY LOSS LIMIT";
      QLog("Daily loss limit reached: "+DoubleToString(daily,2));
      if(InpCloseAllAtDailyLoss)
         CloseMatchedTrades("Daily loss protection");
      return;
     }

   if(InpUseDailyProfitTarget && InpDailyProfitTargetMoney>0.0 && daily>=InpDailyProfitTargetMoney)
     {
      g_protection_hit=true;
      g_manager_enabled=false;
      g_status="DAILY PROFIT TARGET";
      QLog("Daily profit target reached: "+DoubleToString(daily,2));
      if(InpCloseAllAtDailyProfit)
         CloseMatchedTrades("Daily profit protection");
     }
  }

//============================== STATISTICS =================================
int CountMatchedTrades()
  {
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && MatchesSelectedOrder())
         count++;
     }
   return count;
  }

double MatchedFloatingProfit()
  {
   double result=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES) || !MatchesSelectedOrder())
         continue;
      result+=OrderProfit()+OrderSwap()+OrderCommission();
     }
   return result;
  }

string AccountTypeText()
  {
   return (IsDemo() ? "DEMO" : "REAL");
  }

string RiskText()
  {
   if(InpUseDailyLossLimit)
      return DoubleToString(InpDailyLossLimitMoney,2)+" "+AccountCurrency();
   return "NOT SET";
  }

//============================== PANEL OBJECTS ==============================
void DeletePanel()
  {
   for(int i=ObjectsTotal()-1;i>=0;i--)
     {
      string name=ObjectName(i);
      if(StringFind(name,Q_PREFIX,0)==0)
         ObjectDelete(name);
     }
  }

void SetCommonObjectProperties(string name)
  {
   ObjectSetInteger(0,name,OBJPROP_CORNER,InpPanelCorner);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

bool CreateRectangle(string name,int x,int y,int width,int height,color background,color border)
  {
   if(!ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0))
      return false;
   SetCommonObjectProperties(name);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,background);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,border);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   return true;
  }

bool CreateLabel(string name,string text,int x,int y,int size,color text_color,bool bold=false)
  {
   if(!ObjectCreate(0,name,OBJ_LABEL,0,0,0))
      return false;
   SetCommonObjectProperties(name);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,(bold ? "Arial Bold" : "Arial"));
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetInteger(0,name,OBJPROP_COLOR,text_color);
   return true;
  }

bool CreateButton(string name,string text,int x,int y,int width,int height,color background)
  {
   if(!ObjectCreate(0,name,OBJ_BUTTON,0,0,0))
      return false;
   SetCommonObjectProperties(name);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,height);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial Bold");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,10);
   ObjectSetInteger(0,name,OBJPROP_COLOR,Q_WHITE);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,background);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,Q_GOLD);
   return true;
  }

void BuildPanel()
  {
   if(!InpShowPanel)
      return;

   DeletePanel();
   int x=InpPanelX;
   int y=InpPanelY;

   CreateRectangle(Q_PREFIX+"BG",x,y,470,335,Q_NAVY,Q_GOLD);
   CreateLabel(Q_PREFIX+"BRAND","QUANTORA",x+18,y+14,14,Q_GOLD,true);
   CreateLabel(Q_PREFIX+"SUBTITLE","Professional Trading Tool",x+18,y+38,10,Q_WHITE,true);
   CreateLabel(Q_PREFIX+"VERSION","MT4  v"+Q_VERSION,x+382,y+18,10,Q_GRAY,true);

   CreateLabel(Q_PREFIX+"LINE1","----------------------------------------------",x+18,y+60,10,Q_GRAY,false);
   CreateLabel(Q_PREFIX+"STATUS","STATUS: ACTIVE",x+18,y+82,11,Q_GREEN,true);
   CreateLabel(Q_PREFIX+"BALANCE","BALANCE: 0.00",x+18,y+110,10,Q_WHITE,true);
   CreateLabel(Q_PREFIX+"EQUITY","EQUITY: 0.00",x+235,y+110,10,Q_WHITE,true);
   CreateLabel(Q_PREFIX+"MARGIN","FREE MARGIN: 0.00",x+18,y+136,10,Q_WHITE,true);
   CreateLabel(Q_PREFIX+"SYMBOL","CURRENT SYMBOL: "+Symbol(),x+235,y+136,10,Q_WHITE,true);
   CreateLabel(Q_PREFIX+"SPREAD","SPREAD: 0",x+18,y+162,10,Q_WHITE,true);
   CreateLabel(Q_PREFIX+"ACCOUNT","ACCOUNT TYPE: "+AccountTypeText(),x+235,y+162,10,Q_WHITE,true);
   CreateLabel(Q_PREFIX+"MAGIC","MAGIC: "+FilterText(),x+18,y+188,10,Q_WHITE,true);
   CreateLabel(Q_PREFIX+"RISK","RISK LIMIT: "+RiskText(),x+235,y+188,10,Q_WHITE,true);
   CreateLabel(Q_PREFIX+"TRADES","TRADES: 0",x+18,y+214,10,Q_WHITE,true);
   CreateLabel(Q_PREFIX+"FLOAT","FLOATING P/L: 0.00",x+150,y+214,10,Q_WHITE,true);
   CreateLabel(Q_PREFIX+"DAILY","DAILY P/L: 0.00",x+320,y+214,10,Q_WHITE,true);

   CreateButton(Q_PREFIX+"TOGGLE","STOP MANAGER",x+18,y+246,135,38,C'135,45,45');
   CreateButton(Q_PREFIX+"CLOSE","CLOSE MATCHED",x+166,y+246,135,38,C'105,70,25');
   CreateButton(Q_PREFIX+"BE","BREAK EVEN NOW",x+314,y+246,135,38,C'35,105,75');

   CreateLabel(Q_PREFIX+"FOOT","mql5.com/en/users/quantora/seller",x+18,y+305,10,Q_GOLD,true);
   ChartRedraw();
  }

void UpdatePanel()
  {
   if(!InpShowPanel)
      return;

   color status_color=(g_manager_enabled ? Q_GREEN : Q_RED);
   ObjectSetString(0,Q_PREFIX+"STATUS",OBJPROP_TEXT,"STATUS: "+g_status);
   ObjectSetInteger(0,Q_PREFIX+"STATUS",OBJPROP_COLOR,status_color);
   ObjectSetString(0,Q_PREFIX+"BALANCE",OBJPROP_TEXT,
                   "BALANCE: "+DoubleToString(AccountBalance(),2)+" "+AccountCurrency());
   ObjectSetString(0,Q_PREFIX+"EQUITY",OBJPROP_TEXT,
                   "EQUITY: "+DoubleToString(AccountEquity(),2)+" "+AccountCurrency());
   ObjectSetString(0,Q_PREFIX+"MARGIN",OBJPROP_TEXT,
                   "FREE MARGIN: "+DoubleToString(AccountFreeMargin(),2));
   ObjectSetString(0,Q_PREFIX+"SYMBOL",OBJPROP_TEXT,"CURRENT SYMBOL: "+Symbol());
   ObjectSetString(0,Q_PREFIX+"SPREAD",OBJPROP_TEXT,
                   "SPREAD: "+IntegerToString((int)MarketInfo(Symbol(),MODE_SPREAD))+" points");
   ObjectSetString(0,Q_PREFIX+"ACCOUNT",OBJPROP_TEXT,"ACCOUNT TYPE: "+AccountTypeText());
   ObjectSetString(0,Q_PREFIX+"MAGIC",OBJPROP_TEXT,"MAGIC: "+FilterText());
   ObjectSetString(0,Q_PREFIX+"RISK",OBJPROP_TEXT,"RISK LIMIT: "+RiskText());
   ObjectSetString(0,Q_PREFIX+"TRADES",OBJPROP_TEXT,
                   "TRADES: "+IntegerToString(CountMatchedTrades()));
   ObjectSetString(0,Q_PREFIX+"FLOAT",OBJPROP_TEXT,
                   "FLOATING P/L: "+DoubleToString(MatchedFloatingProfit(),2));
   ObjectSetString(0,Q_PREFIX+"DAILY",OBJPROP_TEXT,
                   "DAILY P/L: "+DoubleToString(DailyResult(),2));
   ObjectSetString(0,Q_PREFIX+"TOGGLE",OBJPROP_TEXT,
                   (g_manager_enabled ? "STOP MANAGER" : "START MANAGER"));
   ObjectSetInteger(0,Q_PREFIX+"TOGGLE",OBJPROP_BGCOLOR,
                    (g_manager_enabled ? C'135,45,45' : C'35,105,75'));
   ChartRedraw();
  }

//============================== EVENTS =====================================
int OnInit()
  {
   if(InpStopLossPoints<0 || InpTakeProfitPoints<0 ||
      InpBreakEvenTriggerPoints<0 || InpBreakEvenOffsetPoints<0 ||
      InpTrailingStartPoints<0 || InpTrailingDistancePoints<0 ||
      InpTrailingStepPoints<0 || InpSlippagePoints<0)
     {
      Print("Quantora Trade Manager MT4 | Invalid negative input value.");
      return INIT_PARAMETERS_INCORRECT;
     }

   RefreshDayState();
   BuildPanel();
   EventSetTimer(MathMax(1,InpTimerSeconds));
   QLog("Initialized successfully. Version "+Q_VERSION+" Scope="+ScopeText()+" Filter="+FilterText());
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   DeletePanel();
   ChartRedraw();
   QLog("Removed from chart. Reason="+IntegerToString(reason));
  }

void OnTick()
  {
   CheckAccountProtection();
   ManageTrades();
  }

void OnTimer()
  {
   CheckAccountProtection();
   ManageTrades();
   UpdatePanel();
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id!=CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam==Q_PREFIX+"TOGGLE")
     {
      if(g_protection_hit)
        {
         g_status="PROTECTION LOCKED";
         UpdatePanel();
         return;
        }
      g_manager_enabled=!g_manager_enabled;
      g_status=(g_manager_enabled ? "ACTIVE" : "STOPPED");
      UpdatePanel();
     }
   else if(sparam==Q_PREFIX+"CLOSE")
     {
      CloseMatchedTrades("Panel command");
      g_status="MATCHED TRADES CLOSED";
      UpdatePanel();
     }
   else if(sparam==Q_PREFIX+"BE")
     {
      BreakEvenAllNow();
      g_status="BREAK EVEN APPLIED";
      UpdatePanel();
     }
  }

//===========================================================
// Developed by Quantora
//
// More Professional Trading Robots
//
// https://www.mql5.com/en/users/quantora/seller
//===========================================================
