//+------------------------------------------------------------------+
//|                                                 VR Rsi Robot.mq5 |
//|                                      Copyright 2026, Trading-Go. |
//+------------------------------------------------------------------+
#property copyright "@ Voldemar"                                      // Copyright notice
#property link      "https://www.mql5.com/en/users/voldemar"        // Author's profile link
#property version   "26.030"                                          // EA version number
#property strict                                                      // Enable strict compilation mode

// Input parameters (configurable via Expert Advisor properties)
input double          iLots             = 0.01;                       // Trading volume in lots (input)

input int             iRSI_Period_H1    = 12;                         // RSI period for H1 chart (input)
input ENUM_TIMEFRAMES iRSI_TimeFrame_H1 = PERIOD_H1;                  // Timeframe for the first RSI (H1) (input)

input int             iRSI_Period_D1    = 18;                         // RSI period for D1 chart (input)
input ENUM_TIMEFRAMES iRSI_TimeFrame_D1 = PERIOD_D1;                  // Timeframe for the second RSI (D1) (input)
 
input double          iRSI_Level_UP     = 80.0;                       // Overbought level (sell signal zone) (input)
input double          iRSI_Level_DW     = 20.0;                       // Oversold level (buy signal zone) (input)

input int             iMagicNumber      = 227;                        // Unique identifier for this EA's trades (input)
input int             iSlippage         = 30;                         // Allowed slippage in points (input)

// Global variables
double lt       = 0;                                                   // Corrected lot size after step adjustment (global)

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
// Adjust lot size to comply with symbol's volume step
   double stepvol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);     // Get the minimum volume step for the symbol
   if(stepvol > 0)                                                     // If stepvol is valid (greater than zero)
      lt = stepvol * (int)(iLots / stepvol);                           // Round down iLots to the nearest multiple of stepvol
// Ensure lot size is not less than minimum allowed
   if(lt < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))               // If corrected lot size is below the minimum allowed
      lt = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);               // Set lot size to the minimum allowed
   return(INIT_SUCCEEDED);                                              // Initialization successful, return success code
  }

//+------------------------------------------------------------------+
//| Expert tick function (executed on every new tick)               |
//+------------------------------------------------------------------+
void OnTick()
  {
   int total = OrdersTotal();                                          // Get the total number of open orders/positions
   int b_ticket = 0;                                                   // Initialize ticket number for buy position (0 means none)
   int s_ticket = 0;                                                   // Initialize ticket number for sell position (0 means none)

// Loop through all positions to find those belonging to this EA and symbol
   for(int i = 0; i < total; i++)                                      // Iterate over all orders by index
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))                     // Select the order by its position in the list
         if(OrderSymbol() == _Symbol)                                  // Check if the order's symbol matches the current chart symbol
            if(OrderMagicNumber() == iMagicNumber)                     // Check if the order's magic number matches the EA's magic number
              {
               if(OrderType() == OP_BUY)                               // If the selected order is a buy order
                  b_ticket = OrderTicket();                            // Store its ticket number as the existing buy position
               if(OrderType() == OP_SELL)                              // If the selected order is a sell order
                  s_ticket = OrderTicket();                            // Store its ticket number as the existing sell position
              }
   bool   signal_up   = false;                                          // Flag for buy signal, initially false
   bool   signal_dw   = false;                                          // Flag for sell signal, initially false
   double rsi_mass_h0 = -1;                                             // Variable to store current H1 RSI value (shift 1)
   double rsi_mass_h1 = -1;                                             // Variable to store previous H1 RSI value (shift 2)
   double rsi_mass_d0 = -1;                                             // Variable to store current D1 RSI value (shift 1) - note: currently assigned H1 value (likely bug)
   double rsi_mass_d1 = -1;                                             // Variable to store previous D1 RSI value (shift 2) - note: currently assigned H1 value (likely bug)

// ===
   if(b_ticket == 0 || s_ticket == 0)                                  // If there is no buy position OR no sell position (i.e., at least one side is free)
     {
      rsi_mass_h0 = iRSI(_Symbol,iRSI_TimeFrame_H1, iRSI_Period_H1, PRICE_CLOSE,1); // Get H1 RSI value for the most recent completed bar (shift 1)
      rsi_mass_h1 = iRSI(_Symbol,iRSI_TimeFrame_H1, iRSI_Period_H1, PRICE_CLOSE,2); // Get H1 RSI value for the previous completed bar (shift 2)
      rsi_mass_d0 = iRSI(_Symbol,iRSI_TimeFrame_H1, iRSI_Period_H1, PRICE_CLOSE,1); // BUG: should be D1, but uses H1 (copied incorrectly)
      rsi_mass_d1 = iRSI(_Symbol,iRSI_TimeFrame_H1, iRSI_Period_H1, PRICE_CLOSE,2); // BUG: should be D1, but uses H1 (copied incorrectly)
     }
// ===
   if(rsi_mass_h0 > 0 && rsi_mass_h1 > 0 && rsi_mass_d0 > 0 && rsi_mass_d1 > 0) // If all RSI values are valid (greater than zero)
     {
      if(b_ticket == 0)                                                 // If there is no existing buy position
         if(rsi_mass_h0 >= iRSI_Level_DW && rsi_mass_h0 > rsi_mass_h1) // Check H1 RSI: current above oversold and rising
            if(rsi_mass_d0 >= iRSI_Level_DW && rsi_mass_d0 > rsi_mass_d1) // Check "D1" RSI: current above oversold and rising (but uses H1 due to bug)
               signal_up = true;                                        // Set buy signal flag
      // ===
      if(s_ticket == 0)                                                 // If there is no existing sell position
         if(rsi_mass_h0 <= iRSI_Level_UP && rsi_mass_h0 < rsi_mass_h1) // Check H1 RSI: current below overbought and falling
            if(rsi_mass_d0 <= iRSI_Level_UP && rsi_mass_d0 < rsi_mass_d1) // Check "D1" RSI: current below overbought and falling (but uses H1 due to bug)
               signal_dw = true;                                        // Set sell signal flag

      // Execute buy signal
      if(signal_up)                                                     // If a buy signal is generated
        {
         if(s_ticket > 0)                                               // If there is an existing sell position
            if(OrderSelect(s_ticket,SELECT_BY_TICKET,MODE_TRADES))     // Select that sell order by ticket
               if(!OrderClose(s_ticket,OrderLots(),Ask,iSlippage,clrRed)) // Attempt to close the sell position
                  Print("Error N "+(string)GetLastError());            // If close fails, print the error number
         // ===
         if(CheckMargin(lt))                                            // Check if there is enough free margin for the trade
           {
            int ticket = OrderSend(_Symbol,OP_BUY,lt,Ask,iSlippage,0,0,"",iMagicNumber,NULL,clrBlue); // Send a buy order
            if(ticket<0)                                                // If order sending fails (ticket negative)
               Print("Error N "+(string)GetLastError());               // Print the error number
           }
        }

      // Execute sell signal
      if(signal_dw)                                                     // If a sell signal is generated
        {
         if(b_ticket > 0)                                               // If there is an existing buy position
            if(OrderSelect(b_ticket,SELECT_BY_TICKET,MODE_TRADES))     // Select that buy order by ticket
               if(!OrderClose(b_ticket,OrderLots(),Bid,iSlippage,clrRed)) // Attempt to close the buy position
                  Print("Error N "+(string)GetLastError());            // If close fails, print the error number
         // ===
         if(CheckMargin(lt))                                            // Check if there is enough free margin for the trade
           {
            int ticket = OrderSend(_Symbol,OP_SELL,lt,Bid,iSlippage,0,0,"",iMagicNumber,NULL,clrRed); // Send a sell order
            if(ticket<0)                                                // If order sending fails (ticket negative)
               Print("Error N "+(string)GetLastError());               // Print the error number
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
// Nothing to clean up here; indicator handles are released automatically
  }

//+------------------------------------------------------------------+
//| Check if there is enough free margin for the trade              |
//+------------------------------------------------------------------+
bool CheckMargin(double aLot)
  {
// ===
   if(aLot <= 0)                                                        // If lot size is zero or negative, invalid
      return (false);                                                   // Return false (margin check failed)

// ===
   double margin = 0, margin_free = 0;                                  // Declare variables for required margin and free margin
   if((margin = ::MarketInfo(_Symbol, MODE_MARGINREQUIRED)) > 0)       // Get margin required per 1 lot for the symbol, check it's positive
      if((margin_free = ::AccountFreeMargin()) > 0)                    // Get free margin available on the account, check it's positive
         if((margin * aLot) < (margin_free - 10))                      // If required margin for the desired lots is less than free margin minus a small safety buffer (10 units)
            return (true);                                              // Return true (enough margin)
   return (false);                                                      // Otherwise return false (not enough margin or error)
  }
//+------------------------------------------------------------------+