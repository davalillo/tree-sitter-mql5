//+------------------------------------------------------------------+
//|                                   Quantora Margin Calculator MT4 |
//|           Professional Trading Utility for MetaTrader 4          |
//|                                                                  |
//| Copyright © 2026 Quantora                                        |
//| https://www.mql5.com/en/users/quantora/seller                    |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2026 Quantora"
#property link      "https://www.mql5.com/en/users/quantora/seller"
#property version   "1.00"
#property strict
#property description "Professional margin calculator for MetaTrader 4."
#property description "Calculates required margin, free margin impact and margin safety."

enum ENUM_Q_TRADE_DIRECTION
  {
   Q_BUY_TRADE  = 0,
   Q_SELL_TRADE = 1
  };

//============================== INPUTS =====================================
input string                 InpTradeHeader          = "========== TRADE SETTINGS ==========";
input bool                   InpUseCurrentSymbol     = true;
input string                 InpCustomSymbol         = "";
input ENUM_Q_TRADE_DIRECTION InpTradeDirection       = Q_BUY_TRADE;
input double                 InpLotSize              = 0.10;
input double                 InpCustomPrice          = 0.0;

input string                 InpSafetyHeader         = "========== SAFETY SETTINGS ==========";
input double                 InpSafeMarginUsePct     = 20.0;
input double                 InpWarningMarginUsePct  = 40.0;
input double                 InpDangerMarginUsePct   = 70.0;

input string                 InpPanelHeader          = "========== DASHBOARD ==========";
input bool                   InpShowPanel            = true;
input ENUM_BASE_CORNER       InpPanelCorner          = CORNER_LEFT_UPPER;
input int                    InpPanelX               = 15;
input int                    InpPanelY               = 145;
input int                    InpTimerSeconds         = 1;

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
string g_prefix="QMC4_";
string g_status="READY";
string g_symbol="";
string g_margin_level_text="NOT CALCULATED";

double g_price=0.0;
double g_required_margin=0.0;
double g_free_margin_before=0.0;
double g_free_margin_after=0.0;
double g_margin_use_pct=0.0;
double g_margin_level_after=0.0;
double g_contract_size=0.0;
double g_position_value=0.0;
double g_tick_value=0.0;
double g_tick_size=0.0;
double g_volume_min=0.0;
double g_volume_max=0.0;
double g_volume_step=0.0;

int g_error_count=0;

//============================== HELPERS ====================================
string SelectedSymbol()
  {
   if(InpUseCurrentSymbol || StringLen(InpCustomSymbol)==0)
      return Symbol();

   return InpCustomSymbol;
  }

string DirectionText()
  {
   return (InpTradeDirection==Q_BUY_TRADE ? "BUY" : "SELL");
  }

double ResolvePrice(string symbol)
  {
   if(InpCustomPrice>0.0)
      return InpCustomPrice;

   if(InpTradeDirection==Q_BUY_TRADE)
      return MarketInfo(symbol,MODE_ASK);

   return MarketInfo(symbol,MODE_BID);
  }

color MarginLevelColor()
  {
   if(g_margin_level_text=="SAFE")
      return Q_GREEN;

   if(g_margin_level_text=="MODERATE")
      return Q_YELLOW;

   if(g_margin_level_text=="WARNING")
      return Q_ORANGE;

   return Q_RED;
  }

void ClassifyMarginUse()
  {
   if(g_margin_use_pct<=InpSafeMarginUsePct)
      g_margin_level_text="SAFE";
   else if(g_margin_use_pct<=InpWarningMarginUsePct)
      g_margin_level_text="MODERATE";
   else if(g_margin_use_pct<=InpDangerMarginUsePct)
      g_margin_level_text="WARNING";
   else
      g_margin_level_text="DANGEROUS";
  }

bool CalculateMargin()
  {
   g_symbol=SelectedSymbol();

   double point=MarketInfo(g_symbol,MODE_POINT);
   if(point<=0.0)
     {
      g_status="SYMBOL NOT AVAILABLE";
      g_error_count++;
      return false;
     }

   if(InpLotSize<=0.0)
     {
      g_status="SET VALID LOT SIZE";
      return false;
     }

   g_price=ResolvePrice(g_symbol);

   if(g_price<=0.0)
     {
      g_status="INVALID PRICE";
      g_error_count++;
      return false;
     }

   g_contract_size=MarketInfo(g_symbol,MODE_LOTSIZE);
   g_tick_value=MarketInfo(g_symbol,MODE_TICKVALUE);
   g_tick_size=MarketInfo(g_symbol,MODE_TICKSIZE);
   g_volume_min=MarketInfo(g_symbol,MODE_MINLOT);
   g_volume_max=MarketInfo(g_symbol,MODE_MAXLOT);
   g_volume_step=MarketInfo(g_symbol,MODE_LOTSTEP);

   int cmd=(InpTradeDirection==Q_BUY_TRADE ? OP_BUY : OP_SELL);

   g_free_margin_before=AccountFreeMargin();

   ResetLastError();
   double free_after=AccountFreeMarginCheck(g_symbol,cmd,InpLotSize);

   if(free_after<0.0)
     {
      g_required_margin=0.0;
      g_free_margin_after=free_after;
      g_margin_use_pct=0.0;
      g_margin_level_after=0.0;
      g_status="INSUFFICIENT FREE MARGIN";
      g_margin_level_text="DANGEROUS";
      g_error_count++;
      return false;
     }

   g_free_margin_after=free_after;
   g_required_margin=MathMax(0.0,g_free_margin_before-g_free_margin_after);

   if(g_free_margin_before>0.0)
      g_margin_use_pct=(g_required_margin/g_free_margin_before)*100.0;
   else
      g_margin_use_pct=0.0;

   double equity=AccountEquity();
   double current_margin=AccountMargin();
   double total_margin_after=current_margin+g_required_margin;

   if(total_margin_after>0.0)
      g_margin_level_after=(equity/total_margin_after)*100.0;
   else
      g_margin_level_after=0.0;

   g_position_value=g_contract_size*InpLotSize*g_price;

   ClassifyMarginUse();
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
   int h=485;

   CreateRectangle(g_prefix+"BG",x,y,w,h,Q_BG,Q_GOLD);

   CreateLabel(g_prefix+"TITLE","QUANTORA",x+18,y+14,14,Q_GOLD,true);
   CreateLabel(g_prefix+"SUB","MARGIN CALCULATOR",x+18,y+38,11,Q_WHITE,true);
   CreateLabel(g_prefix+"VER","MT4  v1.00",x+410,y+18,9,Q_GRAY,false);

   CreateLabel(g_prefix+"STATUS","STATUS: READY",x+18,y+72,10,Q_GREEN,true);

   CreateLabel(g_prefix+"SYMBOL","SYMBOL: "+SelectedSymbol(),x+18,y+104,10,Q_WHITE,false);
   CreateLabel(g_prefix+"DIR","DIRECTION: "+DirectionText(),x+260,y+104,10,Q_WHITE,false);

   CreateLabel(g_prefix+"LOT","LOT SIZE: 0.00",x+18,y+132,10,Q_WHITE,false);
   CreateLabel(g_prefix+"PRICE","PRICE: 0.00000",x+260,y+132,10,Q_WHITE,false);

   CreateLabel(g_prefix+"BAL","BALANCE: 0.00",x+18,y+168,10,Q_GRAY,false);
   CreateLabel(g_prefix+"EQUITY","EQUITY: 0.00",x+260,y+168,10,Q_GRAY,false);

   CreateLabel(g_prefix+"FREEB","FREE MARGIN BEFORE: 0.00",x+18,y+198,10,Q_WHITE,false);
   CreateLabel(g_prefix+"FREEA","FREE MARGIN AFTER: 0.00",x+260,y+198,10,Q_WHITE,false);

   CreateLabel(g_prefix+"REQ","REQUIRED MARGIN: 0.00",x+18,y+236,12,Q_GOLD,true);
   CreateLabel(g_prefix+"USE","MARGIN USE: 0.00 %",x+260,y+236,11,Q_WHITE,true);

   CreateLabel(g_prefix+"LEVEL","SAFETY LEVEL: NOT CALCULATED",x+18,y+272,12,Q_GOLD,true);
   CreateLabel(g_prefix+"MLVL","MARGIN LEVEL AFTER: 0.00 %",x+260,y+272,10,Q_WHITE,false);

   CreateLabel(g_prefix+"VALUE","POSITION VALUE: 0.00",x+18,y+310,10,Q_WHITE,false);
   CreateLabel(g_prefix+"CONTRACT","CONTRACT SIZE: 0.00",x+260,y+310,10,Q_GRAY,false);

   CreateLabel(g_prefix+"TICKV","TICK VALUE: 0.00",x+18,y+338,10,Q_GRAY,false);
   CreateLabel(g_prefix+"TICKS","TICK SIZE: 0.00000",x+260,y+338,10,Q_GRAY,false);

   CreateLabel(g_prefix+"MINMAX","MIN / MAX LOT: 0.00 / 0.00",x+18,y+366,10,Q_GRAY,false);
   CreateLabel(g_prefix+"STEP","LOT STEP: 0.00",x+260,y+366,10,Q_GRAY,false);

   CreateButton(g_prefix+"REFRESH","RECALCULATE",x+18,y+406,225,38,Q_BLUE);
   CreateButton(g_prefix+"RESET","RESET STATUS",x+257,y+406,225,38,Q_BORDER);

   CreateLabel(g_prefix+"FOOT","mql5.com/en/users/quantora/seller",x+18,y+462,9,Q_GOLD,false);

   ChartRedraw();
  }

void UpdatePanel()
  {
   if(!InpShowPanel)
      return;

   CalculateMargin();

   int digits=(int)MarketInfo(g_symbol,MODE_DIGITS);

   color status_color=Q_GREEN;

   if(StringFind(g_status,"FAILED")>=0 ||
      StringFind(g_status,"INVALID")>=0 ||
      StringFind(g_status,"INSUFFICIENT")>=0 ||
      StringFind(g_status,"NOT AVAILABLE")>=0)
      status_color=Q_RED;
   else if(StringFind(g_status,"SET VALID")>=0)
      status_color=Q_GOLD;

   ObjectSetString(0,g_prefix+"STATUS",OBJPROP_TEXT,"STATUS: "+g_status);
   ObjectSetInteger(0,g_prefix+"STATUS",OBJPROP_COLOR,status_color);

   ObjectSetString(0,g_prefix+"SYMBOL",OBJPROP_TEXT,"SYMBOL: "+g_symbol);
   ObjectSetString(0,g_prefix+"DIR",OBJPROP_TEXT,"DIRECTION: "+DirectionText());

   ObjectSetString(0,g_prefix+"LOT",OBJPROP_TEXT,
                   "LOT SIZE: "+DoubleToString(InpLotSize,2));
   ObjectSetString(0,g_prefix+"PRICE",OBJPROP_TEXT,
                   "PRICE: "+DoubleToString(g_price,digits));

   ObjectSetString(0,g_prefix+"BAL",OBJPROP_TEXT,
                   "BALANCE: "+DoubleToString(AccountBalance(),2));
   ObjectSetString(0,g_prefix+"EQUITY",OBJPROP_TEXT,
                   "EQUITY: "+DoubleToString(AccountEquity(),2));

   ObjectSetString(0,g_prefix+"FREEB",OBJPROP_TEXT,
                   "FREE MARGIN BEFORE: "+DoubleToString(g_free_margin_before,2));
   ObjectSetString(0,g_prefix+"FREEA",OBJPROP_TEXT,
                   "FREE MARGIN AFTER: "+DoubleToString(g_free_margin_after,2));
   ObjectSetInteger(0,g_prefix+"FREEA",OBJPROP_COLOR,
                    g_free_margin_after>=0.0 ? Q_GREEN : Q_RED);

   ObjectSetString(0,g_prefix+"REQ",OBJPROP_TEXT,
                   "REQUIRED MARGIN: "+DoubleToString(g_required_margin,2));
   ObjectSetString(0,g_prefix+"USE",OBJPROP_TEXT,
                   "MARGIN USE: "+DoubleToString(g_margin_use_pct,2)+" %");

   ObjectSetString(0,g_prefix+"LEVEL",OBJPROP_TEXT,
                   "SAFETY LEVEL: "+g_margin_level_text);
   ObjectSetInteger(0,g_prefix+"LEVEL",OBJPROP_COLOR,MarginLevelColor());

   ObjectSetString(0,g_prefix+"MLVL",OBJPROP_TEXT,
                   "MARGIN LEVEL AFTER: "+DoubleToString(g_margin_level_after,2)+" %");

   ObjectSetString(0,g_prefix+"VALUE",OBJPROP_TEXT,
                   "POSITION VALUE: "+DoubleToString(g_position_value,2));
   ObjectSetString(0,g_prefix+"CONTRACT",OBJPROP_TEXT,
                   "CONTRACT SIZE: "+DoubleToString(g_contract_size,2));

   ObjectSetString(0,g_prefix+"TICKV",OBJPROP_TEXT,
                   "TICK VALUE: "+DoubleToString(g_tick_value,4));
   ObjectSetString(0,g_prefix+"TICKS",OBJPROP_TEXT,
                   "TICK SIZE: "+DoubleToString(g_tick_size,8));

   ObjectSetString(0,g_prefix+"MINMAX",OBJPROP_TEXT,
                   "MIN / MAX LOT: "+DoubleToString(g_volume_min,2)+
                   " / "+DoubleToString(g_volume_max,2));
   ObjectSetString(0,g_prefix+"STEP",OBJPROP_TEXT,
                   "LOT STEP: "+DoubleToString(g_volume_step,4));

   ChartRedraw();
  }

//============================== EVENTS =====================================
int OnInit()
  {
   if(InpLotSize<=0.0 ||
      InpSafeMarginUsePct<0.0 ||
      InpWarningMarginUsePct<InpSafeMarginUsePct ||
      InpDangerMarginUsePct<InpWarningMarginUsePct)
     {
      Print("Quantora Margin Calculator MT4: Invalid input values.");
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
