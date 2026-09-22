//+------------------------------------------------------------------+
//|                                     APB_Channel_XAUUSD_EA.mq4     |
//|  Strategy: averaged directional bars + channel, exactly as you    |
//|  described from the screenshot -                                  |
//|    - Arrow fires on a bar-colour reversal                         |
//|    - Entry triggers only once price CLOSES back inside/through    |
//|      the channel in the arrow's direction                         |
//|    - Any new opposite arrow immediately closes the open trade     |
//|    - Stop-loss sits below/above the recent swing low/high         |
//|                                                                    |
//|  IP NOTE: the screenshot is the output of the commercial, licence-|
//|  locked "Synergy Pro Average Price Bars" indicator (the same      |
//|  decompiled file with the DLL licence check you sent earlier).    |
//|  Its exact bar-averaging/channel formula is proprietary and is    |
//|  NOT reproduced here. Instead this EA implements your described   |
//|  RULES using two standard, public-domain techniques: Heikin-Ashi  |
//|  bars (averaged/coloured directional bars) and a Keltner-style    |
//|  EMA+ATR channel (the band). Same rule set, no licence/IP issue.  |
//|                                                                    |
//|  Designed for XAUUSD / XAGUSD.                                    |
//+------------------------------------------------------------------+
#property strict
#property copyright "Custom EA for Wasim"
#property version   "2.00"
#property description "Heikin-Ashi + Keltner channel APB-style strategy, swing-based SL"

//================= APB average-bar + channel (original) =============
input int    HeikinAshiBars      = 60;    // lookback recomputed each new bar
input int    Channel_MA_Period   = 20;    // channel middle line (EMA)
input int    Channel_ATR_Period  = 20;    // channel width basis
input double Channel_Multiplier  = 1.5;   // band = ATR * multiplier
input int    MaxBarsToTrigger    = 15;    // bars allowed to wait for the channel trigger; 0 = wait indefinitely

//================= Risk management ===================================
enum ENUM_RISK_MODE { RISK_PERCENT, RISK_FIXED_MONEY };
input ENUM_RISK_MODE RiskMode     = RISK_PERCENT;
input double RiskValue            = 1.0;    // % of balance if RISK_PERCENT, $ amount if RISK_FIXED_MONEY
input double RR_Ratio             = 1.5;    // TP distance = RR_Ratio * risk distance
input bool   UseInitialStopLoss   = true;   // true = hard stop below/above the swing low/high
enum ENUM_SL_METHOD { SL_SWING_STRUCTURE, SL_ATR_MULTIPLE };
input ENUM_SL_METHOD SLMethod     = SL_SWING_STRUCTURE;
input int    SwingLookbackBars    = 10;     // bars scanned back from the signal bar for the swing low/high
input int    ATR_Period_SL        = 14;     // used only if SLMethod = SL_ATR_MULTIPLE
input double ATR_SL_Multiplier    = 1.5;
input int    SL_BufferPips        = 20;     // extra buffer beyond the swing low/high
input double FixedLots            = 0.01;   // fallback lot size if risk calc fails

//================= Breakeven =========================================
input bool   UseBreakEven         = true;
input double BreakEvenTriggerPct  = 50;     // % of TP distance reached before locking in
input int    BreakEvenLockPips    = 2;

//================= Filters ===========================================
input bool   UseTimeFilter        = true;
input int    TradeStartHour       = 7;
input int    TradeEndHour         = 21;
input bool   UseLiquidityFilter   = true;
input int    VolumeAvgPeriod      = 20;
input double MinVolumeRatio       = 0.5;
input bool   AvoidFridayLateSession = true;
input int    FridayCutoffHour     = 20;
input bool   UseLargeCandleFilter = true;
input int    ATR_Period_Filter    = 100;
input double MaxATRPips           = 100;

//================= Trade management ==================================
input bool   CloseOnOppositeSignal = true;  // close on opposite ARROW, per screenshot
input int    MagicNumber           = 20260828;
input int    Slippage              = 20;
input string TradeComment          = "APB-Channel-EA";
input int    PointsPerPip          = 10;    // 10 for 3/5-digit gold quotes, 1 for 2/4-digit brokers
input bool   DebugLog              = true;

double   PipSize;
datetime lastBarTime = 0;

double   haOpen[];
double   haClose[];
int      pendingDir = 0;         // 1 = buy armed, -1 = sell armed, 0 = none
int      pendingBarsElapsed = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   PipSize = PointsPerPip * Point;
   if(StringFind(Symbol(),"XAU")<0 && StringFind(Symbol(),"XAG")<0)
      Print("Warning: this EA was tuned for XAUUSD/XAGUSD; running on ", Symbol());
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
void OnTick()
{
   ManageBreakEven();

   if(!IsNewBar()) return;

   ComputeHeikinAshi();

   bool sellArrow = HA_Bearish(1) && HA_Bullish(2); // HA colour flipped down
   bool buyArrow  = HA_Bullish(1) && HA_Bearish(2); // HA colour flipped up

   if(sellArrow)
   {
      if(DebugLog) Print("DBG Sell arrow (HA flip down) at ",TimeToStr(Time[1],TIME_DATE|TIME_MINUTES));
      if(CloseOnOppositeSignal) CloseOpposite(-1);
      pendingDir = -1;
      pendingBarsElapsed = 0;
   }
   else if(buyArrow)
   {
      if(DebugLog) Print("DBG Buy arrow (HA flip up) at ",TimeToStr(Time[1],TIME_DATE|TIME_MINUTES));
      if(CloseOnOppositeSignal) CloseOpposite(1);
      pendingDir = 1;
      pendingBarsElapsed = 0;
   }
   else if(pendingDir!=0)
   {
      pendingBarsElapsed++;
   }

   int entrySignal = 0;
   if(pendingDir!=0)
   {
      double upper1 = GetUpperBand(1);
      double lower1 = GetLowerBand(1);

      if(pendingDir==-1 && Close[1]<=upper1)
      {
         entrySignal = -1;
         if(DebugLog) Print("DBG SELL trigger: Close[1]=",Close[1]," <= upperBand=",upper1);
         pendingDir = 0;
      }
      else if(pendingDir==1 && Close[1]>=lower1)
      {
         entrySignal = 1;
         if(DebugLog) Print("DBG BUY trigger: Close[1]=",Close[1]," >= lowerBand=",lower1);
         pendingDir = 0;
      }
      else if(MaxBarsToTrigger>0 && pendingBarsElapsed>=MaxBarsToTrigger)
      {
         if(DebugLog) Print("DBG pending signal (",pendingDir,") expired after ",pendingBarsElapsed,
                             " bars with no channel trigger");
         pendingDir = 0;
      }
   }

   if(entrySignal==0) return;

   if(!PassFilters())
   {
      if(DebugLog) Print("DBG entrySignal=",entrySignal," but blocked by a filter, no trade");
      return;
   }
   if(CountOpenOrders()>0)
   {
      if(DebugLog) Print("DBG entrySignal=",entrySignal," but a position is already open, no trade");
      return;
   }

   if(DebugLog) Print("DBG entrySignal=",entrySignal," passed all filters -> opening trade");
   OpenTrade(entrySignal);
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   if(Time[0]==lastBarTime) return false;
   lastBarTime = Time[0];
   return true;
}

//+------------------------------------------------------------------+
//  Heikin-Ashi (public domain) - stands in for the "averaged bars"   |
//+------------------------------------------------------------------+
void ComputeHeikinAshi()
{
   int n = HeikinAshiBars;
   if(n < MaxBarsToTrigger+5) n = MaxBarsToTrigger+5;
   ArrayResize(haOpen,n+1);
   ArrayResize(haClose,n+1);

   for(int idx=n; idx>=0; idx--)
   {
      double c = (Open[idx]+High[idx]+Low[idx]+Close[idx])/4.0;
      double o;
      if(idx==n) o = (Open[idx]+Close[idx])/2.0;
      else       o = (haOpen[idx+1]+haClose[idx+1])/2.0;
      haOpen[idx]  = o;
      haClose[idx] = c;
   }
}
bool HA_Bullish(int shift){ return haClose[shift]>haOpen[shift]; }
bool HA_Bearish(int shift){ return haClose[shift]<haOpen[shift]; }

//+------------------------------------------------------------------+
//  Keltner-style EMA+ATR channel (public domain) - the "channel"    |
//+------------------------------------------------------------------+
double GetUpperBand(int shift)
{
   double mid = iMA(NULL,0,Channel_MA_Period,0,MODE_EMA,PRICE_CLOSE,shift);
   double atr = iATR(NULL,0,Channel_ATR_Period,shift);
   return mid + atr*Channel_Multiplier;
}
double GetLowerBand(int shift)
{
   double mid = iMA(NULL,0,Channel_MA_Period,0,MODE_EMA,PRICE_CLOSE,shift);
   double atr = iATR(NULL,0,Channel_ATR_Period,shift);
   return mid - atr*Channel_Multiplier;
}

//+------------------------------------------------------------------+
bool PassFilters()
{
   if(UseTimeFilter)
   {
      int h=Hour();
      bool inWindow;
      if(TradeStartHour<=TradeEndHour) inWindow = (h>=TradeStartHour && h<TradeEndHour);
      else                             inWindow = !(h<TradeStartHour && h>=TradeEndHour);
      if(!inWindow)
      {
         if(DebugLog) Print("DBG filter: TIME window blocked trade, hour=",h,
                             " window=[",TradeStartHour,",",TradeEndHour,")");
         return false;
      }
   }

   if(AvoidFridayLateSession && DayOfWeek()==5 && Hour()>=FridayCutoffHour)
   {
      if(DebugLog) Print("DBG filter: Friday late-session blocked trade, hour=",Hour());
      return false;
   }

   if(UseLiquidityFilter)
   {
      double avgVol=0;
      for(int i=1;i<=VolumeAvgPeriod;i++) avgVol += (double)Volume[i];
      avgVol/=VolumeAvgPeriod;
      if(avgVol>0 && Volume[1] < MinVolumeRatio*avgVol)
      {
         if(DebugLog) Print("DBG filter: LIQUIDITY blocked trade, vol[1]=",Volume[1],
                             " avgVol=",avgVol," minRequired=",MinVolumeRatio*avgVol);
         return false;
      }
   }

   if(UseLargeCandleFilter)
   {
      double atr = iATR(NULL,0,ATR_Period_Filter,1);
      double atrPips = atr/PipSize;
      if(atrPips>MaxATRPips)
      {
         if(DebugLog) Print("DBG filter: ATR/large-candle blocked trade, atrPips=",atrPips,
                             " max=",MaxATRPips);
         return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
int CountOpenOrders()
{
   int c=0;
   for(int i=0;i<OrdersTotal();i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS)) continue;
      if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber) c++;
   }
   return c;
}

//+------------------------------------------------------------------+
void CloseOpposite(int signal)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;

      if(signal==1 && OrderType()==OP_SELL)
      {
         if(!OrderClose(OrderTicket(),OrderLots(),Ask,Slippage,clrOrange))
            Print("DBG CloseOpposite (sell) failed: ",GetLastError());
         else if(DebugLog) Print("DBG Closed SELL #",OrderTicket()," on opposite arrow");
      }
      else if(signal==-1 && OrderType()==OP_BUY)
      {
         if(!OrderClose(OrderTicket(),OrderLots(),Bid,Slippage,clrOrange))
            Print("DBG CloseOpposite (buy) failed: ",GetLastError());
         else if(DebugLog) Print("DBG Closed BUY #",OrderTicket()," on opposite arrow");
      }
   }
}

//+------------------------------------------------------------------+
double CalcLots(double slDistance)
{
   double riskMoney;
   if(RiskMode==RISK_PERCENT) riskMoney = AccountBalance()*RiskValue/100.0;
   else                        riskMoney = RiskValue;

   double tickValue = MarketInfo(Symbol(),MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(),MODE_TICKSIZE);
   if(tickSize<=0) tickSize=Point;
   if(tickValue<=0 || slDistance<=0) return FixedLots;

   double lossPerLot = (slDistance/tickSize)*tickValue;
   if(lossPerLot<=0) return FixedLots;

   double lots = riskMoney/lossPerLot;

   double minLot  = MarketInfo(Symbol(),MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(),MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(),MODE_LOTSTEP);
   if(lotStep<=0) lotStep=0.01;

   lots = MathFloor(lots/lotStep)*lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return lots;
}

//+------------------------------------------------------------------+
// Stop-loss / risk-distance reference. SL_SWING_STRUCTURE places the |
// stop beyond the lowest low / highest high of the last              |
// SwingLookbackBars closed bars (a real structural swing point, not  |
// just the single signal candle), plus a buffer.                    |
//+------------------------------------------------------------------+
double GetStopLoss(int direction,double entry)
{
   double sl;
   if(SLMethod==SL_SWING_STRUCTURE)
   {
      if(direction==1)
      {
         double swingLow = Low[1];
         for(int i=2;i<=SwingLookbackBars;i++)
            if(Low[i]<swingLow) swingLow=Low[i];
         sl = swingLow - SL_BufferPips*PipSize;
      }
      else
      {
         double swingHigh = High[1];
         for(int i=2;i<=SwingLookbackBars;i++)
            if(High[i]>swingHigh) swingHigh=High[i];
         sl = swingHigh + SL_BufferPips*PipSize;
      }
   }
   else
   {
      double atr = iATR(NULL,0,ATR_Period_SL,1);
      if(direction==1) sl = entry - atr*ATR_SL_Multiplier;
      else              sl = entry + atr*ATR_SL_Multiplier;
   }
   return sl;
}

//+------------------------------------------------------------------+
void OpenTrade(int signal)
{
   double entry, sl, tp, dist, lots;
   int type;
   color arrowColor;

   if(signal==1)
   {
      entry = Ask;
      sl    = GetStopLoss(1, entry);
      dist  = entry-sl;
      if(dist<=0) { Print("DBG Invalid BUY risk distance, trade skipped"); return; }
      tp    = entry + dist*RR_Ratio;
      lots  = CalcLots(dist);
      type  = OP_BUY;
      arrowColor = clrBlue;
   }
   else
   {
      entry = Bid;
      sl    = GetStopLoss(-1, entry);
      dist  = sl-entry;
      if(dist<=0) { Print("DBG Invalid SELL risk distance, trade skipped"); return; }
      tp    = entry - dist*RR_Ratio;
      lots  = CalcLots(dist);
      type  = OP_SELL;
      arrowColor = clrRed;
   }

   double sendSL = UseInitialStopLoss ? NormalizeDouble(sl,Digits) : 0.0;

   if(UseInitialStopLoss)
   {
      double stopLevelPts = MarketInfo(Symbol(),MODE_STOPLEVEL) * Point;
      if(stopLevelPts>0 && (MathAbs(entry-sl)<stopLevelPts || MathAbs(entry-tp)<stopLevelPts))
      {
         Print("DBG OpenTrade aborted: SL/TP closer than broker StopLevel (",
               MarketInfo(Symbol(),MODE_STOPLEVEL)," points). Increase SL_BufferPips or ATR_SL_Multiplier.");
         return;
      }
   }

   if(DebugLog)
      Print("DBG OpenTrade: type=",type," entry=",entry," sl(sent)=",sendSL,
            " tp=",tp," lots=",lots," riskDist=",dist);

   int ticket = OrderSend(Symbol(),type,lots,entry,Slippage,sendSL,
                           NormalizeDouble(tp,Digits),TradeComment,MagicNumber,0,arrowColor);
   if(ticket<0)
      Print("DBG OrderSend FAILED, error code ",GetLastError());
   else
      Print("DBG OrderSend OK, ticket #",ticket);
}

//+------------------------------------------------------------------+
// Moves the stop to breakeven (+lock) once price has covered the     |
// required % of the TP distance. Also works correctly if someone     |
// sets UseInitialStopLoss=false (sl==0 is treated as "no stop yet"), |
// so switching that input back off doesn't break this logic.         |
//+------------------------------------------------------------------+
void ManageBreakEven()
{
   if(!UseBreakEven) return;

   for(int i=0;i<OrdersTotal();i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;

      double openPrice = OrderOpenPrice();
      double sl = OrderStopLoss();
      double tp = OrderTakeProfit();
      if(tp==0) continue;

      if(OrderType()==OP_BUY)
      {
         double dist = tp-openPrice;
         double trigger = openPrice + dist*BreakEvenTriggerPct/100.0;
         if(Bid>=trigger && sl<openPrice)
         {
            double newSL = openPrice + BreakEvenLockPips*PipSize;
            if(!OrderModify(OrderTicket(),openPrice,NormalizeDouble(newSL,Digits),tp,0,clrGreen))
               Print("DBG BreakEven modify (buy) failed: ",GetLastError());
            else if(DebugLog) Print("DBG BreakEven set on BUY #",OrderTicket());
         }
      }
      else if(OrderType()==OP_SELL)
      {
         double dist = openPrice-tp;
         double trigger = openPrice - dist*BreakEvenTriggerPct/100.0;
         if(Bid<=trigger && (sl>openPrice || sl==0))
         {
            double newSL = openPrice - BreakEvenLockPips*PipSize;
            if(!OrderModify(OrderTicket(),openPrice,NormalizeDouble(newSL,Digits),tp,0,clrRed))
               Print("DBG BreakEven modify (sell) failed: ",GetLastError());
            else if(DebugLog) Print("DBG BreakEven set on SELL #",OrderTicket());
         }
      }
   }
}
//+------------------------------------------------------------------+
