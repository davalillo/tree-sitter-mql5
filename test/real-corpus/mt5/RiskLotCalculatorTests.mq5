//+------------------------------------------------------------------+
//|                                     RiskLotCalculatorTests.mq5   |
//|          Assertions over Calc.mqh - runs on any chart, offline   |
//|                              Copyright 2026, Ralph Ivan Simeon   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Ralph Ivan Simeon"
#property link      "https://www.mql5.com/en/users/84510755"
#property version   "1.00"

#include "Calc.mqh"

int g_pass = 0;
int g_fail = 0;

//+------------------------------------------------------------------+
void Check(const string what, const bool ok)
  {
   if(ok)
     {
      g_pass++;
      Print("  PASS  ", what);
     }
   else
     {
      g_fail++;
      Print("* FAIL  ", what);
     }
  }

//+------------------------------------------------------------------+
void CheckNear(const string what, const double got, const double want,
               const double tol = 1e-8)
  {
   bool ok = (MathAbs(got - want) <= tol);
   if(!ok)
      Print("* FAIL  ", what, "  got=", DoubleToString(got, 8),
            " want=", DoubleToString(want, 8));
   else
      Print("  PASS  ", what);

   if(ok) g_pass++; else g_fail++;
  }

//+------------------------------------------------------------------+
//| A 5-digit FX pair: 1 point on 1.00 lot is worth 1.00             |
//+------------------------------------------------------------------+
SymbolSpec SpecFx(void)
  {
   SymbolSpec s;
   s.point      = 0.00001;
   s.tick_size  = 0.00001;
   s.tick_value = 1.0;
   s.vol_min    = 0.01;
   s.vol_max    = 100.0;
   s.vol_step   = 0.01;
   s.digits     = 5;
   return(s);
  }

//+------------------------------------------------------------------+
//| Gold: 2 digits, 0.01 move on 1.00 lot is worth 1.00              |
//+------------------------------------------------------------------+
SymbolSpec SpecGold(void)
  {
   SymbolSpec s;
   s.point      = 0.01;
   s.tick_size  = 0.01;
   s.tick_value = 1.0;
   s.vol_min    = 0.01;
   s.vol_max    = 50.0;
   s.vol_step   = 0.01;
   s.digits     = 2;
   return(s);
  }

//+------------------------------------------------------------------+
//| An index quoted in whole points with a 0.1 lot step              |
//+------------------------------------------------------------------+
SymbolSpec SpecIndex(void)
  {
   SymbolSpec s;
   s.point      = 1.0;
   s.tick_size  = 1.0;
   s.tick_value = 1.0;
   s.vol_min    = 0.1;
   s.vol_max    = 20.0;
   s.vol_step   = 0.1;
   s.digits     = 0;
   return(s);
  }

//+------------------------------------------------------------------+
void OnStart(void)
  {
   Print("=== Risk Lot Calculator - Calc.mqh ===");

//------------------------------------------------------------------
   Print("-- VolumeDigits");
   Check("step 0.01 -> 2 dp", VolumeDigits(0.01) == 2);
   Check("step 0.1  -> 1 dp", VolumeDigits(0.1)  == 1);
   Check("step 1.0  -> 0 dp", VolumeDigits(1.0)  == 0);
   Check("step 0    -> 2 dp fallback", VolumeDigits(0.0) == 2);

//------------------------------------------------------------------
   Print("-- PointValuePerLot");
   SymbolSpec fx = SpecFx();
   CheckNear("fx point value", PointValuePerLot(fx), 1.0);

//--- a broker quoting tick size at 10x the point must halve nothing:
//--- one point is a tenth of a tick, so it is worth a tenth as much
   SymbolSpec coarse = SpecFx();
   coarse.tick_size  = 0.0001;
   coarse.tick_value = 1.0;
   CheckNear("point value scales with tick size", PointValuePerLot(coarse), 0.1);

   SymbolSpec dead = SpecFx();
   dead.tick_value = 0.0;
   CheckNear("no tick value -> 0", PointValuePerLot(dead), 0.0);

//------------------------------------------------------------------
   Print("-- NormaliseVolume");
   bool cmin = false, cmax = false;

   CheckNear("0.567 rounds DOWN to 0.56",
             NormaliseVolume(fx, 0.567, cmin, cmax), 0.56);
   Check("...and is not flagged as clamped", !cmin && !cmax);

   CheckNear("exact 0.50 survives",
             NormaliseVolume(fx, 0.50, cmin, cmax), 0.50);

   CheckNear("0.004 clamps up to the 0.01 minimum",
             NormaliseVolume(fx, 0.004, cmin, cmax), 0.01);
   Check("...and IS flagged as clamped_min", cmin);

   CheckNear("999 clamps to the 100 maximum",
             NormaliseVolume(fx, 999.0, cmin, cmax), 100.0);
   Check("...and IS flagged as clamped_max", cmax);

   SymbolSpec idx = SpecIndex();
   CheckNear("0.34 on a 0.1 step -> 0.3",
             NormaliseVolume(idx, 0.34, cmin, cmax), 0.3);

//------------------------------------------------------------------
   Print("-- CalcLots, the ordinary case");
//--- 100 at risk, stop 200 points away, 1.00 per point per lot
//--- => 200 per lot at risk => 0.50 lots
   LotResult r = CalcLots(fx, 100.0, 1.10000, 1.09800);
   Check("valid", r.valid);
   CheckNear("stop distance in points", r.sl_points, 200.0, 1e-6);
   CheckNear("lots", r.lots, 0.50, 1e-9);
   CheckNear("actual risk matches the request", r.actual_risk, 100.0, 1e-6);
   Check("not clamped", !r.clamped_min && !r.clamped_max);

   Print("-- CalcLots is side-agnostic");
   LotResult up = CalcLots(fx, 100.0, 1.09800, 1.10000);   // stop above entry
   CheckNear("same size selling as buying", up.lots, 0.50, 1e-9);

   Print("-- CalcLots on gold");
//--- 50 at risk, stop 5.00 away = 500 points, 1.00 per point => 0.10 lots
   LotResult g = CalcLots(SpecGold(), 50.0, 2400.00, 2395.00);
   Check("valid", g.valid);
   CheckNear("gold lots", g.lots, 0.10, 1e-9);
   CheckNear("gold risk", g.actual_risk, 50.0, 1e-6);

//------------------------------------------------------------------
   Print("-- CalcLots never rounds the risk UP");
//--- 100 / (300 * 1.00) = 0.3333... which must become 0.33, not 0.34
   LotResult down = CalcLots(fx, 100.0, 1.10000, 1.09700);
   CheckNear("rounded down", down.lots, 0.33, 1e-9);
   Check("resulting risk is under the request", down.actual_risk < 100.0);
   CheckNear("...by exactly one step's worth", down.actual_risk, 99.0, 1e-6);

//------------------------------------------------------------------
   Print("-- CalcLots flags a size the broker will not accept");
   LotResult tiny = CalcLots(fx, 1.0, 1.10000, 1.09800);
   Check("still valid (the trade is placeable)", tiny.valid);
   CheckNear("forced up to the minimum lot", tiny.lots, 0.01, 1e-9);
   Check("clamped_min is set", tiny.clamped_min);
   Check("and it now risks MORE than asked", tiny.actual_risk > tiny.risk_money);
   CheckNear("specifically 2.00", tiny.actual_risk, 2.0, 1e-6);

   LotResult huge = CalcLots(fx, 10000000.0, 1.10000, 1.09800);
   Check("clamped_max is set", huge.clamped_max);
   CheckNear("capped at vol_max", huge.lots, 100.0, 1e-9);

//------------------------------------------------------------------
   Print("-- CalcLots refuses the impossible");
   LotResult z = CalcLots(fx, 0.0, 1.10000, 1.09800);
   Check("zero risk rejected", !z.valid && StringLen(z.error) > 0);

   LotResult neg = CalcLots(fx, -5.0, 1.10000, 1.09800);
   Check("negative risk rejected", !neg.valid);

   LotResult same = CalcLots(fx, 100.0, 1.10000, 1.10000);
   Check("stop on top of entry rejected", !same.valid);

   LotResult nodata = CalcLots(dead, 100.0, 1.10000, 1.09800);
   Check("missing tick data rejected", !nodata.valid);

//------------------------------------------------------------------
   Print("-- PointsToPips");
   CheckNear("5 digits: 200 pts = 20 pips", PointsToPips(200, 5), 20.0);
   CheckNear("3 digits: 200 pts = 20 pips", PointsToPips(200, 3), 20.0);
   CheckNear("2 digits: 200 pts = 200 pips", PointsToPips(200, 2), 200.0);

//------------------------------------------------------------------
   Print("======================================");
   Print(g_fail == 0 ? "ALL PASS" : "FAILURES PRESENT",
         "   passed=", g_pass, "  failed=", g_fail);
  }
//+------------------------------------------------------------------+
