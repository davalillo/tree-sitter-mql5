//+------------------------------------------------------------------+
//|                                               RiskGuardLite.mq5  |
//| Original educational portfolio sample. No profit guarantee.     |
//+------------------------------------------------------------------+
#property copyright "Original portfolio demonstration"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

input int      InpFastEmaPeriod   = 20;        // Fast EMA period
input int      InpSlowEmaPeriod   = 50;        // Slow EMA period
input int      InpAtrPeriod       = 14;        // ATR period
input double   InpStopAtrMultiple = 2.0;       // Stop loss distance, x ATR
input double   InpRewardRiskRatio = 1.5;       // Take profit, x stop distance
input double   InpRiskPercent     = 0.5;       // Risk per trade, % of equity
input int      InpMaxSpreadPoints = 25;        // Max spread to enter, points
input int      InpSlippagePoints  = 10;        // Max slippage, points
input ulong    InpMagicNumber     = 26081701;  // Magic number

CTrade trade;
int fast_handle = INVALID_HANDLE;
int slow_handle = INVALID_HANDLE;
int atr_handle = INVALID_HANDLE;
datetime last_bar_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization: validate inputs, create indicators        |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpFastEmaPeriod < 2 || InpSlowEmaPeriod <= InpFastEmaPeriod ||
      InpAtrPeriod < 2 || InpStopAtrMultiple <= 0.0 ||
      InpRewardRiskRatio <= 0.0 || InpRiskPercent <= 0.0 ||
      InpRiskPercent > 100.0 || InpMaxSpreadPoints < 0 ||
      InpSlippagePoints < 0)
      return INIT_PARAMETERS_INCORRECT;

   fast_handle = iMA(_Symbol,_Period,InpFastEmaPeriod,0,MODE_EMA,PRICE_CLOSE);
   slow_handle = iMA(_Symbol,_Period,InpSlowEmaPeriod,0,MODE_EMA,PRICE_CLOSE);
   atr_handle = iATR(_Symbol,_Period,InpAtrPeriod);
   if(fast_handle == INVALID_HANDLE || slow_handle == INVALID_HANDLE ||
      atr_handle == INVALID_HANDLE)
      return INIT_FAILED;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization: release indicator handles               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(fast_handle != INVALID_HANDLE) IndicatorRelease(fast_handle);
   if(slow_handle != INVALID_HANDLE) IndicatorRelease(slow_handle);
   if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
  }

//+------------------------------------------------------------------+
//| On each new closed bar, enter on an EMA crossover                |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!IsNewBar() || HasManagedPosition())
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) ||
      (tick.ask-tick.bid)/_Point > InpMaxSpreadPoints)
      return;

   double fast[],slow[],atr[];
   ArrayResize(fast,3);
   ArrayResize(slow,3);
   ArrayResize(atr,2);
   ArraySetAsSeries(fast,true);
   ArraySetAsSeries(slow,true);
   ArraySetAsSeries(atr,true);
   if(CopyBuffer(fast_handle,0,0,3,fast) != 3 ||
      CopyBuffer(slow_handle,0,0,3,slow) != 3 ||
      CopyBuffer(atr_handle,0,0,2,atr) != 2 || atr[1] <= 0.0)
      return;

//--- crossover on the last two closed bars
   const bool buy_signal = fast[1] > slow[1] && fast[2] <= slow[2];
   const bool sell_signal = fast[1] < slow[1] && fast[2] >= slow[2];
   if(!buy_signal && !sell_signal)
      return;

//--- ATR stop, fixed reward:risk target, percent-risk volume
   const ENUM_ORDER_TYPE order_type = buy_signal ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   const double entry = buy_signal ? tick.ask : tick.bid;
   const double min_stop = MathMax((double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point,
                                   MathMax(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),_Point));
   const double distance = MathMax(atr[1]*InpStopAtrMultiple,min_stop);
   const double stop = NormalizePrice(buy_signal ? entry-distance : entry+distance);
   const double limit = NormalizePrice(buy_signal ? entry+distance*InpRewardRiskRatio
                                                  : entry-distance*InpRewardRiskRatio);
   const double volume = RiskVolume(order_type,entry,stop);
   if(volume <= 0.0)
      return;

//--- send the order and check the server return code
   const bool requested = buy_signal
                          ? trade.Buy(volume,_Symbol,0.0,stop,limit,"RiskGuard Lite buy")
                          : trade.Sell(volume,_Symbol,0.0,stop,limit,"RiskGuard Lite sell");
   const uint retcode = trade.ResultRetcode();
   const bool accepted = retcode == TRADE_RETCODE_DONE ||
                         retcode == TRADE_RETCODE_DONE_PARTIAL ||
                         retcode == TRADE_RETCODE_PLACED;
   if(!requested || !accepted)
      PrintFormat("Order was not accepted: retcode=%u, %s",
                  retcode,trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| True once per new bar of the chart timeframe                     |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   const datetime current = iTime(_Symbol,_Period,0);
   if(current == 0 || current == last_bar_time)
      return false;
   last_bar_time = current;
   return true;
  }

//+------------------------------------------------------------------+
//| True if this EA already has a position on the symbol             |
//+------------------------------------------------------------------+
bool HasManagedPosition()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Lot size so that a stop-out loses InpRiskPercent of equity       |
//+------------------------------------------------------------------+
double RiskVolume(const ENUM_ORDER_TYPE order_type,const double entry,const double stop)
  {
   double one_lot_result = 0.0;
   if(!OrderCalcProfit(order_type,_Symbol,1.0,entry,stop,one_lot_result))
      return 0.0;
   const double loss_per_lot = MathAbs(one_lot_result);
   if(loss_per_lot <= 0.0)
      return 0.0;

   const double risk_money = AccountInfoDouble(ACCOUNT_EQUITY)*InpRiskPercent/100.0;
   const double min_volume = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   const double max_volume = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   const double step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(risk_money <= 0.0 || min_volume <= 0.0 || max_volume <= 0.0 || step <= 0.0)
      return 0.0;

   double volume = MathFloor((risk_money/loss_per_lot)/step)*step;
   if(volume < min_volume)
     {
      Print("Risk-based volume is below the broker minimum; entry skipped.");
      return 0.0;
     }
   volume = MathMin(volume,max_volume);
   return NormalizeDouble(volume,VolumeDigits(step));
  }

//+------------------------------------------------------------------+
//| Number of decimals in the broker volume step                     |
//+------------------------------------------------------------------+
int VolumeDigits(const double step)
  {
   for(int digits=0;digits<=8;digits++)
      if(MathAbs(step-NormalizeDouble(step,digits)) < 1e-10)
         return digits;
   return 8;
  }

//+------------------------------------------------------------------+
//| Round a price to the symbol tick size                            |
//+------------------------------------------------------------------+
double NormalizePrice(const double price)
  {
   const double tick_size = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      return NormalizeDouble(price,_Digits);
   return NormalizeDouble(MathRound(price/tick_size)*tick_size,_Digits);
  }
