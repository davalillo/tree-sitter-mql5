//+------------------------------------------------------------------+
//|                                         SemiHFT_GridBot.mq4      |
//|  Reverse-engineered from a "Semi HFT Algo Trading bot" screen   |
//|  recording + annotated screenshots (NAS100 M1, then re-tuned    |
//|  live on XAUUSD).                                                |
//|                                                                  |
//|  STATE MACHINE:                                                  |
//|  PHASE 1 - SEED (flat): 3 pending levels each side, symmetric:  |
//|      Level1 (nearest)  lot = SeedLotNear                        |
//|      Level2/3          lot = SeedLotFar                         |
//|  PHASE 2 - BUMP: once one side's Level1 fills, the OPPOSITE     |
//|      side's Level2 pending lot is raised to RecoveryBumpLot.    |
//|  PHASE 3 - MARTINGALE: once either side reaches 2 fills, BOTH   |
//|      sides switch every still-pending level (2..5) to a         |
//|      doubling sequence off RecoveryBumpLot (x1,x2,x4,x8), and   |
//|      levels 4-5 are added. Already-filled levels are untouched. |
//|  BASKET TP/SL: floating P/L of everything this cycle is         |
//|      watched; hitting BasketTP_USD closes & cancels everything  |
//|      and a fresh SEED grid re-arms next tick.                   |
//|                                                                  |
//|  MULTI-SYMBOL SUPPORT (this revision):                          |
//|  NAS100/US100 (index CFDs) commonly have a much larger broker   |
//|  "stop level" (minimum distance for a pending order from        |
//|  price) than XAUUSD, and a different POINT size, so one set of  |
//|  lot/step inputs tuned for gold can silently fail to place any  |
//|  orders at all on an index. This version:                       |
//|    - keeps SEPARATE input blocks for XAUUSD and for NAS100/     |
//|      US100, auto-selected from the chart's symbol name (or      |
//|      forced via SymbolProfile),                                 |
//|    - widens the grid step automatically if it's narrower than   |
//|      the broker's MODE_STOPLEVEL for the current symbol, and    |
//|    - logs every failed OrderSend/OrderDelete/OrderClose with    |
//|      GetLastError() so a silent failure shows up in the Experts |
//|      log instead of just doing nothing.                         |
//|                                                                  |
//|  RISK WARNING: two-sided martingale grid, no built-in per-trade |
//|  stop loss. BasketSL_USD is OFF by default -- enable it and     |
//|  test on demo before running live, on either symbol.            |
//+------------------------------------------------------------------+
#property copyright "Wasim"
#property strict

//--------------------------- SYMBOL PROFILE ---------------------------
enum ENUM_PROFILE { PROFILE_AUTO, PROFILE_XAUUSD, PROFILE_NAS100 };
input ENUM_PROFILE SymbolProfile   = PROFILE_AUTO;  // AUTO detects from chart symbol name

//--------------------------- XAUUSD SETTINGS ---------------------------
input string   ____Metals____      = "===== XAUUSD / metals =====";
input double   Metals_SeedLotNear     = 0.02;
input double   Metals_SeedLotFar      = 0.01;
input double   Metals_RecoveryBumpLot = 0.05;
input int      Metals_GridStepPoints  = 50;    // 50pt * 0.01 point = $0.50 spacing
input int      Metals_MaxSpreadPoints = 40;

//--------------------------- NAS100 / US100 SETTINGS --------------------
input string   ____Index____       = "===== NAS100 / US100 =====";
input double   Index_SeedLotNear      = 0.20;
input double   Index_SeedLotFar       = 0.10;
input double   Index_RecoveryBumpLot  = 0.50;
input int      Index_GridStepPoints   = 50;    // re-check against your broker's index POINT size
input int      Index_MaxSpreadPoints  = 150;   // indices typically quote wider spreads in points

//--------------------------- SHARED SETTINGS ---------------------------
input string   ____Shared____      = "===== Shared =====";
input int      MagicNumber         = 990011;
input double   MartingaleMultiplier= 2.0;      // Doubling factor once martingale phase activates
input double   BasketTP_USD        = 2.00;     // Close everything when basket floating profit >= this
input double   BasketSL_USD        = 0;        // 0 = disabled. Emergency close if floating loss <= -this
input int      Slippage            = 5;
input bool     LogOrderErrors      = true;     // Print GetLastError() detail on any failed order

#define MAXLEV 5

//--------------------------- GLOBALS ---------------------------------
double point;
int    digits;
double g_basePrice     = 0;
bool   g_gridActive    = false;

double g_SeedLotNear, g_SeedLotFar, g_RecoveryBumpLot;
int    g_GridStepPoints, g_MaxSpreadPoints;

//+------------------------------------------------------------------+
int OnInit()
  {
   point  = MarketInfo(Symbol(), MODE_POINT);
   digits = (int)MarketInfo(Symbol(), MODE_DIGITS);

   ApplyProfile();

   if(CountOurOrders() > 0)
     {
      g_gridActive = true;
      g_basePrice  = RecoverBasePrice();
     }
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Pick XAUUSD vs NAS100/US100 settings, by name or by forced input |
//+------------------------------------------------------------------+
void ApplyProfile()
  {
   ENUM_PROFILE p = SymbolProfile;

   if(p == PROFILE_AUTO)
     {
      string s = Symbol();
      StringToUpper(s);
      if(StringFind(s, "XAU") >= 0)
         p = PROFILE_XAUUSD;
      else if(StringFind(s, "100") >= 0 || StringFind(s, "NAS") >= 0 ||
              StringFind(s, "USTEC") >= 0 || StringFind(s, "NDX") >= 0)
         p = PROFILE_NAS100;
      else
         p = PROFILE_XAUUSD; // fallback
     }

   if(p == PROFILE_NAS100)
     {
      g_SeedLotNear     = Index_SeedLotNear;
      g_SeedLotFar      = Index_SeedLotFar;
      g_RecoveryBumpLot = Index_RecoveryBumpLot;
      g_GridStepPoints  = Index_GridStepPoints;
      g_MaxSpreadPoints = Index_MaxSpreadPoints;
      Print("SemiHFT_GridBot: using NAS100/US100 profile for symbol ", Symbol());
     }
   else
     {
      g_SeedLotNear     = Metals_SeedLotNear;
      g_SeedLotFar      = Metals_SeedLotFar;
      g_RecoveryBumpLot = Metals_RecoveryBumpLot;
      g_GridStepPoints  = Metals_GridStepPoints;
      g_MaxSpreadPoints = Metals_MaxSpreadPoints;
      Print("SemiHFT_GridBot: using XAUUSD/metals profile for symbol ", Symbol());
     }

   // Respect the broker's minimum pending-order distance for THIS symbol.
   // Indices commonly need a much bigger stop level than metals -- if our
   // configured step is narrower than that, every OrderSend would just
   // fail silently, which is the classic "EA does nothing on NAS100" bug.
   int stopLevel = (int)MarketInfo(Symbol(), MODE_STOPLEVEL);
   int freezeLevel = (int)MarketInfo(Symbol(), MODE_FREEZELEVEL);
   int minRequired = (int)MathMax(stopLevel, freezeLevel) + 5; // +5pt safety buffer
   if(g_GridStepPoints < minRequired)
     {
      Print("SemiHFT_GridBot: GridStepPoints ", g_GridStepPoints,
            " is tighter than broker stop/freeze level for ", Symbol(),
            " (needs >= ", minRequired, "). Widening automatically.");
      g_GridStepPoints = minRequired;
     }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   ManageBasket();

   if(!g_gridActive)
      ArmSeedGrid();
   else
      ReconcileGrid();
  }

//+------------------------------------------------------------------+
string LevelTag(bool isBuy, int lvl)
  {
   return (isBuy ? "B" : "S") + IntegerToString(lvl);
  }

//+------------------------------------------------------------------+
int GetLevelInfo(bool isBuy, int lvl, int &ticket, double &lot)
  {
   string tag = LevelTag(isBuy, lvl);
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderComment() != tag) continue;

      ticket = OrderTicket();
      lot    = OrderLots();
      int t  = OrderType();
      if(t == OP_BUY || t == OP_SELL) return(2);
      if(t == OP_BUYSTOP || t == OP_SELLSTOP) return(1);
     }
   return(0);
  }

//+------------------------------------------------------------------+
int CountOurOrders()
  {
   int cnt = 0;
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      cnt++;
     }
   return cnt;
  }

//+------------------------------------------------------------------+
double RecoverBasePrice()
  {
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderComment() == "B1") return(OrderOpenPrice() - g_GridStepPoints * point);
      if(OrderComment() == "S1") return(OrderOpenPrice() + g_GridStepPoints * point);
     }
   return((Bid + Ask) / 2.0);
  }

//+------------------------------------------------------------------+
double BasketFloatingProfit()
  {
   double total = 0;
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
         total += OrderProfit() + OrderSwap() + OrderCommission();
     }
   return total;
  }

//+------------------------------------------------------------------+
void CloseBasket()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;

      int type = OrderType();
      bool ok;
      if(type == OP_BUY)
         ok = OrderClose(OrderTicket(), OrderLots(), Bid, Slippage, clrRed);
      else if(type == OP_SELL)
         ok = OrderClose(OrderTicket(), OrderLots(), Ask, Slippage, clrRed);
      else
         ok = OrderDelete(OrderTicket());

      if(!ok) LogOrderError("CloseBasket", OrderTicket());
     }
   g_gridActive = false;
  }

//+------------------------------------------------------------------+
void ManageBasket()
  {
   if(CountOurOrders() == 0) { g_gridActive = false; return; }

   double pl = BasketFloatingProfit();

   if(BasketTP_USD > 0 && pl >= BasketTP_USD)
     {
      Print("Basket TP hit: ", pl, " -> closing all & starting again");
      CloseBasket();
      return;
     }
   if(BasketSL_USD > 0 && pl <= -MathAbs(BasketSL_USD))
     {
      Print("Basket SL hit: ", pl, " -> closing all (safety stop)");
      CloseBasket();
      return;
     }
  }

//+------------------------------------------------------------------+
double NormalizeLot(double lots)
  {
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot   = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot   = MarketInfo(Symbol(), MODE_MAXLOT);
   lots = MathRound(lots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   return(NormalizeDouble(lots, 2));
  }

//+------------------------------------------------------------------+
void LogOrderError(string context, int ticketOrZero)
  {
   if(!LogOrderErrors) return;
   Print("SemiHFT_GridBot ERROR in ", context, " ticket=", ticketOrZero,
         " err=", GetLastError(), " (", Symbol(), ")");
  }

//+------------------------------------------------------------------+
//| Place (or resize) a level. If the market has already passed the  |
//| intended stop price -- common on fast-moving indices like USTEC  |
//| when several ticks/levels get skipped between reconcile calls -- |
//| a Buy/Sell Stop there would be rejected with error 130 forever.  |
//| In that case, fill it at market instead: the level's condition   |
//| ("price traded through here") has effectively already been met.  |
//+------------------------------------------------------------------+
void SafePlaceLevel(bool isBuy, int lvl, double lot, double price, string context)
  {
   int stopLevel = (int)MarketInfo(Symbol(), MODE_STOPLEVEL);
   double buffer = MathMax(stopLevel, 1) * point;

   bool passed;
   if(isBuy)
      passed = (price <= Ask + buffer);   // Buy Stop must sit above Ask
   else
      passed = (price >= Bid - buffer);   // Sell Stop must sit below Bid

   int t;
   if(!passed)
     {
      int ordType = isBuy ? OP_BUYSTOP : OP_SELLSTOP;
      t = OrderSend(Symbol(), ordType, lot, price, Slippage, 0, 0,
                    LevelTag(isBuy, lvl), MagicNumber, 0, isBuy ? clrBlue : clrRed);
      if(t < 0) LogOrderError(context + " (stop) " + LevelTag(isBuy, lvl), 0);
     }
   else
     {
      // Level already breached by price movement -> treat as triggered, fill at market
      double execPrice = isBuy ? Ask : Bid;
      int ordType = isBuy ? OP_BUY : OP_SELL;
      t = OrderSend(Symbol(), ordType, lot, execPrice, Slippage, 0, 0,
                    LevelTag(isBuy, lvl), MagicNumber, 0, isBuy ? clrBlue : clrRed);
      if(t < 0)
         LogOrderError(context + " (market fallback) " + LevelTag(isBuy, lvl), 0);
      else
         Print("SemiHFT_GridBot: ", LevelTag(isBuy, lvl), " target ", price,
               " already passed by price -> filled at market ", execPrice, " instead");
     }
  }

//+------------------------------------------------------------------+
//| PHASE 1: flat -> lay the symmetric seed ladder                   |
//+------------------------------------------------------------------+
void ArmSeedGrid()
  {
   double spread = (Ask - Bid) / point;
   if(spread > g_MaxSpreadPoints) return;

   g_basePrice = (Bid + Ask) / 2.0;

   for(int lvl = 1; lvl <= 3; lvl++)
     {
      double lot = (lvl == 1) ? g_SeedLotNear : g_SeedLotFar;

      double buyPrice = NormalizeDouble(g_basePrice + lvl * g_GridStepPoints * point, digits);
      SafePlaceLevel(true, lvl, NormalizeLot(lot), buyPrice, "ArmSeedGrid");

      double sellPrice = NormalizeDouble(g_basePrice - lvl * g_GridStepPoints * point, digits);
      SafePlaceLevel(false, lvl, NormalizeLot(lot), sellPrice, "ArmSeedGrid");
     }

   g_gridActive = true;
  }

//+------------------------------------------------------------------+
//| PHASE 2/3: every tick, self-heal the pending ladder               |
//+------------------------------------------------------------------+
void ReconcileGrid()
  {
   int ticket; double lot;

   int buyFills = 0, sellFills = 0;
   for(int lvl = 1; lvl <= MAXLEV; lvl++)
     {
      if(GetLevelInfo(true,  lvl, ticket, lot) == 2) buyFills++;
      if(GetLevelInfo(false, lvl, ticket, lot) == 2) sellFills++;
     }

   bool martingale = (buyFills >= 2 || sellFills >= 2);
   int  maxLevelToEnsure = martingale ? MAXLEV : 3;

   for(int side = 0; side < 2; side++)
     {
      bool isBuy          = (side == 0);
      int  fillsOtherSide = isBuy ? sellFills : buyFills;

      for(int lvl = 1; lvl <= maxLevelToEnsure; lvl++)
        {
         int status = GetLevelInfo(isBuy, lvl, ticket, lot);
         if(status == 2) continue;

         double targetLot;
         if(!martingale)
           {
            targetLot = (lvl == 1) ? g_SeedLotNear : g_SeedLotFar;
            if(lvl == 2 && fillsOtherSide >= 1) targetLot = g_RecoveryBumpLot;
           }
         else
           {
            if(lvl == 1)
               targetLot = g_SeedLotNear;
            else
               targetLot = g_RecoveryBumpLot * MathPow(MartingaleMultiplier, lvl - 2);
           }
         targetLot = NormalizeLot(targetLot);

         double price = NormalizeDouble(g_basePrice + (isBuy ? 1 : -1) * lvl * g_GridStepPoints * point, digits);

         if(status == 0)
           {
            SafePlaceLevel(isBuy, lvl, targetLot, price, "ReconcileGrid place");
           }
         else if(status == 1 && MathAbs(lot - targetLot) > 0.0000001)
           {
            bool delOk = OrderDelete(ticket);
            if(!delOk) LogOrderError("ReconcileGrid delete " + LevelTag(isBuy, lvl), ticket);
            SafePlaceLevel(isBuy, lvl, targetLot, price, "ReconcileGrid replace");
           }
        }
     }
  }
//+------------------------------------------------------------------+
