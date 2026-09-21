//+------------------------------------------------------------------+
//|                                    multiple_order_stop_limit.mq4 |
//|                                                      reza rahmad |
//|                                           rezarahmad@gmail.com   |
//+------------------------------------------------------------------+
#property copyright "reza rahmad"
#property link      "rezarahmad@gmail.com"
#property version   "2.00"
#property strict
#property show_inputs

//--- Enums for order type
enum ENUM_ORDER_STRATEGY
  {
   STRATEGY_STOP  = 0, // Stop Orders (BuyStop & SellStop)
   STRATEGY_LIMIT = 1, // Limit Orders (BuyLimit & SellLimit)
   STRATEGY_BOTH  = 2  // Both Stop & Limit Orders
  };

input string              sec1          = "=== Order Settings ===";
input ENUM_ORDER_STRATEGY OrderStrategy = STRATEGY_STOP; // Order Strategy Type
input int                 TotalOrders   = 5;             // Number of orders (Per Direction)
input double              Lots          = 0.01;          // Lot Size

input string              sec2          = "=== Distance Settings (in Pips) ===";
input double              RangeStepPips = 10.0;          // Step distance between orders
input double              StopLossPips  = 15.0;          // StopLoss (0 for none)
input double              TakeProfitPips= 20.0;          // TakeProfit (0 for none)

input string              sec3          = "=== Other Settings ===";
input int                 MagicNumber   = 2016;          // Magic Number

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
  {
//--- Universal Pip Calculation (Supports Forex 4/5 Digits, Gold XAU, Stocks, Crypto)
   double pip_size = Point;
   if(Digits == 5 || Digits == 3)
     {
      pip_size = Point * 10.0; // Adjust for fractional pip brokers
     }

//--- Confirm execution
   string strat_name = "";
   if(OrderStrategy == STRATEGY_STOP) strat_name = "Stop Orders";
   if(OrderStrategy == STRATEGY_LIMIT) strat_name = "Limit Orders";
   if(OrderStrategy == STRATEGY_BOTH) strat_name = "Stop & Limit Orders";

   string msg = StringFormat("Execute %d %s on %s?\n\nLot Size: %.2f\nStep Range: %.1f Pips\nSL: %.1f Pips | TP: %.1f Pips", 
                             TotalOrders * ((OrderStrategy == STRATEGY_BOTH) ? 4 : 2), 
                             strat_name, Symbol(), Lots, RangeStepPips, StopLossPips, TakeProfitPips);
                             
   int res = MessageBox(msg, "Order Confirmation", MB_YESNO | MB_ICONWARNING);
   if(res != IDYES)
     {
      Print("Grid placement cancelled by user.");
      return;
     }

   double ask = Ask;
   double bid = Bid;

   for(int i = 1; i <= TotalOrders; i++)
     {
      RefreshRates();
      ask = Ask;
      bid = Bid;
      
      double distance = RangeStepPips * i * pip_size;
      double sl_dist  = StopLossPips * pip_size;
      double tp_dist  = TakeProfitPips * pip_size;
      
//--- Calculate Stop Orders
      if(OrderStrategy == STRATEGY_STOP || OrderStrategy == STRATEGY_BOTH)
        {
         // BUY STOP
         double buy_price = NormalizeDouble(ask + distance, Digits);
         double buy_sl = (StopLossPips > 0) ? NormalizeDouble(buy_price - sl_dist, Digits) : 0.0;
         double buy_tp = (TakeProfitPips > 0) ? NormalizeDouble(buy_price + tp_dist, Digits) : 0.0;
         
         if(OrderSend(Symbol(), OP_BUYSTOP, Lots, buy_price, 10, buy_sl, buy_tp, "Grid BuyStop", MagicNumber, 0, clrBlue) < 0)
            Print("Error opening BuyStop: ", GetLastError());
            
         // SELL STOP
         double sell_price = NormalizeDouble(bid - distance, Digits);
         double sell_sl = (StopLossPips > 0) ? NormalizeDouble(sell_price + sl_dist, Digits) : 0.0;
         double sell_tp = (TakeProfitPips > 0) ? NormalizeDouble(sell_price - tp_dist, Digits) : 0.0;
         
         if(OrderSend(Symbol(), OP_SELLSTOP, Lots, sell_price, 10, sell_sl, sell_tp, "Grid SellStop", MagicNumber, 0, clrRed) < 0)
            Print("Error opening SellStop: ", GetLastError());
        }
        
//--- Calculate Limit Orders
      if(OrderStrategy == STRATEGY_LIMIT || OrderStrategy == STRATEGY_BOTH)
        {
         // BUY LIMIT
         double buy_price = NormalizeDouble(ask - distance, Digits);
         double buy_sl = (StopLossPips > 0) ? NormalizeDouble(buy_price - sl_dist, Digits) : 0.0;
         double buy_tp = (TakeProfitPips > 0) ? NormalizeDouble(buy_price + tp_dist, Digits) : 0.0;
         
         if(OrderSend(Symbol(), OP_BUYLIMIT, Lots, buy_price, 10, buy_sl, buy_tp, "Grid BuyLimit", MagicNumber, 0, clrDodgerBlue) < 0)
            Print("Error opening BuyLimit: ", GetLastError());
            
         // SELL LIMIT
         double sell_price = NormalizeDouble(bid + distance, Digits);
         double sell_sl = (StopLossPips > 0) ? NormalizeDouble(sell_price + sl_dist, Digits) : 0.0;
         double sell_tp = (TakeProfitPips > 0) ? NormalizeDouble(sell_price - tp_dist, Digits) : 0.0;
         
         if(OrderSend(Symbol(), OP_SELLLIMIT, Lots, sell_price, 10, sell_sl, sell_tp, "Grid SellLimit", MagicNumber, 0, clrOrangeRed) < 0)
            Print("Error opening SellLimit: ", GetLastError());
        }
     }
     
   Print("Multiple pending orders grid executed successfully!");
   PlaySound("ok.wav");
  }
//+------------------------------------------------------------------+
