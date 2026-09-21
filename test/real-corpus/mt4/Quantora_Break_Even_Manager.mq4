//+------------------------------------------------------------------+
//|              Quantora Break Even Manager MT4                     |
//|           Professional Trading Utility for MetaTrader 4          |
//|                                                                  |
//| Copyright © 2026 Quantora                                        |
//| https://www.mql5.com/en/users/quantora/seller                    |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2026 Quantora"
#property link      "https://www.mql5.com/en/users/quantora/seller"
#property version   "1.00"
#property strict
#property description "Professional automatic break-even manager for MetaTrader 4."
#property description "Manages manual trades, all trades or a selected Magic Number."

enum ENUM_Q_SCOPE
  {
   Q_CURRENT_SYMBOL=0,
   Q_ALL_SYMBOLS=1
  };

enum ENUM_Q_MAGIC_FILTER
  {
   Q_MANUAL_ONLY=0,
   Q_ALL_TRADES=1,
   Q_SPECIFIC_MAGIC=2
  };

input string              InpScopeHeader             = "========== TRADE SCOPE ==========";
input ENUM_Q_SCOPE        InpScope                   = Q_CURRENT_SYMBOL;
input ENUM_Q_MAGIC_FILTER InpMagicFilter             = Q_MANUAL_ONLY;
input int                 InpSpecificMagic           = 0;
input bool                InpManageBuyTrades         = true;
input bool                InpManageSellTrades        = true;

input string              InpBreakEvenHeader         = "========== BREAK EVEN SETTINGS ==========";
input bool                InpUseBreakEven            = true;
input int                 InpBreakEvenTriggerPoints  = 400;
input int                 InpBreakEvenOffsetPoints   = 30;
input int                 InpMinimumStepPoints       = 10;

input string              InpExecutionHeader         = "========== EXECUTION ==========";
input int                 InpTimerSeconds            = 1;
input bool                InpEnablePrintLog          = true;

input string              InpPanelHeader             = "========== QUANTORA DASHBOARD ==========";
input bool                InpShowPanel               = true;
input ENUM_BASE_CORNER    InpPanelCorner             = CORNER_LEFT_UPPER;
input int                 InpPanelX                  = 15;
input int                 InpPanelY                  = 145;

#define Q_VERSION "1.00"
#define Q_PREFIX  "QBEM4_"

color Q_NAVY   = C'8,23,38';
color Q_GOLD   = C'212,175,55';
color Q_WHITE  = C'245,245,245';
color Q_GRAY   = C'169,176,184';
color Q_GREEN  = C'0,200,83';
color Q_RED    = C'255,82,82';
color Q_BORDER = C'70,86,104';

bool   g_manager_enabled=true;
string g_status="ACTIVE";
int    g_applied_count=0;
int    g_error_count=0;

void QLog(string message)
  {
   if(InpEnablePrintLog)
      Print("[Quantora Break Even Manager MT4] ",message);
  }

string ScopeText()
  {
   return(InpScope==Q_CURRENT_SYMBOL ? "CURRENT SYMBOL" : "ALL SYMBOLS");
  }

string FilterText()
  {
   if(InpMagicFilter==Q_MANUAL_ONLY)
      return "MANUAL ONLY";
   if(InpMagicFilter==Q_SPECIFIC_MAGIC)
      return "MAGIC "+IntegerToString(InpSpecificMagic);
   return "ALL TRADES";
  }

string AccountTypeText()
  {
   return(IsDemo() ? "DEMO" : "REAL");
  }

bool IsMarketOrder(int type)
  {
   return(type==OP_BUY || type==OP_SELL);
  }

bool MatchesSelectedOrder()
  {
   int type=OrderType();
   if(!IsMarketOrder(type))
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

double CurrentBid(string symbol)
  {
   return MarketInfo(symbol,MODE_BID);
  }

double CurrentAsk(string symbol)
  {
   return MarketInfo(symbol,MODE_ASK);
  }

double MinimumStopDistance(string symbol)
  {
   double point=SymbolPointValue(symbol);
   double stop_level=MarketInfo(symbol,MODE_STOPLEVEL)*point;
   double freeze_level=MarketInfo(symbol,MODE_FREEZELEVEL)*point;
   return MathMax(stop_level,freeze_level);
  }

bool IsStopDistanceValid(string symbol,int type,double stop_loss)
  {
   double minimum=MinimumStopDistance(symbol);
   if(type==OP_BUY)
      return(stop_loss<=CurrentBid(symbol)-minimum);
   return(stop_loss>=CurrentAsk(symbol)+minimum);
  }

bool ModifySelectedOrder(double new_stop_loss,string reason)
  {
   string symbol=OrderSymbol();
   int ticket=OrderTicket();
   new_stop_loss=NormalizeSymbolPrice(symbol,new_stop_loss);
   double take_profit=OrderTakeProfit();
   if(take_profit>0.0)
      take_profit=NormalizeSymbolPrice(symbol,take_profit);

   ResetLastError();
   bool result=OrderModify(ticket,OrderOpenPrice(),new_stop_loss,take_profit,0,clrNONE);
   if(result)
     {
      g_applied_count++;
      QLog(reason+" applied. Ticket="+IntegerToString(ticket)+
           " SL="+DoubleToString(new_stop_loss,SymbolDigitsValue(symbol)));
      return true;
     }

   int error=GetLastError();
   g_error_count++;
   QLog(reason+" failed. Ticket="+IntegerToString(ticket)+
        " Error="+IntegerToString(error));
   ResetLastError();
   return false;
  }

bool ApplyBreakEvenToSelectedOrder(bool ignore_trigger=false)
  {
   if(!MatchesSelectedOrder())
      return false;

   string symbol=OrderSymbol();
   int type=OrderType();
   double point=SymbolPointValue(symbol);
   if(point<=0.0)
      return false;

   double open_price=OrderOpenPrice();
   double old_sl=OrderStopLoss();
   double current=(type==OP_BUY ? CurrentBid(symbol) : CurrentAsk(symbol));
   double profit_points=(type==OP_BUY)
                        ? (current-open_price)/point
                        : (open_price-current)/point;

   if(!ignore_trigger && profit_points<InpBreakEvenTriggerPoints)
      return false;

   double candidate=(type==OP_BUY)
                    ? open_price+InpBreakEvenOffsetPoints*point
                    : open_price-InpBreakEvenOffsetPoints*point;

   bool improves=false;
   if(type==OP_BUY)
      improves=(old_sl<=0.0 || candidate>old_sl+InpMinimumStepPoints*point);
   else
      improves=(old_sl<=0.0 || candidate<old_sl-InpMinimumStepPoints*point);

   if(!improves)
      return false;
   if(!IsStopDistanceValid(symbol,type,candidate))
      return false;

   return ModifySelectedOrder(candidate,"Break even");
  }

void ManageTrades()
  {
   if(!g_manager_enabled || !InpUseBreakEven)
      return;

   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;
      ApplyBreakEvenToSelectedOrder(false);
     }
  }

void BreakEvenAllNow()
  {
   int changed=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;
      if(ApplyBreakEvenToSelectedOrder(true))
         changed++;
     }

   if(changed>0)
      g_status="BREAK EVEN APPLIED";
   else
      g_status="NO ELIGIBLE TRADE";
  }

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
   double total=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES) || !MatchesSelectedOrder())
         continue;
      total+=OrderProfit()+OrderSwap()+OrderCommission();
     }
   return total;
  }

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
   CreateLabel(Q_PREFIX+"TRIGGER","TRIGGER: "+IntegerToString(InpBreakEvenTriggerPoints)+" points",x+235,y+188,10,Q_WHITE,true);
   CreateLabel(Q_PREFIX+"SCOPE","SCOPE: "+ScopeText(),x+18,y+214,10,Q_GRAY,true);
   CreateLabel(Q_PREFIX+"TRADES","MANAGED TRADES: 0",x+170,y+214,10,Q_WHITE,true);
   CreateLabel(Q_PREFIX+"FLOAT","FLOATING P/L: 0.00",x+335,y+214,10,Q_GREEN,true);
   CreateLabel(Q_PREFIX+"DETAIL","OFFSET: "+IntegerToString(InpBreakEvenOffsetPoints)+"   APPLIED: 0   ERRORS: 0",x+18,y+240,10,Q_GRAY,true);

   CreateButton(Q_PREFIX+"TOGGLE","STOP MANAGER",x+18,y+270,205,38,C'135,45,45');
   CreateButton(Q_PREFIX+"BE","BREAK EVEN NOW",x+246,y+270,205,38,C'35,105,75');

   CreateLabel(Q_PREFIX+"FOOT","mql5.com/en/users/quantora/seller",x+18,y+315,10,Q_GOLD,true);
   ChartRedraw();
  }

void UpdatePanel()
  {
   if(!InpShowPanel)
      return;

   int managed=CountMatchedTrades();
   if(g_manager_enabled)
      g_status=(managed>0 ? "MONITORING "+IntegerToString(managed)+" TRADE(S)" : "WAITING - NO MATCHED TRADE");

   color status_color=(g_manager_enabled ? Q_GREEN : Q_RED);
   ObjectSetString(0,Q_PREFIX+"STATUS",OBJPROP_TEXT,"STATUS: "+g_status);
   ObjectSetInteger(0,Q_PREFIX+"STATUS",OBJPROP_COLOR,status_color);
   ObjectSetString(0,Q_PREFIX+"BALANCE",OBJPROP_TEXT,"BALANCE: "+DoubleToString(AccountBalance(),2)+" "+AccountCurrency());
   ObjectSetString(0,Q_PREFIX+"EQUITY",OBJPROP_TEXT,"EQUITY: "+DoubleToString(AccountEquity(),2)+" "+AccountCurrency());
   ObjectSetString(0,Q_PREFIX+"MARGIN",OBJPROP_TEXT,"FREE MARGIN: "+DoubleToString(AccountFreeMargin(),2));
   ObjectSetString(0,Q_PREFIX+"SYMBOL",OBJPROP_TEXT,"CURRENT SYMBOL: "+Symbol());
   ObjectSetString(0,Q_PREFIX+"SPREAD",OBJPROP_TEXT,"SPREAD: "+IntegerToString((int)MarketInfo(Symbol(),MODE_SPREAD))+" points");
   ObjectSetString(0,Q_PREFIX+"ACCOUNT",OBJPROP_TEXT,"ACCOUNT TYPE: "+AccountTypeText());
   ObjectSetString(0,Q_PREFIX+"MAGIC",OBJPROP_TEXT,"MAGIC: "+FilterText());
   ObjectSetString(0,Q_PREFIX+"TRADES",OBJPROP_TEXT,"MANAGED TRADES: "+IntegerToString(managed));
   ObjectSetString(0,Q_PREFIX+"FLOAT",OBJPROP_TEXT,"FLOATING P/L: "+DoubleToString(MatchedFloatingProfit(),2));
   ObjectSetString(0,Q_PREFIX+"DETAIL",OBJPROP_TEXT,"OFFSET: "+IntegerToString(InpBreakEvenOffsetPoints)+"   APPLIED: "+IntegerToString(g_applied_count)+"   ERRORS: "+IntegerToString(g_error_count));
   ObjectSetString(0,Q_PREFIX+"TOGGLE",OBJPROP_TEXT,(g_manager_enabled ? "STOP MANAGER" : "START MANAGER"));
   ObjectSetInteger(0,Q_PREFIX+"TOGGLE",OBJPROP_BGCOLOR,(g_manager_enabled ? C'135,45,45' : C'35,105,75'));
   ChartRedraw();
  }

int OnInit()
  {
   if(InpBreakEvenTriggerPoints<0 || InpBreakEvenOffsetPoints<0 ||
      InpMinimumStepPoints<0 || InpTimerSeconds<1)
     {
      Print("Quantora Break Even Manager MT4 | Invalid input value.");
      return INIT_PARAMETERS_INCORRECT;
     }

   BuildPanel();
   EventSetTimer(MathMax(1,InpTimerSeconds));
   QLog("Initialized. Version "+Q_VERSION+" Scope="+ScopeText()+" Filter="+FilterText());
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
   ManageTrades();
  }

void OnTimer()
  {
   ManageTrades();
   UpdatePanel();
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id!=CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam==Q_PREFIX+"TOGGLE")
     {
      g_manager_enabled=!g_manager_enabled;
      g_status=(g_manager_enabled ? "ACTIVE" : "STOPPED");
      UpdatePanel();
     }
   else if(sparam==Q_PREFIX+"BE")
     {
      BreakEvenAllNow();
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
