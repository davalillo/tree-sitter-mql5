//+------------------------------------------------------------------+
//|                                     Prop_ATR_Trail_Manager.mq4   |
//|                                     Copyright 2026, Amanda V     |
//+------------------------------------------------------------------+
#property copyright "Amanda V"
#property version   "1.00"
#property strict

//--- Inputs
input group "=== Volatility Trailing Settings ==="
input int    InpATRPeriod     = 14;      // ATR Period
input double InpATRMultiplier = 2.0;     // ATR Multiplier

input group "=== Breakeven Settings ==="
input bool   InpUseBreakeven  = true;    // Use Auto-Breakeven
input int    InpBEActivation  = 20;      // Pips in profit to activate BE
input int    InpBELockProfit  = 2;       // Pips to lock in profit (covers fees)

input group "=== Global Settings ==="
input int    InpMagicNumber   = 0;       // Magic Number (0 = Manual Trades)

double pt;
double pip_mult;

//+------------------------------------------------------------------+
int OnInit()
  {
   pt = Point;
   pip_mult = (Digits == 3 || Digits == 5) ? 10.0 : 1.0;
   Print("Institutional ATR Manager Initialized.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   double atr_value = iATR(Symbol(), 0, InpATRPeriod, 1);
   double trail_distance = atr_value * InpATRMultiplier;
   
   double be_activation_pts = InpBEActivation * pip_mult * pt;
   double be_lock_pts       = InpBELockProfit * pip_mult * pt;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && (InpMagicNumber == 0 || OrderMagicNumber() == InpMagicNumber))
           {
            double open_price = OrderOpenPrice();
            double current_sl = OrderStopLoss();
            int    type       = OrderType();
            
            //--- BUY ORDERS
            if(type == OP_BUY)
              {
               double bid = Bid;
               
               // 1. Breakeven Logic
               if(InpUseBreakeven && bid >= open_price + be_activation_pts)
                 {
                  double new_be_sl = open_price + be_lock_pts;
                  if(current_sl < new_be_sl && new_be_sl < bid)
                    {
                     bool res = OrderModify(OrderTicket(), open_price, new_be_sl, OrderTakeProfit(), 0, clrGreen);
                     if(res) current_sl = new_be_sl; // Update for trailing check
                    }
                 }
                 
               // 2. ATR Trailing Logic
               double new_trail_sl = bid - trail_distance;
               if(new_trail_sl > current_sl && new_trail_sl < bid)
                 {
                  // Only modify if difference is meaningful to prevent broker spam
                  if(current_sl == 0 || new_trail_sl - current_sl > (2 * pip_mult * pt))
                    {
                     OrderModify(OrderTicket(), open_price, new_trail_sl, OrderTakeProfit(), 0, clrBlue);
                    }
                 }
              }
              
            //--- SELL ORDERS
            else if(type == OP_SELL)
              {
               double ask = Ask;
               
               // 1. Breakeven Logic
               if(InpUseBreakeven && ask <= open_price - be_activation_pts)
                 {
                  double new_be_sl = open_price - be_lock_pts;
                  if(current_sl > new_be_sl || current_sl == 0)
                    {
                     if(new_be_sl > ask)
                       {
                        bool res = OrderModify(OrderTicket(), open_price, new_be_sl, OrderTakeProfit(), 0, clrGreen);
                        if(res) current_sl = new_be_sl;
                       }
                    }
                 }
                 
               // 2. ATR Trailing Logic
               double new_trail_sl = ask + trail_distance;
               if(current_sl == 0 || (new_trail_sl < current_sl && new_trail_sl > ask))
                 {
                  if(current_sl == 0 || current_sl - new_trail_sl > (2 * pip_mult * pt))
                    {
                     OrderModify(OrderTicket(), open_price, new_trail_sl, OrderTakeProfit(), 0, clrRed);
                    }
                 }
              }
           }
        }
     }
  }
//+------------------------------------------------------------------+