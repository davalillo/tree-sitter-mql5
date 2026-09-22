//+------------------------------------------------------------------+
//|                Quantora Trailing Stop Manager MT4                |
//|           Professional Trading Utility for MetaTrader 4          |
//|                                                                  |
//| Copyright © 2026 Quantora                                        |
//| https://www.mql5.com/en/users/quantora/seller                    |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2026 Quantora"
#property link      "https://www.mql5.com/en/users/quantora/seller"
#property version   "1.00"
#property strict
#property description "Professional automatic trailing stop manager for MetaTrader 4."
#property description "Manages manual trades, all trades or a specific Magic Number."

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
input string              InpScopeHeader            = "========== TRADE SCOPE ==========";
input ENUM_Q_SCOPE        InpScope                  = Q_CURRENT_SYMBOL;
input ENUM_Q_MAGIC_FILTER InpMagicFilter            = Q_MANUAL_ONLY;
input int                 InpSpecificMagic          = 0;
input bool                InpManageBuyTrades        = true;
input bool                InpManageSellTrades       = true;

input string              InpTrailingHeader         = "========== TRAILING STOP ==========";
input int                 InpTrailingStartPoints    = 600;
input int                 InpTrailingDistancePoints = 350;
input int                 InpTrailingStepPoints     = 50;
input int                 InpMinimumProfitPoints    = 600;

input string              InpExecutionHeader        = "========== EXECUTION ==========";
input int                 InpTimerSeconds           = 1;
input int                 InpSlippagePoints         = 30;
input bool                InpPrintLogs              = true;

input string              InpPanelHeader            = "========== DASHBOARD ==========";
input bool                InpShowPanel              = true;
input ENUM_BASE_CORNER    InpPanelCorner            = CORNER_LEFT_UPPER;
input int                 InpPanelX                 = 15;
input int                 InpPanelY                 = 145;

//============================== BRAND COLORS ===============================
#define Q_BG       C'8,23,38'
#define Q_GOLD     C'212,175,55'
#define Q_WHITE    C'245,245,245'
#define Q_GRAY     C'169,176,184'
#define Q_GREEN    C'0,200,83'
#define Q_RED      C'255,82,82'
#define Q_BUTTON   C'18,48,75'
#define Q_BORDER   C'62,76,89'

//============================== STATE ======================================
string g_prefix = "QTSM4_";
bool   g_manager_enabled = true;
string g_status = "ACTIVE";
int    g_update_count = 0;
int    g_error_count  = 0;

//============================== HELPERS ====================================
void LogMessage(string message)
  {
   if(InpPrintLogs)
      Print("Quantora Trailing Stop Manager MT4: ",message);
  }

double SymbolPoint(string symbol)
  {
   return MarketInfo(symbol,MODE_POINT);
  }

int SymbolDigits(string symbol)
  {
   return (int)MarketInfo(symbol,MODE_DIGITS);
  }

double NormalizePrice(string symbol,double price)
  {
   return NormalizeDouble(price,SymbolDigits(symbol));
  }

double CurrentBid(string symbol)
  {
   if(symbol==Symbol())
     {
      RefreshRates();
      return Bid;
     }
   return MarketInfo(symbol,MODE_BID);
  }

double CurrentAsk(string symbol)
  {
   if(symbol==Symbol())
     {
      RefreshRates();
      return Ask;
     }
   return MarketInfo(symbol,MODE_ASK);
  }

bool IsMarketOrder(int type)
  {
   return (type==OP_BUY || type==OP_SELL);
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

int CountMatchedTrades()
  {
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;
      if(MatchesSelectedOrder())
         count++;
     }
   return count;
  }

double MatchedFloatingProfit()
  {
   double result=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;
      if(!MatchesSelectedOrder())
         continue;
      result+=OrderProfit()+OrderSwap()+OrderCommission();
     }
   return result;
  }

string ScopeText()
  {
   return (InpScope==Q_CURRENT_SYMBOL ? "CURRENT SYMBOL" : "ALL SYMBOLS");
  }

string MagicText()
  {
   if(InpMagicFilter==Q_MANUAL_ONLY)
      return "MANUAL ONLY";
   if(InpMagicFilter==Q_SPECIFIC_MAGIC)
      return "MAGIC "+IntegerToString(InpSpecificMagic);
   return "ALL TRADES";
  }

string AccountTypeText()
  {
   return (IsDemo() ? "DEMO" : "REAL");
  }

bool IsTradeEnvironmentReady()
  {
   if(!IsConnected())
     {
      g_status="NO CONNECTION";
      return false;
     }
   if(!IsTradeAllowed())
     {
      g_status="TRADING DISABLED";
      return false;
     }
   return true;
  }

double MinimumStopDistance(string symbol)
  {
   double point=SymbolPoint(symbol);
   int stop_level=(int)MarketInfo(symbol,MODE_STOPLEVEL);
   int freeze_level=(int)MarketInfo(symbol,MODE_FREEZELEVEL);
   int minimum=MathMax(stop_level,freeze_level);
   return minimum*point;
  }

bool IsCandidateValid(string symbol,int type,double candidate)
  {
   double min_distance=MinimumStopDistance(symbol);
   double bid=CurrentBid(symbol);
   double ask=CurrentAsk(symbol);

   if(bid<=0.0 || ask<=0.0)
      return false;

   if(type==OP_BUY)
      return (candidate < bid-min_distance);

   if(type==OP_SELL)
      return (candidate > ask+min_distance);

   return false;
  }

bool ModifySelectedOrder(double new_sl)
  {
   int ticket=OrderTicket();
   string symbol=OrderSymbol();
   double normalized_sl=NormalizePrice(symbol,new_sl);

   ResetLastError();
   bool modified=OrderModify(ticket,
                             OrderOpenPrice(),
                             normalized_sl,
                             OrderTakeProfit(),
                             0,
                             clrNONE);
   if(!modified)
     {
      int error=GetLastError();
      g_error_count++;
      g_status="MODIFY ERROR "+IntegerToString(error);
      LogMessage("OrderModify failed. Ticket="+IntegerToString(ticket)+
                 " Error="+IntegerToString(error));
      ResetLastError();
      return false;
     }

   g_update_count++;
   g_status="TRAILING UPDATED";
   LogMessage("Trailing Stop updated. Ticket="+IntegerToString(ticket)+
              " New SL="+DoubleToString(normalized_sl,SymbolDigits(symbol)));
   return true;
  }

bool ApplyTrailingToSelectedOrder(bool force_now)
  {
   int type=OrderType();
   if(!IsMarketOrder(type))
      return false;

   string symbol=OrderSymbol();
   double point=SymbolPoint(symbol);
   if(point<=0.0)
      return false;

   double open_price=OrderOpenPrice();
   double old_sl=OrderStopLoss();
   double bid=CurrentBid(symbol);
   double ask=CurrentAsk(symbol);

   if(bid<=0.0 || ask<=0.0)
      return false;

   double profit_points=(type==OP_BUY)
                        ? (bid-open_price)/point
                        : (open_price-ask)/point;

   int activation_points=MathMax(InpTrailingStartPoints,InpMinimumProfitPoints);

   if(!force_now && profit_points<activation_points)
      return false;

   if(force_now && profit_points<=0.0)
      return false;

   double candidate=(type==OP_BUY)
                    ? bid-InpTrailingDistancePoints*point
                    : ask+InpTrailingDistancePoints*point;

   candidate=NormalizePrice(symbol,candidate);

   if(!IsCandidateValid(symbol,type,candidate))
      return false;

   double step=InpTrailingStepPoints*point;
   bool improves=false;

   if(type==OP_BUY)
     {
      improves=(old_sl<=0.0 || candidate>old_sl+step);
      if(candidate<=open_price && !force_now)
         return false;
     }
   else
     {
      improves=(old_sl<=0.0 || candidate<old_sl-step);
      if(candidate>=open_price && !force_now)
         return false;
     }

   if(!improves)
      return false;

   return ModifySelectedOrder(candidate);
  }

void ManageTrailingStops(bool force_now=false)
  {
   if(!g_manager_enabled && !force_now)
      return;

   if(!IsTradeEnvironmentReady())
      return;

   int matched=0;
   int changed=0;

   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;

      if(!MatchesSelectedOrder())
         continue;

      matched++;
      if(ApplyTrailingToSelectedOrder(force_now))
         changed++;
     }

   if(force_now)
     {
      if(changed>0)
         g_status="TRAIL APPLIED: "+IntegerToString(changed);
      else if(matched==0)
         g_status="NO MATCHED TRADES";
      else
         g_status="NO ELIGIBLE TRADE";
     }
   else if(matched==0)
      g_status="WAITING - NO MATCHED TRADE";
   else if(g_status!="TRAILING UPDATED")
      g_status="MONITORING "+IntegerToString(matched)+" TRADE(S)";
  }

//============================== PANEL HELPERS ==============================
bool CreateRectangle(string name,int x,int y,int width,int height,color background,color border)
  {
   if(!ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0))
      return false;

   ObjectSetInteger(0,name,OBJPROP_CORNER,InpPanelCorner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,background);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,border);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   return true;
  }

bool CreateLabel(string name,string text,int x,int y,int size,color text_color,bool bold=false)
  {
   if(!ObjectCreate(0,name,OBJ_LABEL,0,0,0))
      return false;

   ObjectSetInteger(0,name,OBJPROP_CORNER,InpPanelCorner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_COLOR,text_color);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetString(0,name,OBJPROP_FONT,(bold ? "Arial Bold" : "Arial"));
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   return true;
  }

bool CreateButton(string name,string text,int x,int y,int width,int height,color background)
  {
   if(!ObjectCreate(0,name,OBJ_BUTTON,0,0,0))
      return false;

   ObjectSetInteger(0,name,OBJPROP_CORNER,InpPanelCorner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,background);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,Q_GOLD);
   ObjectSetInteger(0,name,OBJPROP_COLOR,Q_WHITE);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial Bold");
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   return true;
  }

void DeletePanel()
  {
  for(int i=ObjectsTotal()-1;i>=0;i--)
     {
      string name=ObjectName(0,i);
      if(StringFind(name,g_prefix)==0)
         ObjectDelete(0,name);
     }
  }

void BuildPanel()
  {
   if(!InpShowPanel)
      return;

   DeletePanel();

   int x=InpPanelX;
   int y=InpPanelY;
   int w=470;
   int h=390;

   CreateRectangle(g_prefix+"BG",x,y,w,h,Q_BG,Q_GOLD);

   CreateLabel(g_prefix+"TITLE","QUANTORA",x+18,y+14,14,Q_GOLD,true);
   CreateLabel(g_prefix+"SUB","TRAILING STOP MANAGER",x+18,y+38,11,Q_WHITE,true);
   CreateLabel(g_prefix+"VER","MT4  v1.00",x+382,y+18,9,Q_GRAY,false);

   CreateLabel(g_prefix+"STATUS","STATUS: ACTIVE",x+18,y+72,10,Q_GREEN,true);
   CreateLabel(g_prefix+"BAL","BALANCE: 0.00",x+18,y+102,10,Q_WHITE,false);
   CreateLabel(g_prefix+"EQUITY","EQUITY: 0.00",x+245,y+102,10,Q_WHITE,false);
   CreateLabel(g_prefix+"MARGIN","FREE MARGIN: 0.00",x+18,y+128,10,Q_WHITE,false);
   CreateLabel(g_prefix+"SYMBOL","CURRENT SYMBOL: "+Symbol(),x+245,y+128,10,Q_WHITE,false);
   CreateLabel(g_prefix+"SPREAD","SPREAD: 0",x+18,y+154,10,Q_WHITE,false);
   CreateLabel(g_prefix+"ACCOUNT","ACCOUNT TYPE: "+AccountTypeText(),x+245,y+154,10,Q_WHITE,false);
   CreateLabel(g_prefix+"MAGIC","MAGIC: "+MagicText(),x+18,y+180,10,Q_GRAY,false);
   CreateLabel(g_prefix+"SCOPE","SCOPE: "+ScopeText(),x+245,y+180,10,Q_GRAY,false);

   CreateLabel(g_prefix+"POSITIONS","MANAGED TRADES: 0",x+18,y+214,10,Q_WHITE,true);
   CreateLabel(g_prefix+"FLOAT","FLOATING P/L: 0.00",x+245,y+214,10,Q_WHITE,true);

   CreateLabel(g_prefix+"START","TRAIL START: "+IntegerToString(InpTrailingStartPoints)+" points",x+18,y+242,10,Q_GRAY,false);
   CreateLabel(g_prefix+"DIST","DISTANCE: "+IntegerToString(InpTrailingDistancePoints)+" points",x+245,y+242,10,Q_GRAY,false);
   CreateLabel(g_prefix+"STEP","STEP: "+IntegerToString(InpTrailingStepPoints)+" points",x+18,y+268,10,Q_GRAY,false);
   CreateLabel(g_prefix+"MIN","MIN PROFIT: "+IntegerToString(InpMinimumProfitPoints)+" points",x+245,y+268,10,Q_GRAY,false);

   CreateLabel(g_prefix+"COUNT","UPDATES: 0",x+18,y+296,10,Q_GREEN,false);
   CreateLabel(g_prefix+"ERRORS","ERRORS: 0",x+245,y+296,10,Q_RED,false);

   CreateButton(g_prefix+"TOGGLE","STOP MANAGER",x+18,y+324,205,38,Q_RED);
   CreateButton(g_prefix+"TRAIL","TRAIL NOW",x+247,y+324,205,38,Q_BUTTON);

   CreateLabel(g_prefix+"FOOT","mql5.com/en/users/quantora/seller",x+18,y+370,9,Q_GOLD,false);

   ChartRedraw();
  }

void UpdatePanel()
  {
   if(!InpShowPanel)
      return;

   int matched=CountMatchedTrades();
   double floating=MatchedFloatingProfit();
   double spread=(MarketInfo(Symbol(),MODE_ASK)-MarketInfo(Symbol(),MODE_BID))/Point;

   ObjectSetString(0,g_prefix+"STATUS",OBJPROP_TEXT,"STATUS: "+g_status);
   ObjectSetInteger(0,g_prefix+"STATUS",OBJPROP_COLOR,
                    g_manager_enabled ? Q_GREEN : Q_RED);

   ObjectSetString(0,g_prefix+"BAL",OBJPROP_TEXT,
                   "BALANCE: "+DoubleToString(AccountBalance(),2));
   ObjectSetString(0,g_prefix+"EQUITY",OBJPROP_TEXT,
                   "EQUITY: "+DoubleToString(AccountEquity(),2));
   ObjectSetString(0,g_prefix+"MARGIN",OBJPROP_TEXT,
                   "FREE MARGIN: "+DoubleToString(AccountFreeMargin(),2));
   ObjectSetString(0,g_prefix+"SYMBOL",OBJPROP_TEXT,
                   "CURRENT SYMBOL: "+Symbol());
   ObjectSetString(0,g_prefix+"SPREAD",OBJPROP_TEXT,
                   "SPREAD: "+DoubleToString(spread,1)+" points");
   ObjectSetString(0,g_prefix+"ACCOUNT",OBJPROP_TEXT,
                   "ACCOUNT TYPE: "+AccountTypeText());
   ObjectSetString(0,g_prefix+"MAGIC",OBJPROP_TEXT,
                   "MAGIC: "+MagicText());
   ObjectSetString(0,g_prefix+"SCOPE",OBJPROP_TEXT,
                   "SCOPE: "+ScopeText());
   ObjectSetString(0,g_prefix+"POSITIONS",OBJPROP_TEXT,
                   "MANAGED TRADES: "+IntegerToString(matched));
   ObjectSetString(0,g_prefix+"FLOAT",OBJPROP_TEXT,
                   "FLOATING P/L: "+DoubleToString(floating,2));
   ObjectSetInteger(0,g_prefix+"FLOAT",OBJPROP_COLOR,
                    floating>=0.0 ? Q_GREEN : Q_RED);
   ObjectSetString(0,g_prefix+"COUNT",OBJPROP_TEXT,
                   "UPDATES: "+IntegerToString(g_update_count));
   ObjectSetString(0,g_prefix+"ERRORS",OBJPROP_TEXT,
                   "ERRORS: "+IntegerToString(g_error_count));

   ObjectSetString(0,g_prefix+"TOGGLE",OBJPROP_TEXT,
                   g_manager_enabled ? "STOP MANAGER" : "START MANAGER");
   ObjectSetInteger(0,g_prefix+"TOGGLE",OBJPROP_BGCOLOR,
                    g_manager_enabled ? Q_RED : Q_GREEN);

   ChartRedraw();
  }

//============================== EVENTS =====================================
int OnInit()
  {
   if(InpTrailingStartPoints<0 ||
      InpTrailingDistancePoints<=0 ||
      InpTrailingStepPoints<0 ||
      InpMinimumProfitPoints<0)
     {
      Print("Quantora Trailing Stop Manager MT4: Invalid input values.");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_manager_enabled=true;
   g_status="ACTIVE";

   BuildPanel();

   int timer=MathMax(1,InpTimerSeconds);
   EventSetTimer(timer);

   LogMessage("Initialized successfully.");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   DeletePanel();
   Comment("");
  }

void OnTick()
  {
   ManageTrailingStops(false);
  }

void OnTimer()
  {
   ManageTrailingStops(false);
   UpdatePanel();
  }

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(id!=CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam==g_prefix+"TOGGLE")
     {
      g_manager_enabled=!g_manager_enabled;
      g_status=(g_manager_enabled ? "ACTIVE" : "STOPPED");
      UpdatePanel();
     }
   else if(sparam==g_prefix+"TRAIL")
     {
      ManageTrailingStops(true);
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
