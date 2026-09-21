//+------------------------------------------------------------------+
//|                                     Quantora Risk Calculator MT4 |
//|           Professional Trading Utility for MetaTrader 4          |
//|                                                                  |
//| Copyright © 2026 Quantora                                        |
//| https://www.mql5.com/en/users/quantora/seller                    |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2026 Quantora"
#property link      "https://www.mql5.com/en/users/quantora/seller"
#property version   "1.00"
#property strict
#property description "Professional trade risk and reward calculator for MetaTrader 4."
#property description "Calculates money risk, risk percentage, potential reward and margin."

enum ENUM_Q_ACCOUNT_BASE
  {
   Q_USE_BALANCE  = 0,
   Q_USE_EQUITY   = 1,
   Q_CUSTOM_VALUE = 2
  };

enum ENUM_Q_TRADE_DIRECTION
  {
   Q_BUY_TRADE  = 0,
   Q_SELL_TRADE = 1
  };

//============================== INPUTS =====================================
input string                 InpAccountHeader       = "========== ACCOUNT SETTINGS ==========";
input ENUM_Q_ACCOUNT_BASE    InpAccountBase         = Q_USE_BALANCE;
input double                 InpCustomAccountValue  = 10000.0;

input string                 InpTradeHeader         = "========== TRADE SETTINGS ==========";
input bool                   InpUseCurrentSymbol    = true;
input string                 InpCustomSymbol        = "";
input ENUM_Q_TRADE_DIRECTION InpTradeDirection      = Q_BUY_TRADE;
input double                 InpLotSize             = 0.10;
input double                 InpEntryPrice          = 0.0;
input double                 InpStopLossPrice       = 0.0;
input double                 InpTakeProfitPrice     = 0.0;

input string                 InpRiskHeader          = "========== RISK LEVELS ==========";
input double                 InpExcellentRiskMax    = 0.50;
input double                 InpSafeRiskMax         = 1.00;
input double                 InpModerateRiskMax     = 2.00;
input double                 InpAggressiveRiskMax   = 3.00;
input double                 InpMarginWarningPct    = 50.0;

input string                 InpPanelHeader         = "========== DASHBOARD ==========";
input bool                   InpShowPanel           = true;
input ENUM_BASE_CORNER       InpPanelCorner         = CORNER_LEFT_UPPER;
input int                    InpPanelX              = 15;
input int                    InpPanelY              = 145;
input int                    InpTimerSeconds        = 1;

//============================== BRAND COLORS ===============================
#define Q_BG       C'8,23,38'
#define Q_GOLD     C'212,175,55'
#define Q_WHITE    C'245,245,245'
#define Q_GRAY     C'169,176,184'
#define Q_GREEN    C'0,200,83'
#define Q_YELLOW   C'255,193,7'
#define Q_ORANGE   C'255,152,0'
#define Q_RED      C'255,82,82'
#define Q_BLUE     C'32,93,145'
#define Q_BORDER   C'62,76,89'

//============================== STATE ======================================
string g_prefix="QRC4_";
string g_status="READY";
string g_symbol="";
string g_risk_level="NOT CALCULATED";
string g_margin_status="OK";

double g_account_value=0.0;
double g_entry=0.0;
double g_stop=0.0;
double g_target=0.0;
double g_sl_points=0.0;
double g_tp_points=0.0;
double g_tick_value=0.0;
double g_tick_size=0.0;
double g_money_risk=0.0;
double g_risk_percent=0.0;
double g_potential_profit=0.0;
double g_reward_risk=0.0;
double g_margin_required=0.0;
double g_margin_pct_free=0.0;
double g_position_value=0.0;

int g_error_count=0;

//============================== HELPERS ====================================
string SelectedSymbol()
  {
   if(InpUseCurrentSymbol || StringLen(InpCustomSymbol)==0)
      return Symbol();

   return InpCustomSymbol;
  }

double AccountBaseValue()
  {
   if(InpAccountBase==Q_USE_EQUITY)
      return AccountEquity();

   if(InpAccountBase==Q_CUSTOM_VALUE)
      return MathMax(0.0,InpCustomAccountValue);

   return AccountBalance();
  }

string AccountBaseText()
  {
   if(InpAccountBase==Q_USE_EQUITY)
      return "EQUITY";

   if(InpAccountBase==Q_CUSTOM_VALUE)
      return "CUSTOM VALUE";

   return "BALANCE";
  }

string DirectionText()
  {
   return (InpTradeDirection==Q_BUY_TRADE ? "BUY" : "SELL");
  }

double DefaultEntryPrice(string symbol)
  {
   if(InpTradeDirection==Q_BUY_TRADE)
      return MarketInfo(symbol,MODE_ASK);

   return MarketInfo(symbol,MODE_BID);
  }

color RiskLevelColor()
  {
   if(g_risk_level=="EXCELLENT" || g_risk_level=="SAFE")
      return Q_GREEN;

   if(g_risk_level=="MODERATE")
      return Q_YELLOW;

   if(g_risk_level=="AGGRESSIVE")
      return Q_ORANGE;

   return Q_RED;
  }

void ClassifyRisk()
  {
   if(g_risk_percent<=InpExcellentRiskMax)
      g_risk_level="EXCELLENT";
   else if(g_risk_percent<=InpSafeRiskMax)
      g_risk_level="SAFE";
   else if(g_risk_percent<=InpModerateRiskMax)
      g_risk_level="MODERATE";
   else if(g_risk_percent<=InpAggressiveRiskMax)
      g_risk_level="AGGRESSIVE";
   else
      g_risk_level="DANGEROUS";
  }

bool ValidateTradeGeometry()
  {
   if(InpTradeDirection==Q_BUY_TRADE)
     {
      if(g_stop>=g_entry)
        {
         g_status="BUY SL MUST BE BELOW ENTRY";
         return false;
        }

      if(g_target>0.0 && g_target<=g_entry)
        {
         g_status="BUY TP MUST BE ABOVE ENTRY";
         return false;
        }
     }
   else
     {
      if(g_stop<=g_entry)
        {
         g_status="SELL SL MUST BE ABOVE ENTRY";
         return false;
        }

      if(g_target>0.0 && g_target>=g_entry)
        {
         g_status="SELL TP MUST BE BELOW ENTRY";
         return false;
        }
     }

   return true;
  }

bool CalculateRisk()
  {
   g_symbol=SelectedSymbol();

   double point=MarketInfo(g_symbol,MODE_POINT);
   g_tick_value=MarketInfo(g_symbol,MODE_TICKVALUE);
   g_tick_size=MarketInfo(g_symbol,MODE_TICKSIZE);

   if(point<=0.0 || g_tick_value<=0.0 || g_tick_size<=0.0)
     {
      g_status="INVALID SYMBOL DATA";
      g_error_count++;
      return false;
     }

   if(InpLotSize<=0.0)
     {
      g_status="SET VALID LOT SIZE";
      return false;
     }

   g_account_value=AccountBaseValue();

   if(g_account_value<=0.0)
     {
      g_status="INVALID ACCOUNT VALUE";
      return false;
     }

   g_entry=(InpEntryPrice>0.0 ? InpEntryPrice : DefaultEntryPrice(g_symbol));
   g_stop=InpStopLossPrice;
   g_target=InpTakeProfitPrice;

   if(g_entry<=0.0 || g_stop<=0.0)
     {
      g_status="SET ENTRY AND STOP LOSS";
      return false;
     }

   if(!ValidateTradeGeometry())
      return false;

   g_sl_points=MathAbs(g_entry-g_stop)/point;
   g_tp_points=(g_target>0.0 ? MathAbs(g_target-g_entry)/point : 0.0);

   double sl_price_distance=MathAbs(g_entry-g_stop);
   double tp_price_distance=(g_target>0.0 ? MathAbs(g_target-g_entry) : 0.0);

   double loss_per_lot=(sl_price_distance/g_tick_size)*g_tick_value;
   double profit_per_lot=(tp_price_distance/g_tick_size)*g_tick_value;

   g_money_risk=loss_per_lot*InpLotSize;
   g_potential_profit=profit_per_lot*InpLotSize;
   g_risk_percent=(g_account_value>0.0 ? (g_money_risk/g_account_value)*100.0 : 0.0);
   g_reward_risk=(g_money_risk>0.0 ? g_potential_profit/g_money_risk : 0.0);

   ClassifyRisk();

   double free_before=AccountFreeMargin();
   ResetLastError();

   int cmd=(InpTradeDirection==Q_BUY_TRADE ? OP_BUY : OP_SELL);
   double free_after=AccountFreeMarginCheck(g_symbol,cmd,InpLotSize);

   if(free_after<0.0)
      g_margin_required=0.0;
   else
      g_margin_required=MathMax(0.0,free_before-free_after);

   g_margin_pct_free=(free_before>0.0 ? (g_margin_required/free_before)*100.0 : 0.0);
   g_margin_status=(g_margin_pct_free>=InpMarginWarningPct ? "WARNING" : "OK");

   double contract_size=MarketInfo(g_symbol,MODE_LOTSIZE);
   g_position_value=contract_size*InpLotSize*g_entry;

   g_status="CALCULATION READY";
   return true;
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
      string name=ObjectName(i);

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
   int w=500;
   int h=500;

   CreateRectangle(g_prefix+"BG",x,y,w,h,Q_BG,Q_GOLD);

   CreateLabel(g_prefix+"TITLE","QUANTORA",x+18,y+14,14,Q_GOLD,true);
   CreateLabel(g_prefix+"SUB","RISK CALCULATOR",x+18,y+38,11,Q_WHITE,true);
   CreateLabel(g_prefix+"VER","MT4  v1.00",x+410,y+18,9,Q_GRAY,false);

   CreateLabel(g_prefix+"STATUS","STATUS: READY",x+18,y+72,10,Q_GREEN,true);

   CreateLabel(g_prefix+"BASE","ACCOUNT BASE: 0.00",x+18,y+104,10,Q_WHITE,false);
   CreateLabel(g_prefix+"TYPE","BASE TYPE: "+AccountBaseText(),x+260,y+104,10,Q_GRAY,false);

   CreateLabel(g_prefix+"SYMBOL","SYMBOL: "+SelectedSymbol(),x+18,y+132,10,Q_WHITE,false);
   CreateLabel(g_prefix+"DIR","DIRECTION: "+DirectionText(),x+260,y+132,10,Q_WHITE,false);

   CreateLabel(g_prefix+"LOT","LOT SIZE: 0.00",x+18,y+160,10,Q_WHITE,false);
   CreateLabel(g_prefix+"SPREAD","SPREAD: 0.0 points",x+260,y+160,10,Q_GRAY,false);

   CreateLabel(g_prefix+"ENTRY","ENTRY: 0.00000",x+18,y+196,10,Q_WHITE,false);
   CreateLabel(g_prefix+"SLPRICE","STOP LOSS: 0.00000",x+260,y+196,10,Q_WHITE,false);
   CreateLabel(g_prefix+"TPPRICE","TAKE PROFIT: 0.00000",x+18,y+224,10,Q_WHITE,false);

   CreateLabel(g_prefix+"SLPTS","SL DISTANCE: 0 points",x+18,y+260,10,Q_GRAY,false);
   CreateLabel(g_prefix+"TPPTS","TP DISTANCE: 0 points",x+260,y+260,10,Q_GRAY,false);

   CreateLabel(g_prefix+"RISK","MONEY RISK: 0.00",x+18,y+296,11,Q_RED,true);
   CreateLabel(g_prefix+"RISKPC","RISK: 0.00 %",x+260,y+296,11,Q_RED,true);

   CreateLabel(g_prefix+"PROFIT","POTENTIAL PROFIT: 0.00",x+18,y+330,10,Q_GREEN,true);
   CreateLabel(g_prefix+"RR","REWARD / RISK: 0.00",x+260,y+330,10,Q_GOLD,true);

   CreateLabel(g_prefix+"LEVEL","RISK LEVEL: NOT CALCULATED",x+18,y+366,12,Q_GOLD,true);

   CreateLabel(g_prefix+"MARGIN","MARGIN REQUIRED: 0.00",x+18,y+400,10,Q_WHITE,false);
   CreateLabel(g_prefix+"MARGINPC","MARGIN / FREE: 0.00 %",x+260,y+400,10,Q_WHITE,false);

   CreateLabel(g_prefix+"MSTATUS","MARGIN STATUS: OK",x+18,y+428,10,Q_GREEN,true);
   CreateLabel(g_prefix+"VALUE","POSITION VALUE: 0.00",x+260,y+428,10,Q_GRAY,false);

   CreateButton(g_prefix+"REFRESH","RECALCULATE",x+18,y+454,225,34,Q_BLUE);
   CreateButton(g_prefix+"RESET","RESET STATUS",x+257,y+454,225,34,Q_BORDER);

   CreateLabel(g_prefix+"FOOT","mql5.com/en/users/quantora/seller",x+18,y+490,9,Q_GOLD,false);

   ChartRedraw();
  }

void UpdatePanel()
  {
   if(!InpShowPanel)
      return;

   CalculateRisk();

   double point=MarketInfo(g_symbol,MODE_POINT);
   double ask=MarketInfo(g_symbol,MODE_ASK);
   double bid=MarketInfo(g_symbol,MODE_BID);
   double spread=(point>0.0 ? (ask-bid)/point : 0.0);
   int digits=(int)MarketInfo(g_symbol,MODE_DIGITS);

   color status_color=Q_GREEN;

   if(StringFind(g_status,"INVALID")>=0)
      status_color=Q_RED;
   else if(StringFind(g_status,"SET ")>=0 ||
           StringFind(g_status,"MUST BE")>=0)
      status_color=Q_GOLD;

   ObjectSetString(0,g_prefix+"STATUS",OBJPROP_TEXT,"STATUS: "+g_status);
   ObjectSetInteger(0,g_prefix+"STATUS",OBJPROP_COLOR,status_color);

   ObjectSetString(0,g_prefix+"BASE",OBJPROP_TEXT,
                   "ACCOUNT BASE: "+DoubleToString(g_account_value,2));
   ObjectSetString(0,g_prefix+"TYPE",OBJPROP_TEXT,
                   "BASE TYPE: "+AccountBaseText());

   ObjectSetString(0,g_prefix+"SYMBOL",OBJPROP_TEXT,
                   "SYMBOL: "+g_symbol);
   ObjectSetString(0,g_prefix+"DIR",OBJPROP_TEXT,
                   "DIRECTION: "+DirectionText());

   ObjectSetString(0,g_prefix+"LOT",OBJPROP_TEXT,
                   "LOT SIZE: "+DoubleToString(InpLotSize,2));
   ObjectSetString(0,g_prefix+"SPREAD",OBJPROP_TEXT,
                   "SPREAD: "+DoubleToString(spread,1)+" points");

   ObjectSetString(0,g_prefix+"ENTRY",OBJPROP_TEXT,
                   "ENTRY: "+DoubleToString(g_entry,digits));
   ObjectSetString(0,g_prefix+"SLPRICE",OBJPROP_TEXT,
                   "STOP LOSS: "+DoubleToString(g_stop,digits));
   ObjectSetString(0,g_prefix+"TPPRICE",OBJPROP_TEXT,
                   "TAKE PROFIT: "+DoubleToString(g_target,digits));

   ObjectSetString(0,g_prefix+"SLPTS",OBJPROP_TEXT,
                   "SL DISTANCE: "+DoubleToString(g_sl_points,1)+" points");
   ObjectSetString(0,g_prefix+"TPPTS",OBJPROP_TEXT,
                   "TP DISTANCE: "+DoubleToString(g_tp_points,1)+" points");

   ObjectSetString(0,g_prefix+"RISK",OBJPROP_TEXT,
                   "MONEY RISK: "+DoubleToString(g_money_risk,2));
   ObjectSetString(0,g_prefix+"RISKPC",OBJPROP_TEXT,
                   "RISK: "+DoubleToString(g_risk_percent,2)+" %");

   ObjectSetString(0,g_prefix+"PROFIT",OBJPROP_TEXT,
                   "POTENTIAL PROFIT: "+DoubleToString(g_potential_profit,2));
   ObjectSetString(0,g_prefix+"RR",OBJPROP_TEXT,
                   "REWARD / RISK: "+DoubleToString(g_reward_risk,2));

   ObjectSetString(0,g_prefix+"LEVEL",OBJPROP_TEXT,
                   "RISK LEVEL: "+g_risk_level);
   ObjectSetInteger(0,g_prefix+"LEVEL",OBJPROP_COLOR,RiskLevelColor());

   ObjectSetString(0,g_prefix+"MARGIN",OBJPROP_TEXT,
                   "MARGIN REQUIRED: "+DoubleToString(g_margin_required,2));
   ObjectSetString(0,g_prefix+"MARGINPC",OBJPROP_TEXT,
                   "MARGIN / FREE: "+DoubleToString(g_margin_pct_free,2)+" %");

   ObjectSetString(0,g_prefix+"MSTATUS",OBJPROP_TEXT,
                   "MARGIN STATUS: "+g_margin_status);
   ObjectSetInteger(0,g_prefix+"MSTATUS",OBJPROP_COLOR,
                    g_margin_status=="OK" ? Q_GREEN : Q_RED);

   ObjectSetString(0,g_prefix+"VALUE",OBJPROP_TEXT,
                   "POSITION VALUE: "+DoubleToString(g_position_value,2));

   ChartRedraw();
  }

//============================== EVENTS =====================================
int OnInit()
  {
   if(InpLotSize<=0.0 ||
      InpExcellentRiskMax<0.0 ||
      InpSafeRiskMax<InpExcellentRiskMax ||
      InpModerateRiskMax<InpSafeRiskMax ||
      InpAggressiveRiskMax<InpModerateRiskMax ||
      InpMarginWarningPct<0.0)
     {
      Print("Quantora Risk Calculator MT4: Invalid input values.");
      return INIT_PARAMETERS_INCORRECT;
     }

   BuildPanel();
   UpdatePanel();

   EventSetTimer(MathMax(1,InpTimerSeconds));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   DeletePanel();
  }

void OnTick()
  {
   UpdatePanel();
  }

void OnTimer()
  {
   UpdatePanel();
  }

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(id!=CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam==g_prefix+"REFRESH")
     {
      g_status="RECALCULATING";
      UpdatePanel();
     }
   else if(sparam==g_prefix+"RESET")
     {
      g_error_count=0;
      g_status="READY";
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
