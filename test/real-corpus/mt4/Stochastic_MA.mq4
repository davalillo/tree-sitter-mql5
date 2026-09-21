//+------------------------------------------------------------------+
//|                                                Stochastic_MA.mq4 |
//|                        Copyright 2022, MetaQuotes Software Corp. |
//|                                            https://forge.mql5.io |
//+------------------------------------------------------------------+
#property copyright "Copyright 2022, MetaQuotes Software Corp."
#property link      "https://forge.mql5.io"
#property version   "1.00"
#property strict
#property indicator_separate_window

#property description "Stochastic Moving Average" 
#property description "Developed by CoolByte 2026."
#property description "WARNING: Use this software at your own risk."
#property description "The creator of this indicator cannot be held responsible for any damage or loss."

#property indicator_minimum 0
#property indicator_maximum 100

#property indicator_level1     20.0
#property indicator_level2     80.0
#property indicator_levelcolor clrSilver
#property indicator_levelstyle STYLE_DOT

#property indicator_buffers 6
#property indicator_color1  clrDodgerBlue    // weak up
#property indicator_color2  clrTomato        // weak down
#property indicator_color3  clrBlue          // strong up
#property indicator_color4  clrCrimson       // strong down
#property indicator_color5  clrLime          // K line
#property indicator_color6  clrYellow        // D line

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input int                  inpKPeriod        = 3;              // K Period
input int                  inpDPeriod        = 3;              // D Period
input int                  inpSlowingPeriod  = 8;              // Slowing Period
input ENUM_APPLIED_PRICE   inpMAPrice        = PRICE_TYPICAL;  // MA Applied Price

//+------------------------------------------------------------------+
//| Output Buffers                                                   |
//+------------------------------------------------------------------+
double   bufUp1[];   // weak up
double   bufDn1[];   // weak down
double   bufUp2[];   // strong up
double   bufDn2[];   // strong down
double   bufSK[];    // K line
double   bufSD[];    // D line

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorShortName(WindowExpertName()+"(" 
      + string(inpKPeriod) + "," 
      + string(inpDPeriod) + "," 
      + string(inpSlowingPeriod) 
      + ")");
   IndicatorDigits(_Digits);
   IndicatorBuffers(6);
   int k = -1;
   k++;	SetIndexBuffer(k,bufUp1);     SetIndexStyle(k,DRAW_HISTOGRAM,STYLE_SOLID,2);         
         SetIndexLabel (k,"Up1");
   k++;	SetIndexBuffer(k,bufDn1);     SetIndexStyle(k,DRAW_HISTOGRAM,STYLE_SOLID,2);         
         SetIndexLabel (k,"Down1");
   k++;	SetIndexBuffer(k,bufUp2);     SetIndexStyle(k,DRAW_HISTOGRAM,STYLE_SOLID,2);         
         SetIndexLabel (k,"Up2");
   k++;	SetIndexBuffer(k,bufDn2);     SetIndexStyle(k,DRAW_HISTOGRAM,STYLE_SOLID,2);         
         SetIndexLabel (k,"Down2");
   k++;	SetIndexBuffer(k,bufSK);      SetIndexStyle(k,DRAW_LINE,STYLE_SOLID,1);         
         SetIndexLabel (k,"K");
   k++;	SetIndexBuffer(k,bufSD);      SetIndexStyle(k,DRAW_LINE,STYLE_SOLID,1);         
         SetIndexLabel (k,"D");

   //--- set class parameters ---
   m_StocMA.parPrice          = inpMAPrice;
   m_StocMA.parDPeriod        = inpDPeriod;
   m_StocMA.parKPeriod        = inpKPeriod;
   m_StocMA.parSlowingPeriod  = inpSlowingPeriod;
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
   int limit=rates_total-prev_calculated; if (limit>=rates_total) limit=rates_total-1;

   for(int i=limit; i>=0; i--)
   {
      m_StocMA.Update(i);
      bufSK[i] = m_StocMA.bufStoK[0];  // stochastic K      
      bufSD[i] = m_StocMA.bufStoD[0];  // stochastic D
           
      bufUp1[i] = EMPTY_VALUE;   if (m_StocMA.bufStoDir[0]==1)    bufUp1[i] = 100;  // weak up
      bufDn1[i] = EMPTY_VALUE;   if (m_StocMA.bufStoDir[0]==-1)   bufDn1[i] = 100;  // weak down
      bufUp2[i] = EMPTY_VALUE;   if (m_StocMA.bufStoDir[0]==2)    bufUp2[i] = 100;  // strong up
      bufDn2[i] = EMPTY_VALUE;   if (m_StocMA.bufStoDir[0]==-2)   bufDn2[i] = 100;  // strong down
   }
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Stochastic Moving Average                                        |
//+------------------------------------------------------------------+
class CStochasticMA
{

   //+------------------------------------------------------------------+
   //| private                                                          |
   //+------------------------------------------------------------------+
private:
   datetime m_prvBarDt;
   bool     m_isInit;
   double   m_bufMA[];
   int      m_bufDir[];
   
   //+------------------------------------------------------------------+
   //| Initialize                                                       |
   //+------------------------------------------------------------------+
   void Initialize()
   {
      m_isInit = true;

      ArrayResize(bufStoc,2);                ArrayInitialize(bufStoc,EMPTY_VALUE);
      ArrayResize(bufStoK,2);                ArrayInitialize(bufStoK,EMPTY_VALUE);
      ArrayResize(bufStoD,2);                ArrayInitialize(bufStoD,EMPTY_VALUE);
      ArrayResize(bufStoDir,2);              ArrayInitialize(bufStoDir,0);

      ArrayResize(m_bufMA,parSlowingPeriod); ArrayInitialize(m_bufMA,0.0);
      ArrayResize(m_bufDir,2);               ArrayInitialize(m_bufDir,0);
   } 
   
   //+------------------------------------------------------------------+
   //| SmoothMA                                                         |
   //+------------------------------------------------------------------+
   void SmoothMA(double &aMA[], double price, int period)
   {
      if (period<1)  {aMA[0] = price;  return;}
      if (aMA[1]==EMPTY_VALUE)   aMA[1] = price;
      aMA[0] = aMA[1]+(price-aMA[1])/period;
   }

   //+------------------------------------------------------------------+
   //| public                                                           |
   //+------------------------------------------------------------------+
public:
   //--- Input Parameters ---
   string               parName;          // Symbol Name
   int                  parTimeFrame;     // Symbol Time Frame
   
   int                  parPeriod;        // Period
   int                  parKPeriod;       // K Period
   int                  parDPeriod;       // D Period
   int                  parSlowingPeriod; // Slowing Period
   ENUM_APPLIED_PRICE   parPrice;         // Applied Price
   
   //--- Output Buffers (index 0=current, 1=previous) ---
   double bufStoc[];                      // Stochastic
   double bufStoK[];                      // Stochastic K line
   double bufStoD[];                      // Stochastic D line
   int    bufStoDir[];                    // Direction 
                                          //    (2=Strong Up, 1=Weak Up, -1=Weak Down, -2=Strong Down)
   
   //+------------------------------------------------------------------+
   //| CStochasticMA Constructor                                        |
   //+------------------------------------------------------------------+
   CStochasticMA()
   {
      m_isInit          = false;
      parName           = _Symbol;
      parTimeFrame      = _Period;
      
      parKPeriod        = 3;              // K Period
      parDPeriod        = 3;              // D Period
      parSlowingPeriod  = 8;              // Slowing Period
      parPrice          = PRICE_TYPICAL;  // Applied Price
   }
   
   //+------------------------------------------------------------------+
   //| ~CStochasticMA Destructor                                        |
   //+------------------------------------------------------------------+
   ~CStochasticMA(){}

   //+------------------------------------------------------------------+
   //| Update                                                           |
   //+------------------------------------------------------------------+
   void Update(int shift)
   {
      //--- initialize ---
      if (!m_isInit) Initialize();
      if (shift>=Bars) return;
      
      datetime curBarDt = Time[shift];
      int curBar        = shift;
      
      //--- update prev ---
      int k;
      datetime tfBarDt = curBarDt;
      if (parTimeFrame>_Period)  tfBarDt = iTime(parName,parTimeFrame,iBarShift(parName,parTimeFrame,curBarDt));
      if (m_prvBarDt!=tfBarDt)
      {
         m_prvBarDt     = tfBarDt;
         
         bufStoc[1]     = bufStoc[0]; 
         bufStoK[1]     = bufStoK[0]; 
         bufStoD[1]     = bufStoD[0]; 
         bufStoDir[1]   = bufStoDir[0]; 
         m_bufDir[1]    = m_bufDir[0];
         for(k=(parSlowingPeriod-1);k>0;k--)    m_bufMA[k] = m_bufMA[k-1];
      }
      
      //--- initialize from prev
      bufStoc[0]     = bufStoc[1]; 
      bufStoK[0]     = bufStoK[1]; 
      bufStoD[0]     = bufStoD[1]; 
      bufStoDir[0]   = bufStoDir[1]; 
      m_bufDir[0]    = m_bufDir[1];
      m_bufMA[0]     = m_bufMA[1];
      
      //--- calculation to get price ---
      int i = shift;
      double price = 0.0;
      if (parTimeFrame<=_Period)
      {
         switch(parPrice)
         {
            case PRICE_CLOSE:    price =  Close[i];                              break;
            case PRICE_OPEN:     price =  Open[i];                               break;
            case PRICE_HIGH:     price =  High[i];                               break;
            case PRICE_LOW:      price =  Low[i];                                break;
            case PRICE_MEDIAN:   price = (High[i]+Low[i])/2.0;                   break;
            case PRICE_TYPICAL:  price = (High[i]+Low[i]+Close[i])/3.0;          break;
            case PRICE_WEIGHTED: price = (High[i]+Low[i]+Close[i]+Close[i])/4.0; break;
         }
      }
      else
      {
         i = iBarShift(parName,parTimeFrame,curBarDt);
         switch(parPrice)
         {
            case PRICE_CLOSE:    price =  iClose(parName,parTimeFrame,i);        break;
            case PRICE_OPEN:     price =  iOpen (parName,parTimeFrame,i);        break;
            case PRICE_HIGH:     price =  iHigh (parName,parTimeFrame,i);        break;
            case PRICE_LOW:      price =  iLow  (parName,parTimeFrame,i);        break;
            case PRICE_MEDIAN:   price = (iHigh (parName,parTimeFrame,i)+
                                          iLow  (parName,parTimeFrame,i))/2.0;   break;
            case PRICE_TYPICAL:  price = (iHigh (parName,parTimeFrame,i)+
                                          iLow  (parName,parTimeFrame,i)+
                                          iClose(parName,parTimeFrame,i))/3.0;   break;
            case PRICE_WEIGHTED: price = (iHigh (parName,parTimeFrame,i)+
                                          iLow  (parName,parTimeFrame,i)+
                                          iClose(parName,parTimeFrame,i)+
                                          iClose(parName,parTimeFrame,i))/4.0;   break;
         }
      }

      //--- calculate MA -----
      SmoothMA(m_bufMA,price,parSlowingPeriod);
      
      //--- calculate stochastic ---
      double stoch;
      double rangeHi = 0.0;
      double rangeLo = 0.0;
      int idxHi = ArrayMaximum(m_bufMA,parSlowingPeriod,0);
      int idxLo = ArrayMinimum(m_bufMA,parSlowingPeriod,0);
      if (idxHi>=0)  rangeHi = m_bufMA[idxHi];
      if (idxLo>=0)  rangeLo = m_bufMA[idxLo];
      if (rangeHi<=0.0 || rangeLo<=0.0 || (rangeHi-rangeLo==0.0)) stoch = 0.0;
      else  stoch = 100 * (m_bufMA[0] - rangeLo) / (rangeHi-rangeLo);
      bufStoc[0] = stoch;
      
      //--- calculate K ---
      SmoothMA(bufStoK,bufStoc[0],parKPeriod);
      
      //--- calculate D ---
      SmoothMA(bufStoD,bufStoK[0],parDPeriod);

      //--- calculate direction ---
      if (  (bufStoD[1]< 20 && bufStoD[0]>=20)
         || (bufStoD[1]< 50 && bufStoD[0]>=50)
         || (bufStoD[1]< 80 && bufStoD[0]>=80)
         )  m_bufDir[0] = 2;
         
      if (  (bufStoD[1]> 80 && bufStoD[0]<=80)
         || (bufStoD[1]> 50 && bufStoD[0]<=50)
         || (bufStoD[1]> 20 && bufStoD[0]<=20)
         )  m_bufDir[0] = -2;

      if (m_bufDir[0]==2)
      {
         bufStoDir[0] = 2;
         if (bufStoK[0]<bufStoD[0]) bufStoDir[0] = 1;    // pullback dir
      }
      
      if (m_bufDir[0]==-2)
      { 
         bufStoDir[0] = -2;
         if (bufStoK[0]>bufStoD[0]) bufStoDir[0] = -1;   // pullback dir
      }
   }
};
CStochasticMA m_StocMA;