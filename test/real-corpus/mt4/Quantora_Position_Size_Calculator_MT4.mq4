//+------------------------------------------------------------------+
//|                            Quantora Position Size Calculator MT4 |
//|           Professional Trading Utility for MetaTrader 4          |
//|                                                                  |
//| Copyright © 2026 Quantora                                        |
//| https://www.mql5.com/en/users/quantora/seller                    |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2026 Quantora"
#property link      "https://www.mql5.com/en/users/quantora/seller"
#property version   "1.00"
#property strict
#property description "Professional position size and risk calculator for MetaTrader 4."
#property description "Calculates lot size from account value, risk and stop-loss distance."

enum ENUM_Q_ACCOUNT_BASE
  {
   Q_USE_BALANCE  = 0,
   Q_USE_EQUITY   = 1,
   Q_CUSTOM_VALUE = 2
  };

enum ENUM_Q_SL_MODE
  {
   Q_SL_POINTS         = 0,
   Q_SL_PRICE_DISTANCE = 1
  };

//============================== INPUTS =====================================
input string              InpRiskHeader          = "========== RISK SETTINGS ==========";
input ENUM_Q_ACCOUNT_BASE InpAccountBase         = Q_USE_BALANCE;
input double              InpCustomAccountValue  = 10000.0;
input double              InpRiskPercent         = 1.0;
input double              InpRiskMoneyOverride   = 0.0;

input string              InpSLHeader            = "========== STOP LOSS SETTINGS ==========";
input ENUM_Q_SL_MODE      InpStopLossMode        = Q_SL_POINTS;
input double              InpStopLossPoints      = 500.0;
input double              InpEntryPrice          = 0.0;
input double              InpStopLossPrice       = 0.0;

input string              InpCalcHeader          = "========== CALCULATION SETTINGS ==========";
input bool                InpUseCurrentSymbol    = true;
input string              InpCustomSymbol        = "";
input bool                InpRoundDownLot        = true;
input double              InpRewardRiskRatio     = 2.0;

input string              InpPanelHeader         = "========== DASHBOARD ==========";
input bool                InpShowPanel           = true;
input ENUM_BASE_CORNER    InpPanelCorner         = CORNER_LEFT_UPPER;
input int                 InpPanelX              = 15;
input int                 InpPanelY              = 145;
input int                 InpTimerSeconds        = 1;

//============================== BRAND COLORS ===============================
#define Q_BG       C'8,23,38'
#define Q_GOLD     C'212,175,55'
#define Q_WHITE    C'245,245,245'
#define Q_GRAY     C'169,176,184'
#define Q_GREEN    C'0,200,83'
#define Q_RED      C'255,82,82'
#define Q_BLUE     C'32,93,145'
#define Q_BORDER   C'62,76,89'

//============================== STATE ======================================
string g_prefix="QPSC4_";
string g_status="READY";
string g_symbol="";
double g_account_value=0.0;
double g_risk_money=0.0;
double g_sl_points=0.0;
double g_tick_value=0.0;
double g_tick_size=0.0;
double g_raw_lot=0.0;
double g_final_lot=0.0;
double g_margin_required=0.0;
double g_reward_money=0.0;
double g_tp_points=0.0;
int    g_error_count=0;

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

int VolumeDigits(double step)
  {
   int digits=0;
   double temp=step;

   while(digits<8 && MathAbs(temp-MathRound(temp))>1e-10)
     {
      temp*=10.0;
      digits++;
     }

   return digits;
  }

double NormalizeVolume(string symbol,double volume,bool round_down)
  {
   double min_lot=MarketInfo(symbol,MODE_MINLOT);
   double max_lot=MarketInfo(symbol,MODE_MAXLOT);
   double step=MarketInfo(symbol,MODE_LOTSTEP);

   if(step<=0.0)
      step=0.01;

   double steps=volume/step;
   double normalized_steps=(round_down ? MathFloor(steps+1e-10) : MathRound(steps));
   double result=normalized_steps*step;

   result=MathMax(min_lot,MathMin(max_lot,result));
   return NormalizeDouble(result,VolumeDigits(step));
  }

double ResolveStopLossPoints(string symbol)
  {
   double point=MarketInfo(symbol,MODE_POINT);
   if(point<=0.0)
      return 0.0;

   if(InpStopLossMode==Q_SL_POINTS)
      return MathMax(0.0,InpStopLossPoints);

   double entry=InpEntryPrice;
   if(entry<=0.0)
      entry=MarketInfo(symbol,MODE_BID);

   if(entry<=0.0 || InpStopLossPrice<=0.0)
      return 0.0;

   return MathAbs(entry-InpStopLossPrice)/point;
  }

bool CalculatePositionSize()
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

   g_account_value=AccountBaseValue();
   g_sl_points=ResolveStopLossPoints(g_symbol);

   if(g_account_value<=0.0)
     {
      g_status="INVALID ACCOUNT VALUE";
      return false;
     }

   if(g_sl_points<=0.0)
     {
      g_status="SET VALID STOP LOSS";
      g_raw_lot=0.0;
      g_final_lot=0.0;
      g_margin_required=0.0;
      g_reward_money=0.0;
      g_tp_points=0.0;
      return false;
     }

   g_risk_money=(InpRiskMoneyOverride>0.0)
                ? InpRiskMoneyOverride
                : g_account_value*MathMax(0.0,InpRiskPercent)/100.0;

   double price_distance=g_sl_points*point;
   double loss_per_lot=(price_distance/g_tick_size)*g_tick_value;

   if(loss_per_lot<=0.0)
     {
      g_status="CALCULATION ERROR";
      g_error_count++;
      return false;
     }

   g_raw_lot=g_risk_money/loss_per_lot;
   g_final_lot=NormalizeVolume(g_symbol,g_raw_lot,InpRoundDownLot);

   g_tp_points=g_sl_points*MathMax(0.0,InpRewardRiskRatio);
   g_reward_money=g_risk_money*MathMax(0.0,InpRewardRiskRatio);

   ResetLastError();
   g_margin_required=AccountFreeMarginCheck(g_symbol,OP_BUY,g_final_lot);
   if(g_margin_required<0.0)
      g_margin_required=0.0;
   else
      g_margin_required=AccountFreeMargin()-g_margin_required;

   double min_lot=MarketInfo(g_symbol,MODE_MINLOT);
   if(g_raw_lot<min_lot)
      g_status="BELOW MIN LOT - CLAMPED";
   else
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
   int w=480;
   int h=440;

   CreateRectangle(g_prefix+"BG",x,y,w,h,Q_BG,Q_GOLD);

   CreateLabel(g_prefix+"TITLE","QUANTORA",x+18,y+14,14,Q_GOLD,true);
   CreateLabel(g_prefix+"SUB","POSITION SIZE CALCULATOR",x+18,y+38,11,Q_WHITE,true);
   CreateLabel(g_prefix+"VER","MT4  v1.00",x+390,y+18,9,Q_GRAY,false);

   CreateLabel(g_prefix+"STATUS","STATUS: READY",x+18,y+72,10,Q_GREEN,true);

   CreateLabel(g_prefix+"BASE","ACCOUNT BASE: 0.00",x+18,y+104,10,Q_WHITE,false);
   CreateLabel(g_prefix+"TYPE","BASE TYPE: "+AccountBaseText(),x+250,y+104,10,Q_GRAY,false);

   CreateLabel(g_prefix+"SYMBOL","SYMBOL: "+SelectedSymbol(),x+18,y+132,10,Q_WHITE,false);
   CreateLabel(g_prefix+"SPREAD","SPREAD: 0.0 points",x+250,y+132,10,Q_WHITE,false);

   CreateLabel(g_prefix+"RISKPC","RISK: 0.00 %",x+18,y+160,10,Q_GRAY,false);
   CreateLabel(g_prefix+"RISKM","RISK MONEY: 0.00",x+250,y+160,10,Q_RED,true);

   CreateLabel(g_prefix+"SL","STOP LOSS: 0 points",x+18,y+198,10,Q_WHITE,true);
   CreateLabel(g_prefix+"TP","TARGET: 0 points",x+250,y+198,10,Q_WHITE,true);

   CreateLabel(g_prefix+"TICKV","TICK VALUE: 0.00",x+18,y+228,10,Q_GRAY,false);
   CreateLabel(g_prefix+"TICKS","TICK SIZE: 0.00000",x+250,y+228,10,Q_GRAY,false);

   CreateLabel(g_prefix+"RAW","RAW LOT: 0.00",x+18,y+266,11,Q_GRAY,true);
   CreateLabel(g_prefix+"LOT","RECOMMENDED LOT: 0.00",x+18,y+300,14,Q_GOLD,true);

   CreateLabel(g_prefix+"MARGIN","EST. MARGIN: 0.00",x+18,y+338,10,Q_WHITE,false);
   CreateLabel(g_prefix+"REWARD","POTENTIAL REWARD: 0.00",x+250,y+338,10,Q_GREEN,false);

   CreateButton(g_prefix+"REFRESH","RECALCULATE",x+18,y+372,215,38,Q_BLUE);
   CreateButton(g_prefix+"RESET","RESET STATUS",x+247,y+372,215,38,Q_BORDER);

   CreateLabel(g_prefix+"FOOT","mql5.com/en/users/quantora/seller",x+18,y+418,9,Q_GOLD,false);

   ChartRedraw();
  }

void UpdatePanel()
  {
   if(!InpShowPanel)
      return;

   CalculatePositionSize();

   double spread=0.0;
   double point=MarketInfo(g_symbol,MODE_POINT);
   double ask=MarketInfo(g_symbol,MODE_ASK);
   double bid=MarketInfo(g_symbol,MODE_BID);

   if(point>0.0)
      spread=(ask-bid)/point;

   color status_color=Q_GREEN;

   if(StringFind(g_status,"ERROR")>=0 ||
      StringFind(g_status,"INVALID")>=0)
      status_color=Q_RED;
   else if(StringFind(g_status,"SET VALID")>=0 ||
           StringFind(g_status,"CLAMPED")>=0)
      status_color=Q_GOLD;

   ObjectSetString(0,g_prefix+"STATUS",OBJPROP_TEXT,"STATUS: "+g_status);
   ObjectSetInteger(0,g_prefix+"STATUS",OBJPROP_COLOR,status_color);

   ObjectSetString(0,g_prefix+"BASE",OBJPROP_TEXT,
                   "ACCOUNT BASE: "+DoubleToString(g_account_value,2));
   ObjectSetString(0,g_prefix+"TYPE",OBJPROP_TEXT,
                   "BASE TYPE: "+AccountBaseText());
   ObjectSetString(0,g_prefix+"SYMBOL",OBJPROP_TEXT,
                   "SYMBOL: "+g_symbol);
   ObjectSetString(0,g_prefix+"SPREAD",OBJPROP_TEXT,
                   "SPREAD: "+DoubleToString(spread,1)+" points");

   ObjectSetString(0,g_prefix+"RISKPC",OBJPROP_TEXT,
                   "RISK: "+DoubleToString(InpRiskPercent,2)+" %");
   ObjectSetString(0,g_prefix+"RISKM",OBJPROP_TEXT,
                   "RISK MONEY: "+DoubleToString(g_risk_money,2));

   ObjectSetString(0,g_prefix+"SL",OBJPROP_TEXT,
                   "STOP LOSS: "+DoubleToString(g_sl_points,1)+" points");
   ObjectSetString(0,g_prefix+"TP",OBJPROP_TEXT,
                   "TARGET: "+DoubleToString(g_tp_points,1)+" points");

   ObjectSetString(0,g_prefix+"TICKV",OBJPROP_TEXT,
                   "TICK VALUE: "+DoubleToString(g_tick_value,4));
   ObjectSetString(0,g_prefix+"TICKS",OBJPROP_TEXT,
                   "TICK SIZE: "+DoubleToString(g_tick_size,8));

   ObjectSetString(0,g_prefix+"RAW",OBJPROP_TEXT,
                   "RAW LOT: "+DoubleToString(g_raw_lot,4));
   ObjectSetString(0,g_prefix+"LOT",OBJPROP_TEXT,
                   "RECOMMENDED LOT: "+DoubleToString(g_final_lot,4));

   ObjectSetString(0,g_prefix+"MARGIN",OBJPROP_TEXT,
                   "EST. MARGIN: "+DoubleToString(g_margin_required,2));
   ObjectSetString(0,g_prefix+"REWARD",OBJPROP_TEXT,
                   "POTENTIAL REWARD: "+DoubleToString(g_reward_money,2));

   ChartRedraw();
  }

//============================== EVENTS =====================================
int OnInit()
  {
   if(InpRiskPercent<0.0 ||
      InpRiskMoneyOverride<0.0 ||
      InpStopLossPoints<0.0 ||
      InpRewardRiskRatio<0.0)
     {
      Print("Quantora Position Size Calculator MT4: Invalid input values.");
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
