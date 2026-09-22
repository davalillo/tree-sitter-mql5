//+------------------------------------------------------------------+
//|                                                         Calc.mqh |
//|                    Risk Lot Calculator - position sizing maths   |
//|                              Copyright 2026, Ralph Ivan Simeon   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Ralph Ivan Simeon"
#property link      "https://www.mql5.com/en/users/84510755"

//--- Everything in this file is deliberately free of terminal state so
//--- that it can be exercised by the test script without a broker
//--- connection. SpecFromSymbol() is the only bridge to live data.

//+------------------------------------------------------------------+
//| Everything about an instrument the sizing maths needs            |
//+------------------------------------------------------------------+
struct SymbolSpec
  {
   double            point;       // SYMBOL_POINT
   double            tick_size;   // SYMBOL_TRADE_TICK_SIZE
   double            tick_value;  // account currency per tick_size, per 1.00 lot
   double            vol_min;
   double            vol_max;
   double            vol_step;
   int               digits;
  };

//+------------------------------------------------------------------+
//| Result of a sizing request                                       |
//+------------------------------------------------------------------+
struct LotResult
  {
   bool              valid;
   string            error;

   double            lots;         // normalised, actually tradable
   double            raw_lots;     // before stepping/clamping
   double            risk_money;   // what was asked for
   double            actual_risk;  // what `lots` really risks
   double            point_value;  // account currency per point per 1.00 lot
   double            sl_points;
   bool              clamped_min;  // sized below broker minimum
   bool              clamped_max;  // sized above broker maximum
  };

//+------------------------------------------------------------------+
//| Decimal places implied by a volume step (0.01 -> 2)              |
//+------------------------------------------------------------------+
int VolumeDigits(const double step)
  {
   if(step <= 0.0)
      return(2);

   double s = step;
   for(int d = 0; d < 8; d++)
     {
      if(MathAbs(s - MathRound(s)) < 1e-9)
         return(d);
      s *= 10.0;
     }
   return(8);
  }

//+------------------------------------------------------------------+
//| Account currency risked per point of movement, per 1.00 lot      |
//+------------------------------------------------------------------+
double PointValuePerLot(const SymbolSpec &spec)
  {
   if(spec.tick_size <= 0.0 || spec.tick_value <= 0.0 || spec.point <= 0.0)
      return(0.0);

   return(spec.tick_value * (spec.point / spec.tick_size));
  }

//+------------------------------------------------------------------+
//| Round a volume down onto the broker's step, then clamp           |
//+------------------------------------------------------------------+
double NormaliseVolume(const SymbolSpec &spec, const double volume,
                       bool &clamped_min, bool &clamped_max)
  {
   clamped_min = false;
   clamped_max = false;

   double step = (spec.vol_step > 0.0 ? spec.vol_step : 0.01);

//--- always round DOWN: rounding up would silently exceed the risk the
//--- trader asked for, which is the one thing this tool must never do
   double steps = MathFloor(volume / step + 1e-8);
   double v     = NormalizeDouble(steps * step, VolumeDigits(step));

   if(spec.vol_min > 0.0 && v < spec.vol_min)
     {
      v           = spec.vol_min;
      clamped_min = true;                 // NOTE: this now risks MORE than asked
     }

   if(spec.vol_max > 0.0 && v > spec.vol_max)
     {
      v           = spec.vol_max;
      clamped_max = true;                 // ...and this risks LESS
     }

   return(v);
  }

//+------------------------------------------------------------------+
//| Core: how many lots puts `risk_money` at stake between the entry |
//| and the stop?                                                    |
//+------------------------------------------------------------------+
LotResult CalcLots(const SymbolSpec &spec, const double risk_money,
                   const double entry, const double stop)
  {
   LotResult r;
   r.valid       = false;
   r.error       = "";
   r.lots        = 0.0;
   r.raw_lots    = 0.0;
   r.risk_money  = risk_money;
   r.actual_risk = 0.0;
   r.point_value = 0.0;
   r.sl_points   = 0.0;
   r.clamped_min = false;
   r.clamped_max = false;

   if(risk_money <= 0.0)
     {
      r.error = "Risk must be greater than zero";
      return(r);
     }

   if(spec.point <= 0.0)
     {
      r.error = "No point size for this symbol";
      return(r);
     }

   double pv = PointValuePerLot(spec);
   if(pv <= 0.0)
     {
      r.error = "No tick data - add the symbol to Market Watch";
      return(r);
     }
   r.point_value = pv;

   double distance = MathAbs(entry - stop);
   r.sl_points = distance / spec.point;

   if(r.sl_points < 1.0)
     {
      r.error = "Stop is too close to the entry";
      return(r);
     }

//--- loss taken if price travels the whole stop distance on 1.00 lot
   double loss_per_lot = r.sl_points * pv;
   if(loss_per_lot <= 0.0)
     {
      r.error = "Cannot value this stop distance";
      return(r);
     }

   r.raw_lots = risk_money / loss_per_lot;
   r.lots     = NormaliseVolume(spec, r.raw_lots, r.clamped_min, r.clamped_max);

   if(r.lots <= 0.0)
     {
      r.error = "Risk too small for the minimum lot";
      return(r);
     }

   r.actual_risk = r.lots * loss_per_lot;
   r.valid       = true;

   return(r);
  }

//+------------------------------------------------------------------+
//| Read a live symbol into a SymbolSpec                             |
//+------------------------------------------------------------------+
SymbolSpec SpecFromSymbol(const string symbol)
  {
   SymbolSpec spec;

   spec.point     = SymbolInfoDouble(symbol, SYMBOL_POINT);
   spec.tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   spec.vol_min   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   spec.vol_max   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   spec.vol_step  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   spec.digits    = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

//--- TICK_VALUE_LOSS is the figure the server uses when the trade goes
//--- against you, which is exactly the side a stop loss sits on. Some
//--- brokers leave it at zero, so fall back to the generic tick value.
   spec.tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(spec.tick_value <= 0.0)
      spec.tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

   return(spec);
  }

//+------------------------------------------------------------------+
//| Points -> pips, for the 3/5 digit brokers                        |
//+------------------------------------------------------------------+
double PointsToPips(const double points, const int digits)
  {
   if(digits == 3 || digits == 5)
      return(points / 10.0);

   return(points);
  }
//+------------------------------------------------------------------+
