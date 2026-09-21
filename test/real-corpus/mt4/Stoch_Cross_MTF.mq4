//+------------------------------------------------------------------+
//|                                              Stoch_Cross_MTF.mq4 |
//|                                          Copyright 2026, lubexfx |
//|                            https://www.mql5.com/en/users/lubexfx |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, lubexfx"
#property link      "https://www.mql5.com/en/users/lubexfx"
#property version   "1.82"
#property strict
#property indicator_chart_window
#property indicator_buffers 4

#property indicator_label1  "UP"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2

#property indicator_label2  "DOWN"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2

#property indicator_label3  "Alert Up"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrWhite
#property indicator_width3  1

#property indicator_label4  "Alert Down"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrWhite
#property indicator_width4  1

//--- Inputs
input ENUM_TIMEFRAMES Stoch_TF = PERIOD_CURRENT;
input int      KPeriod         = 5;
input int      DPeriod         = 3;
input int      Slowing         = 3;
input int      OverBought      = 80;
input int      OverSold        = 20;

input bool     PopUpAlert      = true;
input bool     EmailAlert      = false;
input bool     PushAlert       = false;
input bool     ShowVerticalLine = true;

//--- MTF PANEL SETTINGS
input bool EnableMTFPanel = true;
input bool EnableMTFAlerts = false;
input int  MinTFAgree = 3;

input int X_Offset = 10;
input int Y_Offset = 20;
input color BullColor = clrLime;
input color BearColor = clrRed;
input color NeutralColor = clrGray;
input int FontSize = 10;
input int LineSpacing = 15;

//--- TF toggles
input bool Show_M1  = true;
input bool Show_M5  = true;
input bool Show_M15 = true;
input bool Show_M30 = true;
input bool Show_H1  = true;
input bool Show_H4  = true;
input bool Show_D1  = true;

//--- Buffers
double UP_Buf[];
double DOWN_Buf[];
double UP_Live_Buf[];
double DOWN_Live_Buf[];

//--- Globals
datetime lastConfirmedAlert = 0;
datetime lastLiveAlert      = 0;
string VLINE_NAME = "Stoch_Cross";

//--- Panel globals
ENUM_TIMEFRAMES tfs[7] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1};
string tfNames[7]      = {"M1","M5","M15","M30","H1","H4","D1"};
bool tfEnabled[7];
bool alertedBuy = false;
bool alertedSell = false;

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, UP_Buf);
   SetIndexBuffer(1, DOWN_Buf);
   SetIndexBuffer(2, UP_Live_Buf);
   SetIndexBuffer(3, DOWN_Live_Buf);

   SetIndexArrow(0, 233);
   SetIndexArrow(1, 234);
   SetIndexArrow(2, 233);
   SetIndexArrow(3, 234);

   IndicatorShortName("Stoch_Cross_MTF");

   tfEnabled[0]=Show_M1;
   tfEnabled[1]=Show_M5;
   tfEnabled[2]=Show_M15;
   tfEnabled[3]=Show_M30;
   tfEnabled[4]=Show_H1;
   tfEnabled[5]=Show_H4;
   tfEnabled[6]=Show_D1;

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectDelete(0, VLINE_NAME);

   for(int i=0;i<7;i++)
      ObjectDelete(0,"MTF_STOCH_"+tfNames[i]);
}

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
   if(rates_total <= Slowing + KPeriod) return(0);

   int limit = rates_total - prev_calculated;

   if(limit > 1)
   {
      limit = rates_total - Slowing - KPeriod - 1;
      ArrayInitialize(UP_Buf,0.0);
      ArrayInitialize(DOWN_Buf,0.0);
      ArrayInitialize(UP_Live_Buf,0.0);
      ArrayInitialize(DOWN_Live_Buf,0.0);
   }

   for(int i = limit; i >= 1; i--)
   {
   
      if(CheckSignal(i,true))
      {
         UP_Buf[i] = low[i];
         UP_Live_Buf[i] = 0;
         DOWN_Live_Buf[i] = 0;

         if(i == 1 && lastConfirmedAlert != time[1])
         {
            TriggerAlerts("CROSSOVER - UP");
            if(ShowVerticalLine) UpdateVLine(time[i], clrLime);
            lastConfirmedAlert = time[1];
         }
      }

      if(CheckSignal(i,false))
      {
         DOWN_Buf[i] = high[i];
         UP_Live_Buf[i] = 0;
         DOWN_Live_Buf[i] = 0;

         if(i == 1 && lastConfirmedAlert != time[1])
         {
            TriggerAlerts("CROSSOVER - DOWN");
            if(ShowVerticalLine) UpdateVLine(time[i], clrRed);
            lastConfirmedAlert = time[1];
         }
      }

      UP_Live_Buf[i] = 0;
      DOWN_Live_Buf[i] = 0;
   }

   UP_Live_Buf[0] = 0;
   DOWN_Live_Buf[0] = 0;

   if(UP_Buf[1] == 0 && DOWN_Buf[1] == 0)
   {
      if(CheckSignal(0,true))
      {
         UP_Live_Buf[0] = low[0];
         if(lastLiveAlert != time[0])
         {
            TriggerAlerts("WAIT FOR IT - UP");
            lastLiveAlert = time[0];
         }
      }
      else if(CheckSignal(0,false))
      {
         DOWN_Live_Buf[0] = high[0];
         if(lastLiveAlert != time[0])
         {
            TriggerAlerts("WAIT FOR IT - DOWN");
            lastLiveAlert = time[0];
         }
      }
   }

   if(EnableMTFPanel)
      DrawMTFPanel();

   return(rates_total);
}

//+------------------------------------------------------------------+
bool CheckSignal(int shift,bool isBuy)
{
   double k_curr=iStochastic(NULL,Stoch_TF,KPeriod,DPeriod,Slowing,MODE_SMA,0,MODE_MAIN,shift);
   double d_curr=iStochastic(NULL,Stoch_TF,KPeriod,DPeriod,Slowing,MODE_SMA,0,MODE_SIGNAL,shift);
   double k_prev=iStochastic(NULL,Stoch_TF,KPeriod,DPeriod,Slowing,MODE_SMA,0,MODE_MAIN,shift+1);
   double d_prev=iStochastic(NULL,Stoch_TF,KPeriod,DPeriod,Slowing,MODE_SMA,0,MODE_SIGNAL,shift+1);

   if(isBuy)
      return(k_prev <= d_prev && k_curr > d_curr && k_curr < OverSold);
   else
      return(k_prev >= d_prev && k_curr < d_curr && k_curr > OverBought);
}

//+------------------------------------------------------------------+
void DrawMTFPanel()
{
   int y=Y_Offset;
   int bullCount=0;
   int bearCount=0;

   for(int i=0;i<7;i++)
   {
      string name="MTF_STOCH_"+tfNames[i];

      if(!tfEnabled[i])
      {
         ObjectDelete(0,name);
         continue;
      }

      double k0=iStochastic(NULL,tfs[i],KPeriod,DPeriod,Slowing,MODE_SMA,0,MODE_MAIN,0);
      double d0=iStochastic(NULL,tfs[i],KPeriod,DPeriod,Slowing,MODE_SMA,0,MODE_SIGNAL,0);
      double k1=iStochastic(NULL,tfs[i],KPeriod,DPeriod,Slowing,MODE_SMA,0,MODE_MAIN,1);
      double d1=iStochastic(NULL,tfs[i],KPeriod,DPeriod,Slowing,MODE_SMA,0,MODE_SIGNAL,1);

      string signal="-";
      color clr=NeutralColor;

      bool buy=(k1<=d1 && k0>d0 && k0<OverSold);
      bool sell=(k1>=d1 && k0<d0 && k0>OverBought);

      if(buy){signal="-";clr=BullColor;bullCount++;}
      else if(sell){signal="-";clr=BearColor;bearCount++;}

      string zone="";
      if(k0<OverSold) zone="OS";
      else if(k0>OverBought) zone="OB";

      string text=tfNames[i]+": "+DoubleToString(k0,1)+" "+signal+" "+zone;

      DrawLabel(name,text,X_Offset,y,clr);
      y+=LineSpacing;
   }

   if(EnableMTFAlerts)
   {
      if(bullCount>=MinTFAgree && !alertedBuy)
      {
         Alert(_Symbol+" MTF ALIGN - UP");
         alertedBuy=true; alertedSell=false;
      }
      else if(bearCount>=MinTFAgree && !alertedSell)
      {
         Alert(_Symbol+" MTF ALIGN - DOWN");
         alertedSell=true; alertedBuy=false;
      }
      else if(bullCount<MinTFAgree && bearCount<MinTFAgree)
      {
         alertedBuy=false; alertedSell=false;
      }
   }
}

//+------------------------------------------------------------------+
void DrawLabel(string name,string text,int x,int y,color clr)
{
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);

   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,FontSize);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
}

//+------------------------------------------------------------------+
void TriggerAlerts(string msg)
{
   string fullMsg=_Symbol+" ("+EnumToString((ENUM_TIMEFRAMES)_Period)+"): "+msg;
   if(PopUpAlert) Alert(fullMsg);
   if(EmailAlert) SendMail("Stoch_Cross Alert",fullMsg);
   if(PushAlert)  SendNotification(fullMsg);
}

//+------------------------------------------------------------------+
void UpdateVLine(datetime t,color clr)
{
   if(ObjectFind(0,VLINE_NAME)<0)
   {
      ObjectCreate(0,VLINE_NAME,OBJ_VLINE,0,t,0);
      ObjectSetInteger(0,VLINE_NAME,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,VLINE_NAME,OBJPROP_BACK,true);
   }

   ObjectSetInteger(0,VLINE_NAME,OBJPROP_TIME,t);
   ObjectSetInteger(0,VLINE_NAME,OBJPROP_COLOR,clr);
}