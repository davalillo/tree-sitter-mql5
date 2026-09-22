//+------------------------------------------------------------------+
//|                                          DemoContractSizer.mq5   |
//|  Demonstrates ContractSizer.mqh without risking any money: it    |
//|  simulates a balance path and shows, line by line, what the      |
//|  ladder, the floor and the breaker would do.                     |
//|                                                                  |
//|  The demonstration that matters is the last one: a DEPOSIT made  |
//|  in the middle of a drawdown. Run with InpDemoDeposit on and off |
//|  and compare — with the flow adjustment the breaker keeps seeing |
//|  the drop; without it, the protection disappears right there.    |
//+------------------------------------------------------------------+
#property copyright "Joao Prata Silva Yglesias"
#property link      "https://www.mql5.com/en/users/jotayglesias"
#property version   "1.00"
#property script_show_inputs

#include "ContractSizer.mqh"

input double InpBalancePerContract = 3000.0;  // Balance per contract
input double InpMinCapital         = 1500.0;  // Operating floor
input double InpMaxDrawdown        = 0.20;    // Breaker (fraction of the peak; 0 = off)
input bool   InpDemoDeposit        = true;    // Simulate a deposit in the middle of the drawdown

//--- The simulation does not use the class (it reads the real account). It
//--- reproduces the SAME arithmetic on an invented path, so the logic is visible.
struct State
  {
   double balance, peak, flows;
   bool   tripped;
  };

int Contracts(const State &s)
  {
   if(s.tripped)                    return(0);
   if(s.balance < InpMinCapital)    return(0);
   int c = (int)MathFloor(s.balance / InpBalancePerContract);
   return(c < 1 ? 1 : c);
  }

void OnStart()
  {
   // Path: rises to 30k, drops 22% to 23.4k, and recovers.
   double days[] = { 12000, 15000, 19000, 24000, 30000, 28500, 26000,
                     24500, 23400, 24000, 26500, 29000 };
   int    depositDay = 8;               // exactly at the bottom of the drawdown
   double deposit    = 9000.0;

   State s;
   s.balance = days[0]; s.peak = days[0]; s.flows = 0; s.tripped = false;

   Print("day   balance   peak      drop    contracts  event");
   Print("--------------------------------------------------------------");

   for(int i = 0; i < ArraySize(days); i++)
     {
      s.balance = days[i];
      string event = "";

      if(InpDemoDeposit && i == depositDay)
        {
         s.balance += deposit;
         // THE ADJUSTMENT: the deposit shifts the peak by the same amount. Without
         // this line the peak would stand still, the balance would jump, and the
         // drop would "vanish".
         s.peak  += deposit;
         s.flows += deposit;
         event = StringFormat("DEPOSIT of %.0f (peak shifted along)", deposit);
        }

      if(s.balance > s.peak) { s.peak = s.balance; }

      double drop = (s.peak > 0) ? (s.peak - s.balance) / s.peak : 0.0;
      if(InpMaxDrawdown > 0 && drop >= InpMaxDrawdown && !s.tripped)
        {
         s.tripped = true;
         event = (event == "" ? "" : event + " | ") + "BREAKER TRIPPED";
        }

      PrintFormat("%3d  %8.0f  %8.0f  %5.1f%%  %8d   %s",
                  i, s.balance, s.peak, 100.0 * drop, Contracts(s), event);
     }

   // --- and now the real class, on the account that is open ---------------
   Print("");
   Print("--- CContractSizer on YOUR account ----------------------------");
   CContractSizer sizer(InpBalancePerContract, 500, 1, InpMinCapital, InpMaxDrawdown,
                        "demo_contract_sizer_peak.txt");
   int allowed = sizer.ContractsToday(TimeLocal());
   PrintFormat("balance %.2f   peak %.2f   contracts allowed today: %d%s",
               AccountInfoDouble(ACCOUNT_BALANCE), sizer.Peak(), allowed,
               sizer.Tripped() ? "   [BREAKER TRIPPED]" : "");
   Print("(the peak lives in MQL5\\Files\\demo_contract_sizer_peak.txt and survives a restart)");

   Print("");
   if(InpDemoDeposit)
     {
      Print("Look at day 8: the deposit came in and the breaker KEPT seeing");
      Print("the drawdown, because the peak rose together with the cash.");
      Print("Run again with InpDemoDeposit off and compare the 'drop' column.");
     }
   else
     {
      Print("Without a deposit this is the clean path. Turn InpDemoDeposit on to see");
      Print("the case almost every breaker implementation gets wrong.");
     }
  }
//+------------------------------------------------------------------+
