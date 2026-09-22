//+------------------------------------------------------------------+
//|                                              ATR_Strength_Index  |
//+------------------------------------------------------------------+
// idea: https://www.tradingview.com/script/sHS0hHQB-ATR-Strength-Index/
// added invert feature so values correspond to RSI directions
#property description "Code by Max Michael 2026"
#property indicator_separate_window
#property indicator_buffers 1
#property indicator_color1  MediumOrchid
#property indicator_minimum 0
#property indicator_maximum 100
#property indicator_level1  70
#property indicator_level2  30
#property indicator_levelcolor clrSilver
#property indicator_levelstyle STYLE_DOT
#property strict

extern int             ATR_period = 14;
extern int             RSI_period = 10;
extern bool                Invert = true;
extern double            level_up = 70;
extern color         Linecolor_up = Maroon;
extern double            level_dn = 30;
extern color         Linecolor_dn = DarkGreen;
extern int           NumberOfBars = 800;

double   RsiBuffer[], PosBuffer[], NegBuffer[];

int init()
{
   IndicatorBuffers(3);
   SetIndexBuffer(0,RsiBuffer); SetIndexStyle(0,DRAW_LINE); SetIndexLabel(0,"RSI");
   SetIndexBuffer(1,PosBuffer); SetIndexStyle(1,DRAW_NONE); SetIndexLabel(1,"");
   SetIndexBuffer(2,NegBuffer); SetIndexStyle(2,DRAW_NONE); SetIndexLabel(2,"");
   IndicatorShortName("ATR Strength Index("+string(RSI_period)+")");
   IndicatorDigits(2);

   string shortname="ATR Strength Index("+string(ATR_period)+","+string(RSI_period)+")";
   IndicatorShortName(shortname);
   ObjectDelete("HLine_upper_ATR"); // will redraw line levels as may have been adjusted
   ObjectDelete("HLine_lower_ATR");
   int sub_window=WindowFind(shortname);
   if(!ObjectCreate("HLine_upper_ATR",OBJ_HLINE,sub_window,0,level_up))
   {
      Print(__FUNCTION__,": failed to create a horizontal line! Error code = ",GetLastError());
      return(false);
   }
   ObjectSet("HLine_upper_ATR",OBJPROP_COLOR,Linecolor_up);
   ObjectSet("HLine_upper_ATR",OBJPROP_BACK,False);
   if(!ObjectCreate("HLine_lower_ATR",OBJ_HLINE,sub_window,0,level_dn))
   {
      Print(__FUNCTION__,": failed to create a horizontal line! Error code = ",GetLastError());
      return(false);
   }
   ObjectSet("HLine_lower_ATR",OBJPROP_COLOR,Linecolor_dn);
   ObjectSet("HLine_lower_ATR",OBJPROP_BACK,False);   
   return(0);
}

int start()
{   
   int CountedBars=IndicatorCounted();
   if (CountedBars<0) return(-1);
   int i=Bars-CountedBars-1;
   if (i>NumberOfBars) i=MathMin(NumberOfBars,Bars-1);
   double diff,pos,neg;
   
   while(i>=0)
   {
      double sumn=0.0, sump=0.0;
      if(i==NumberOfBars-RSI_period)
      {
         int k=NumberOfBars-1;
         while(k>=i)
         {
            if(Invert) diff=iATR(NULL,0,ATR_period,k+1)-iATR(NULL,0,ATR_period,k);
            else       diff=iATR(NULL,0,ATR_period,k)-iATR(NULL,0,ATR_period,k+1);
            if(diff>0) sump += diff;  
            else       sumn -= diff; 
            k--;
         }
         pos = sump/RSI_period;
         neg = sumn/RSI_period;
      }
      else
      {
         if(Invert) diff=iATR(NULL,0,ATR_period,i+1)-iATR(NULL,0,ATR_period,i);
         else       diff=iATR(NULL,0,ATR_period,i)-iATR(NULL,0,ATR_period,i+1);
         if(diff>0) sump= diff;  
         else       sumn=-diff;  
         pos=(PosBuffer[i+1]*(RSI_period-1)+sump)/RSI_period;
         neg=(NegBuffer[i+1]*(RSI_period-1)+sumn)/RSI_period;
      }
      PosBuffer[i]=pos;  NegBuffer[i]=neg;
      if(NegBuffer[i]!=0.0) RsiBuffer[i]=100.0-100.0/(1+pos/neg);
      else
      { 
         if(PosBuffer[i]!=0.0) RsiBuffer[i]=100.0;
         else                  RsiBuffer[i]=50.0;
      }
      i--;
   }
   return(0);
}
