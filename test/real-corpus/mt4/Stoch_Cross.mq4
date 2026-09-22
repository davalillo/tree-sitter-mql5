//+------------------------------------------------------------------+
//|                                                  Stoch_Cross.mq4 |
//|                                          Copyright 2026, lubexfx |
//|                            https://www.mql5.com/en/users/lubexfx |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, lubexfx"
#property link      "https://www.mql5.com/en/users/lubexfx"
#property version   "1.82"
#property strict
#property indicator_chart_window
#property indicator_buffers 4

//--- Display Properties
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

//--- Input Parameters
input int      KPeriod         = 5;
input int      DPeriod         = 3;
input int      Slowing         = 3;
input int      OverBought      = 80;
input int      OverSold        = 20;
input bool     PopUpAlert      = true;
input bool     EmailAlert      = false;
input bool     PushAlert       = false;
input bool     ShowVerticalLine = true;

//--- Buffers
double UP_Buf[];
double DOWN_Buf[];
double UP_Live_Buf[];
double DOWN_Live_Buf[];

//--- Global Variables
datetime lastConfirmedAlert = 0;
datetime lastLiveAlert      = 0;
string VLINE_NAME = "Stoch_Cross";

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

   IndicatorShortName("Stoch_Cross ("+IntegerToString(KPeriod)+","+IntegerToString(DPeriod)+")");
   
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectDelete(0, VLINE_NAME);
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
      ArrayInitialize(UP_Buf, 0.0);
      ArrayInitialize(DOWN_Buf, 0.0);
      ArrayInitialize(UP_Live_Buf, 0.0);
      ArrayInitialize(DOWN_Live_Buf, 0.0);
   }

   //--- Loop for historical bars
   for(int i = limit; i >= 1; i--)
   {
      UP_Buf[i]   = 0.0;
      DOWN_Buf[i] = 0.0;

      UP_Live_Buf[i] = 0.0;
      DOWN_Live_Buf[i] = 0.0;
      
      if(CheckSignal(i, true))
      {
         UP_Buf[i] = low[i];
         if(i == 1 && lastConfirmedAlert != time[1])
         {
            TriggerAlerts("CROSSOVER - UP");
            if(ShowVerticalLine) UpdateVLine(time[i], clrLime);
            lastConfirmedAlert = time[1];
         }
      }
      
      if(CheckSignal(i, false))
      {
         DOWN_Buf[i] = high[i];
         if(i == 1 && lastConfirmedAlert != time[1])
         {
            TriggerAlerts("CROSSOVER - DOWN");
            if(ShowVerticalLine) UpdateVLine(time[i], clrRed);
            lastConfirmedAlert = time[1];
         }
      }
   }

   // Intrabar
   UP_Live_Buf[0]   = 0.0;
   DOWN_Live_Buf[0] = 0.0;

   if(CheckSignal(0, true))
   {
      UP_Live_Buf[0] = low[0];
      if(lastLiveAlert != time[0])
      {
         TriggerAlerts("WAIT FOR IT - UP");
         lastLiveAlert = time[0];
      }
   }
   else if(CheckSignal(0, false))
   {
      DOWN_Live_Buf[0] = high[0];
      if(lastLiveAlert != time[0])
      {
         TriggerAlerts("WAIT FOR IT - DOWN");
         lastLiveAlert = time[0];
      }
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
bool CheckSignal(int shift, bool isBuy)
{
   double k_curr = iStochastic(NULL, 0, KPeriod, DPeriod, Slowing, MODE_SMA, 0, MODE_MAIN, shift);
   double d_curr = iStochastic(NULL, 0, KPeriod, DPeriod, Slowing, MODE_SMA, 0, MODE_SIGNAL, shift);
   double k_prev = iStochastic(NULL, 0, KPeriod, DPeriod, Slowing, MODE_SMA, 0, MODE_MAIN, shift + 1);
   double d_prev = iStochastic(NULL, 0, KPeriod, DPeriod, Slowing, MODE_SMA, 0, MODE_SIGNAL, shift + 1);

   if(isBuy)
      return (k_prev <= d_prev && k_curr > d_curr && k_curr < OverSold);
   else
      return (k_prev >= d_prev && k_curr < d_curr && k_curr > OverBought);
}

//+------------------------------------------------------------------+
void TriggerAlerts(string msg)
{
   string fullMsg = _Symbol + " (" + EnumToString((ENUM_TIMEFRAMES)_Period) + "): " + msg;
   if(PopUpAlert) Alert(fullMsg);
   if(EmailAlert) SendMail("Stoch_Cross Alert", fullMsg);
   if(PushAlert)  SendNotification(fullMsg);
}

//+------------------------------------------------------------------+
//| Updates the single latest vertical line                          |
//+------------------------------------------------------------------+
void UpdateVLine(datetime t, color clr)
{
   if(ObjectFind(0, VLINE_NAME) < 0)
   {
      ObjectCreate(0, VLINE_NAME, OBJ_VLINE, 0, t, 0);
      ObjectSetInteger(0, VLINE_NAME, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, VLINE_NAME, OBJPROP_BACK, true);
   }
   
   // Move the existing line to the new signal position and change color
   ObjectSetInteger(0, VLINE_NAME, OBJPROP_TIME, t);
   ObjectSetInteger(0, VLINE_NAME, OBJPROP_COLOR, clr);
}