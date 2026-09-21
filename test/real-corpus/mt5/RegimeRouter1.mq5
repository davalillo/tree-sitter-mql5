//+------------------------------------------------------------------+
//|                                               RegimeRouter.mq5   |
//|                                                     Ali Rajput   |
//|                                                                  |
//| RegimeRouter - a regime classifier that routes to two different  |
//| trading modules, and keeps a separate win-rate ledger per regime.|
//|                                                                  |
//| THE PROBLEM                                                      |
//| A trend-following rule loses money in a range. A mean-reversion  |
//| rule gets destroyed in a trend. Most EAs pick one and hope the   |
//| market cooperates. The usual fix is a single ADX filter, which   |
//| only measures one thing (directional strength) and says nothing  |
//| about whether returns are actually persistent or mean-reverting. |
//|                                                                  |
//| WHAT THIS DOES                                                   |
//| On every closed bar it measures three independent properties of  |
//| the recent price series:                                         |
//|                                                                  |
//|   1. ADX          - classic directional strength.                |
//|   2. Hurst        - rescaled-range (R/S) exponent of log returns.|
//|                     H above 0.5 means persistent (trending),     |
//|                     H below 0.5 means anti-persistent (mean      |
//|                     reverting), H = 0.5 is a random walk.        |
//|   3. Autocorr(1)  - lag-1 autocorrelation of returns. Positive   |
//|                     means a move tends to be followed by another |
//|                     move the same way; negative means it tends   |
//|                     to snap back.                                |
//|                                                                  |
//| Each of the three casts a vote: +1 trend, -1 range, 0 undecided. |
//| The votes are summed. If the sum clears InpMinVotes in either    |
//| direction the regime is TREND or RANGE; otherwise it is NEUTRAL  |
//| and the EA simply does not trade. Requiring agreement is the     |
//| whole point - one indicator alone is a coin flip with extra      |
//| steps.                                                           |
//|                                                                  |
//| The regime then selects which module is allowed to signal:       |
//|   TREND -> breakout module (a break of the N-bar high or low,    |
//|            taken only in the direction of the fast/slow MA)      |
//|   RANGE -> fade module (price z-score against its own moving     |
//|            average; buy the low tail, sell the high tail)        |
//|                                                                  |
//| THE LEDGER                                                       |
//| Every position is opened with a magic number of                  |
//| InpMagicBase + regime id, so the regime that produced a trade is |
//| permanently stamped on the trade and survives a restart. In      |
//| OnInit the EA walks the deal history, groups deals by position   |
//| id, and rebuilds a per-regime record of trades, wins and net     |
//| profit. Alongside the raw win rate it prints a Wilson 95% lower  |
//| bound, which is the honest number: with 6 trades a 66% win rate  |
//| is not evidence of anything, and the Wilson bound says so.       |
//|                                                                  |
//| That is what makes the routing decision auditable. After a run   |
//| you do not just see that the EA made money - you see whether the |
//| trend module or the fade module earned it, and whether either    |
//| has enough trades behind it to be believed.                      |
//|                                                                  |
//| RESEARCH SWITCH                                                  |
//| InpForceRegime disables the router and forces every trade        |
//| through one module (ALWAYS_TREND or ALWAYS_RANGE). Run the same  |
//| symbol and period three times - AUTO, ALWAYS_TREND, ALWAYS_RANGE |
//| - and you get a direct measurement of whether the classifier is  |
//| adding anything at all. Do that before trusting it. The routing  |
//| idea is a hypothesis, not a result.                              |
//|                                                                  |
//| EXECUTION NOTES                                                  |
//| Signals are evaluated on bar close only, so this is meant for    |
//| M15 and higher. Exits are left to the broker's own SL and TP;    |
//| there is no manual timed force-close, because a close request    |
//| that collides with one already in flight produces repeated       |
//| rejections under broker latency. Positions are opened with no    |
//| stops, then the stops are attached from the real fill price - a  |
//| stop computed from a pre-trade snapshot can already be invalid   |
//| by the time the order fills. If attaching the stops fails, the   |
//| position is closed immediately rather than left unprotected.     |
//|                                                                  |
//| One position at a time. On a netting account a second order on   |
//| the same symbol merges into the existing position instead of     |
//| becoming its own trade, which would silently corrupt the ledger. |
//|                                                                  |
//| MQL5's automatic validation always tests on EURUSD H1 whatever   |
//| the EA is written for. That is expected.                         |
//|                                                                  |
//| No strategy is guaranteed to be profitable. This is a structure  |
//| to test, with the measurement built in - not a promise.          |
//|                                                                  |
//|                                                     - Ali Rajput |
//+------------------------------------------------------------------+
#property copyright "Ali Rajput"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
#property description "Classifies the market with ADX + Hurst + autocorrelation, routes to a trend-following or a mean-reversion module, and keeps a separate win-rate ledger per regime."

#include <Trade/Trade.mqh>
CTrade trade;

//--- Regime ids. These are added to InpMagicBase, so they must stay
//--- stable across versions or an old history stops matching.
#define REGIME_NEUTRAL 0
#define REGIME_TREND   1
#define REGIME_RANGE   2
#define REGIME_COUNT   3

enum ENUM_ROUTER_MODE
  {
   ROUTER_AUTO,          // Auto - classify and route
   ROUTER_ALWAYS_TREND,  // Force trend module (A/B baseline)
   ROUTER_ALWAYS_RANGE   // Force range module (A/B baseline)
  };

input group "=== Regime Classifier ==="
input ENUM_ROUTER_MODE InpForceRegime = ROUTER_AUTO; // Routing mode (force one module to A/B the classifier)
input int    InpMinVotes              = 2;      // Votes needed (out of 3) to commit to a regime
input int    InpADXPeriod             = 14;     // ADX period
input double InpADXTrendLevel         = 25.0;   // ADX at or above this votes TREND
input double InpADXRangeLevel         = 20.0;   // ADX at or below this votes RANGE
input int    InpHurstBars             = 256;    // Bars of returns used for the Hurst estimate
input bool   InpHurstAdaptive         = false;  // Judge Hurst against its OWN recent distribution instead of the fixed levels (see note below)
input int    InpHurstCalibBars        = 200;    // How many past Hurst readings the adaptive band is built from
input double InpHurstUpperPct         = 60.0;   // Adaptive: above this percentile of its own history, Hurst votes TREND
input double InpHurstLowerPct         = 40.0;   // Adaptive: below this percentile, Hurst votes RANGE
input double InpHurstTrendLevel       = 0.55;   // Fixed band: Hurst at or above this votes TREND (used when adaptive is off)
input double InpHurstRangeLevel       = 0.45;   // Fixed band: Hurst at or below this votes RANGE (used when adaptive is off)
input int    InpAutoCorrBars          = 120;    // Bars of returns used for lag-1 autocorrelation
input double InpAutoCorrThreshold     = 0.05;   // Absolute autocorrelation must clear this to cast a vote

input group "=== Trend Module (used in the TREND regime) ==="
input int    InpBreakoutBars          = 20;     // Break of the highest high / lowest low of this many bars
input int    InpTrendFastMA           = 12;     // Fast MA - decides which way a breakout may be taken
input int    InpTrendSlowMA           = 34;     // Slow MA
input double InpTrendSLATRMult        = 1.5;    // Trend stop loss, in ATR
input double InpTrendTPATRMult        = 3.0;    // Trend take profit, in ATR
input bool   InpTrendUseTrailing      = true;   // Trail the stop once per bar while a trend trade is open
input double InpTrendTrailATRMult     = 2.0;    // Trailing distance, in ATR

input group "=== Range Module (used in the RANGE regime) ==="
input int    InpRangeMAPeriod         = 20;     // Mean and standard deviation window
input double InpRangeZEntry           = 2.0;    // Fade the move once the absolute z-score reaches this
input double InpRangeSLATRMult        = 1.5;    // Range stop loss, in ATR
input double InpRangeTPATRMult        = 1.2;    // Range take profit, in ATR

input group "=== Risk and Costs ==="
input double InpRiskPercent           = 0.5;    // Risk % of balance per trade
input int    InpATRPeriod             = 14;     // ATR period used for stop sizing
input int    InpMaxSpreadPoints       = 30;     // Skip the entry if the spread is wider than this
input double InpMinTPToSpreadRatio    = 4.0;    // Skip if the take profit is not at least this many spreads wide
input int    InpSlippagePoints        = 10;     // Maximum allowed slippage (points)
input ulong  InpMagicBase             = 772000; // Magic base. The regime id is added to it.

input group "=== Daily Safety Limits ==="
input int    InpMaxTradesPerDay       = 10;     // Hard cap on entries per day
input double InpDailyLossLimitPercent = 3.0;    // Stop new entries once today's loss reaches this % of the day's opening balance

input group "=== Session Filter (broker server time) ==="
input bool   InpUseSessionFilter      = false;  // Restrict new entries to a server-time window
input int    InpSessionStartHour      = 7;      // Session start hour (0-23)
input int    InpSessionEndHour        = 20;     // Session end hour (0-23)

input group "=== Display ==="
input bool   InpShowPanel             = true;   // Draw the live regime and ledger panel on the chart
input bool   InpVerboseLog            = true;   // Print every regime change and every closed trade

//--- indicator handles
int g_adxHandle  = INVALID_HANDLE;
int g_atrHandle  = INVALID_HANDLE;
int g_fastHandle = INVALID_HANDLE;
int g_slowHandle = INVALID_HANDLE;

//--- active position
ulong    g_activeTicket = 0;
int      g_activeRegime = REGIME_NEUTRAL;
int      g_activeDir    = 0;     // +1 buy, -1 sell
datetime g_activeBar    = 0;

//--- bar tracking
datetime g_lastBarTime = 0;

//--- daily counters
string g_dayKey          = "";
double g_dayStartBalance = 0.0;
int    g_tradesToday     = 0;

//--- last classification, kept for the panel
int    g_regime     = REGIME_NEUTRAL;
int    g_lastRegime = -1;
double g_lastADX    = 0.0;
double g_lastHurst  = 0.0;
double g_lastAC     = 0.0;
int    g_lastScore  = 0;

//--- per-regime ledger, indexed by regime id
int    g_ledTrades[REGIME_COUNT];
int    g_ledWins[REGIME_COUNT];
double g_ledNet[REGIME_COUNT];
double g_ledGrossWin[REGIME_COUNT];    // sum of the winning trades
double g_ledGrossLoss[REGIME_COUNT];   // sum of the losing trades, stored positive

//--- rolling history of Hurst readings, for the adaptive band
double g_hurstHist[];
double g_hurstLo = 0.0;
double g_hurstHi = 0.0;

//--- how many bars the classifier needs before it can say anything
int g_minBars = 0;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
string RegimeName(const int regime)
  {
   if(regime == REGIME_TREND) return "TREND";
   if(regime == REGIME_RANGE) return "RANGE";
   return "NEUTRAL";
  }

ulong MagicForRegime(const int regime)
  {
   return InpMagicBase + (ulong)regime;
  }

//--- returns -1 when the magic does not belong to this EA
int RegimeFromMagic(const long magic)
  {
   long diff = magic - (long)InpMagicBase;
   if(diff < 0 || diff >= REGIME_COUNT)
      return -1;
   return (int)diff;
  }

double GetPoint() { return SymbolInfoDouble(_Symbol, SYMBOL_POINT); }

//+------------------------------------------------------------------+
//| Smallest distance the broker will accept between the market and  |
//| a stop level. ATR-derived stops can come out tighter than this   |
//| on some symbols, which is exactly what an "Invalid stops"        |
//| rejection means.                                                 |
//+------------------------------------------------------------------+
double GetMinStopDistance(const string symbol)
  {
   double point       = SymbolInfoDouble(symbol, SYMBOL_POINT);
   long   stopsLevel  = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long   freezeLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   long   minPoints   = (long)MathMax((double)stopsLevel, (double)freezeLevel);
   return (double)minPoints * point;
  }

double ValuePerPoint(const string symbol)
  {
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(tickSize <= 0.0)
      return 0.0;
   return tickValue * (point / tickSize);
  }

double NormalizeLot(double lot, const string symbol)
  {
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      return 0.0;

   lot = MathFloor(lot / step) * step;
   if(lot > maxLot) lot = maxLot;
   if(lot < minLot) return 0.0;
   return NormalizeDouble(lot, 2);
  }

bool InSession()
  {
   if(!InpUseSessionFilter)
      return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(InpSessionStartHour <= InpSessionEndHour)
      return (dt.hour >= InpSessionStartHour && dt.hour < InpSessionEndHour);

   return (dt.hour >= InpSessionStartHour || dt.hour < InpSessionEndHour);
  }

void CheckDailyReset()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string todayKey = StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day);

   if(todayKey != g_dayKey)
     {
      g_dayKey          = todayKey;
      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_tradesToday     = 0;
     }
  }

//+------------------------------------------------------------------+
//| Wilson score interval, lower bound, at 95%.                      |
//|                                                                  |
//| A raw win rate of 3/4 and one of 300/400 are both 75%, but only  |
//| one of them is evidence. The Wilson lower bound is what is left  |
//| of the win rate after the sample size is taken into account, and |
//| it is the number worth routing decisions on.                     |
//+------------------------------------------------------------------+
double WilsonLowerBound(const int wins, const int n)
  {
   if(n <= 0)
      return 0.0;

   double z  = 1.96;
   double p  = (double)wins / (double)n;
   double z2 = z * z;

   double denom  = 1.0 + z2 / (double)n;
   double centre = p + z2 / (2.0 * (double)n);
   double margin = z * MathSqrt((p * (1.0 - p) + z2 / (4.0 * (double)n)) / (double)n);

   double lower = (centre - margin) / denom;
   if(lower < 0.0) lower = 0.0;
   return lower;
  }

//+------------------------------------------------------------------+
//| Indicator reads                                                  |
//+------------------------------------------------------------------+
//--- all reads use shift 1, the last CLOSED bar, never the forming one
bool ReadBuffer(const int handle, const int bufferIndex, const int shift, double &value)
  {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, bufferIndex, shift, 1, buf) < 1)
      return false;
   value = buf[0];
   return true;
  }

double GetATR()
  {
   double atr = 0.0;
   if(!ReadBuffer(g_atrHandle, 0, 1, atr))
      return 0.0;
   return atr;
  }

//+------------------------------------------------------------------+
//| Log returns of the last `count` closed bars, oldest first.       |
//+------------------------------------------------------------------+
bool GetLogReturns(const int count, double &rets[])
  {
   if(count < 2)
      return false;

   double closes[];
   ArraySetAsSeries(closes, false);           // oldest first
   if(CopyClose(_Symbol, _Period, 1, count + 1, closes) < count + 1)
      return false;

   ArrayResize(rets, count);
   for(int i = 0; i < count; i++)
     {
      if(closes[i] <= 0.0 || closes[i + 1] <= 0.0)
         return false;
      rets[i] = MathLog(closes[i + 1] / closes[i]);
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Hurst exponent by rescaled range (R/S) analysis.                 |
//|                                                                  |
//| For each block length n the series is cut into non-overlapping   |
//| blocks. Inside a block: subtract the block mean, take the        |
//| cumulative sum, and measure its range R. Divide R by the block's |
//| standard deviation S to get a scale-free R/S. Average R/S across |
//| the blocks, then repeat for larger n.                            |
//|                                                                  |
//| R/S grows like n^H, so a straight line fitted to log(R/S)        |
//| against log(n) has slope H. H near 0.5 is a random walk; above   |
//| 0.5 the series keeps going the way it was going; below 0.5 it    |
//| keeps reversing.                                                 |
//|                                                                  |
//| Returns false if there is not enough data for at least three     |
//| block lengths - two points would fit a line perfectly and mean   |
//| nothing.                                                         |
//+------------------------------------------------------------------+
bool HurstRS(const double &rets[], double &hurst)
  {
   int n = ArraySize(rets);
   if(n < 32)
      return false;

   double logN[], logRS[];
   ArrayResize(logN, 0);
   ArrayResize(logRS, 0);

   for(int blockLen = 8; blockLen <= n / 4; blockLen *= 2)
     {
      int blocks = n / blockLen;
      if(blocks < 1)
         break;

      double sumRS = 0.0;
      int    used  = 0;

      for(int b = 0; b < blocks; b++)
        {
         int offset = b * blockLen;

         double mean = 0.0;
         for(int i = 0; i < blockLen; i++)
            mean += rets[offset + i];
         mean /= (double)blockLen;

         double variance = 0.0;
         double cum      = 0.0;
         double minCum   = 0.0;
         double maxCum   = 0.0;

         for(int i = 0; i < blockLen; i++)
           {
            double dev = rets[offset + i] - mean;
            variance += dev * dev;
            cum      += dev;
            if(cum < minCum) minCum = cum;
            if(cum > maxCum) maxCum = cum;
           }

         variance /= (double)blockLen;
         double stddev = MathSqrt(variance);
         double range  = maxCum - minCum;

         if(stddev > 0.0 && range > 0.0)
           {
            sumRS += range / stddev;
            used++;
           }
        }

      if(used > 0)
        {
         double avgRS = sumRS / (double)used;
         if(avgRS > 0.0)
           {
            int k = ArraySize(logN);
            ArrayResize(logN,  k + 1);
            ArrayResize(logRS, k + 1);
            logN[k]  = MathLog((double)blockLen);
            logRS[k] = MathLog(avgRS);
           }
        }
     }

   int points = ArraySize(logN);
   if(points < 3)
      return false;

   //--- ordinary least squares slope of logRS on logN
   double sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumXX = 0.0;
   for(int i = 0; i < points; i++)
     {
      sumX  += logN[i];
      sumY  += logRS[i];
      sumXY += logN[i] * logRS[i];
      sumXX += logN[i] * logN[i];
     }

   double denom = (double)points * sumXX - sumX * sumX;
   if(MathAbs(denom) < 1e-12)
      return false;

   hurst = ((double)points * sumXY - sumX * sumY) / denom;
   return true;
  }

//+------------------------------------------------------------------+
//| Lag-1 autocorrelation of a return series.                        |
//+------------------------------------------------------------------+
bool Lag1AutoCorr(const double &rets[], double &rho)
  {
   int n = ArraySize(rets);
   if(n < 20)
      return false;

   double mean = 0.0;
   for(int i = 0; i < n; i++)
      mean += rets[i];
   mean /= (double)n;

   double num = 0.0, den = 0.0;
   for(int i = 0; i < n; i++)
     {
      double d = rets[i] - mean;
      den += d * d;
      if(i < n - 1)
         num += d * (rets[i + 1] - mean);
     }

   if(den <= 0.0)
      return false;

   rho = num / den;
   return true;
  }

//+------------------------------------------------------------------+
//| The adaptive Hurst band.                                         |
//|                                                                  |
//| Textbooks put the trend/range line at H = 0.5, because 0.5 is a  |
//| random walk. In practice that line is in the wrong place. The    |
//| R/S estimator is biased upward on a finite sample, so a 256-bar  |
//| estimate of an ordinary random-walk-ish series lands well above  |
//| 0.5 - measured on EURUSD H1 the readings averaged 0.568 and only |
//| dropped below 0.45 twice in 419 observations. Against a fixed    |
//| 0.45/0.55 band that voter is not measuring anything; it is a     |
//| near-permanent vote for TREND.                                   |
//|                                                                  |
//| So the adaptive band drops the absolute scale and asks a         |
//| relative question instead: is the series more persistent than    |
//| THIS symbol has recently been? The last InpHurstCalibBars        |
//| readings are kept, and the vote is cast on percentiles of that   |
//| history rather than on 0.5.                                      |
//|                                                                  |
//| The honest cost of this: by construction the voter now votes     |
//| TREND on roughly (100 - InpHurstUpperPct)% of bars and RANGE on  |
//| InpHurstLowerPct% of them, whatever the market is doing - so in  |
//| a market that genuinely trends for a year it will still call the |
//| calmest 40% of it RANGE. That is a real trade-off, not a free    |
//| improvement, which is why InpHurstAdaptive is a switch and not a |
//| rewrite. Run it both ways.                                       |
//+------------------------------------------------------------------+
void PushHurstReading(const double h)
  {
   int n = ArraySize(g_hurstHist);
   ArrayResize(g_hurstHist, n + 1);
   g_hurstHist[n] = h;

   int cap = InpHurstCalibBars;
   if(cap < 20)
      cap = 20;
   if(ArraySize(g_hurstHist) > cap)
      ArrayRemove(g_hurstHist, 0, ArraySize(g_hurstHist) - cap);
  }

int PercentileIndex(const int n, const double pct)
  {
   double p = pct;
   if(p < 0.0)   p = 0.0;
   if(p > 100.0) p = 100.0;

   int idx = (int)MathRound(p / 100.0 * (double)(n - 1));
   if(idx < 0)     idx = 0;
   if(idx > n - 1) idx = n - 1;
   return idx;
  }

//--- false until enough readings have been collected to have a
//--- distribution worth taking percentiles of
bool AdaptiveHurstBand(double &lo, double &hi)
  {
   int n = ArraySize(g_hurstHist);
   if(n < 50)
      return false;

   double sorted[];
   ArrayResize(sorted, n);
   ArrayCopy(sorted, g_hurstHist);
   ArraySort(sorted);

   lo = sorted[PercentileIndex(n, InpHurstLowerPct)];
   hi = sorted[PercentileIndex(n, InpHurstUpperPct)];

   return (hi > lo);
  }

//+------------------------------------------------------------------+
//| Classify the current regime.                                     |
//|                                                                  |
//| Three measurements, three votes, one sum. A measurement that     |
//| cannot be computed simply does not vote, rather than defaulting  |
//| to an opinion it has not earned.                                 |
//+------------------------------------------------------------------+
int ClassifyRegime()
  {
   int score = 0;
   int voters = 0;

   //--- vote 1: ADX
   double adx = 0.0;
   if(ReadBuffer(g_adxHandle, 0, 1, adx))
     {
      g_lastADX = adx;
      voters++;
      if(adx >= InpADXTrendLevel)      score += 1;
      else if(adx <= InpADXRangeLevel) score -= 1;
     }

   //--- vote 2: Hurst
   double hurstRets[];
   double hurst = 0.0;
   if(GetLogReturns(InpHurstBars, hurstRets) && HurstRS(hurstRets, hurst))
     {
      g_lastHurst = hurst;
      PushHurstReading(hurst);

      double lo = InpHurstRangeLevel;
      double hi = InpHurstTrendLevel;
      bool   bandReady = true;

      if(InpHurstAdaptive)
         bandReady = AdaptiveHurstBand(lo, hi);

      g_hurstLo = lo;
      g_hurstHi = hi;

      //--- while the adaptive band is still calibrating this voter stays
      //--- silent, which (all three must speak) means no trades yet
      if(bandReady)
        {
         voters++;
         if(hurst >= hi)      score += 1;
         else if(hurst <= lo) score -= 1;
        }
     }

   //--- vote 3: lag-1 autocorrelation
   double acRets[];
   double rho = 0.0;
   if(GetLogReturns(InpAutoCorrBars, acRets) && Lag1AutoCorr(acRets, rho))
     {
      g_lastAC = rho;
      voters++;
      if(rho >= InpAutoCorrThreshold)       score += 1;
      else if(rho <= -InpAutoCorrThreshold) score -= 1;
     }

   g_lastScore = score;

   //--- The measurements are taken even in a forced run, so the log and
   //--- the panel still show what the classifier WOULD have said. That is
   //--- the whole value of the A/B baseline: you get to see how the forced
   //--- module performed on the bars the router would have refused.
   if(InpForceRegime == ROUTER_ALWAYS_TREND) return REGIME_TREND;
   if(InpForceRegime == ROUTER_ALWAYS_RANGE) return REGIME_RANGE;

   //--- all three must be available; a two-voter majority is not the
   //--- agreement this EA is built on
   if(voters < 3)
      return REGIME_NEUTRAL;

   if(score >= InpMinVotes)  return REGIME_TREND;
   if(score <= -InpMinVotes) return REGIME_RANGE;
   return REGIME_NEUTRAL;
  }

//+------------------------------------------------------------------+
//| Trend module: a break of the N-bar extreme, taken only in the    |
//| direction the moving averages are already pointing.              |
//|                                                                  |
//| The MA pair is a direction filter, not a trigger. It stops the   |
//| module from buying an upside break that happens inside a down    |
//| leg, which is where breakout systems usually bleed.              |
//+------------------------------------------------------------------+
int TrendSignal()
  {
   double fast = 0.0, slow = 0.0;
   if(!ReadBuffer(g_fastHandle, 0, 1, fast)) return 0;
   if(!ReadBuffer(g_slowHandle, 0, 1, slow)) return 0;

   //--- the N bars BEFORE the bar that just closed
   int hiIdx = iHighest(_Symbol, _Period, MODE_HIGH, InpBreakoutBars, 2);
   int loIdx = iLowest(_Symbol, _Period, MODE_LOW,  InpBreakoutBars, 2);
   if(hiIdx < 0 || loIdx < 0)
      return 0;

   double priorHigh = iHigh(_Symbol, _Period, hiIdx);
   double priorLow  = iLow(_Symbol, _Period, loIdx);
   double lastClose = iClose(_Symbol, _Period, 1);

   if(priorHigh <= 0.0 || priorLow <= 0.0 || lastClose <= 0.0)
      return 0;

   if(fast > slow && lastClose > priorHigh) return  1;
   if(fast < slow && lastClose < priorLow)  return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| Range module: fade a stretched z-score back toward the mean.     |
//|                                                                  |
//| z is how many standard deviations the last close sits from its   |
//| own moving average, measured over the same window. A deep        |
//| negative z is bought, a high positive z is sold. In a genuine    |
//| range that is buying the low and selling the high; in a trend it |
//| is standing in front of a train, which is precisely why the      |
//| regime gate exists.                                              |
//+------------------------------------------------------------------+
int RangeSignal(double &zOut)
  {
   zOut = 0.0;

   int n = InpRangeMAPeriod;
   if(n < 5)
      return 0;

   double closes[];
   ArraySetAsSeries(closes, false);
   if(CopyClose(_Symbol, _Period, 1, n, closes) < n)
      return 0;

   double mean = 0.0;
   for(int i = 0; i < n; i++)
      mean += closes[i];
   mean /= (double)n;

   double variance = 0.0;
   for(int i = 0; i < n; i++)
      variance += (closes[i] - mean) * (closes[i] - mean);
   variance /= (double)n;

   double stddev = MathSqrt(variance);
   if(stddev <= 0.0)
      return 0;

   double lastClose = closes[n - 1];          // the bar that just closed
   double z = (lastClose - mean) / stddev;
   zOut = z;

   if(z <= -InpRangeZEntry) return  1;        // stretched low  -> buy
   if(z >=  InpRangeZEntry) return -1;        // stretched high -> sell
   return 0;
  }

//+------------------------------------------------------------------+
//| Ledger                                                           |
//+------------------------------------------------------------------+
void ResetLedger()
  {
   for(int i = 0; i < REGIME_COUNT; i++)
     {
      g_ledTrades[i]    = 0;
      g_ledWins[i]      = 0;
      g_ledNet[i]       = 0.0;
      g_ledGrossWin[i]  = 0.0;
      g_ledGrossLoss[i] = 0.0;
     }
  }

//+------------------------------------------------------------------+
//| Rebuild the per-regime ledger from closed deal history.          |
//|                                                                  |
//| Deals are grouped by DEAL_POSITION_ID because a single position  |
//| produces at least two deals (in and out) and its costs are split |
//| across them - commission usually lands on the entry deal, profit |
//| and swap on the exit. Summing per position is the only way to    |
//| get the real net of a trade. The regime is read back out of the  |
//| magic number, which is why the regime ids must never be          |
//| renumbered.                                                      |
//+------------------------------------------------------------------+
void RebuildLedgerFromHistory()
  {
   ResetLedger();

   if(!HistorySelect(0, TimeCurrent()))
      return;

   long   posIds[];
   double posNet[];
   int    posRegime[];
   bool   posClosed[];

   ArrayResize(posIds, 0);
   ArrayResize(posNet, 0);
   ArrayResize(posRegime, 0);
   ArrayResize(posClosed, 0);

   int totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;

      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
         continue;

      int regime = RegimeFromMagic(HistoryDealGetInteger(ticket, DEAL_MAGIC));
      if(regime <= REGIME_NEUTRAL)
         continue;

      long posId = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      if(posId == 0)
         continue;

      double net = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                 + HistoryDealGetDouble(ticket, DEAL_SWAP)
                 + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                 + HistoryDealGetDouble(ticket, DEAL_FEE);

      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      bool isExit = (entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY);

      //--- search backwards: the matching position is almost always recent
      int found = -1;
      for(int k = ArraySize(posIds) - 1; k >= 0; k--)
        {
         if(posIds[k] == posId)
           {
            found = k;
            break;
           }
        }

      if(found < 0)
        {
         found = ArraySize(posIds);
         ArrayResize(posIds,    found + 1);
         ArrayResize(posNet,    found + 1);
         ArrayResize(posRegime, found + 1);
         ArrayResize(posClosed, found + 1);
         posIds[found]    = posId;
         posNet[found]    = 0.0;
         posRegime[found] = regime;
         posClosed[found] = false;
        }

      posNet[found] += net;
      if(isExit)
         posClosed[found] = true;
     }

   for(int k = 0; k < ArraySize(posIds); k++)
     {
      if(!posClosed[k])
         continue;                              // still open, not a result yet

      int regime = posRegime[k];
      if(regime <= REGIME_NEUTRAL || regime >= REGIME_COUNT)
         continue;

      g_ledTrades[regime]++;
      g_ledNet[regime] += posNet[k];
      if(posNet[k] > 0.0)
        {
         g_ledWins[regime]++;
         g_ledGrossWin[regime] += posNet[k];
        }
      else
         g_ledGrossLoss[regime] -= posNet[k];
     }
  }

//+------------------------------------------------------------------+
//| One ledger line, ready to print or draw.                         |
//+------------------------------------------------------------------+
//| A module's win rate only means something next to the win rate it
//| NEEDS. A 2R trend follower is profitable at 34%; a 1R fade needs
//| better than 50%. So the line prints three numbers side by side:
//| the raw win rate, the Wilson 95% lower bound (what is left of it
//| after the sample size), and the breakeven win rate implied by this
//| module's own average win and average loss. The verdict is simply
//| whether the lower bound clears breakeven - which is the only
//| version of "this module works" that survives a small sample.
string LedgerLine(const int regime)
  {
   int    n    = g_ledTrades[regime];
   int    w    = g_ledWins[regime];
   int    l    = n - w;
   double raw  = (n > 0) ? 100.0 * (double)w / (double)n : 0.0;
   double wils = 100.0 * WilsonLowerBound(w, n);

   double grossWin  = g_ledGrossWin[regime];
   double grossLoss = g_ledGrossLoss[regime];

   double pf = 0.0;
   if(grossLoss > 0.0)
      pf = grossWin / grossLoss;

   double breakeven = 0.0;
   string verdict   = "no data";

   if(w > 0 && l > 0)
     {
      double avgWin  = grossWin / (double)w;
      double avgLoss = grossLoss / (double)l;
      if(avgWin + avgLoss > 0.0)
        {
         breakeven = 100.0 * avgLoss / (avgWin + avgLoss);
         verdict   = (wils > breakeven) ? "EDGE" : "UNPROVEN";
        }
     }
   else if(n > 0)
      verdict = "UNPROVEN";

   return StringFormat("%-7s %3d tr %3d W  raw %5.1f%%  wilson95 %5.1f%%  breakeven %5.1f%%  PF %4.2f  net %+9.2f  [%s]",
                       RegimeName(regime), n, w, raw, wils, breakeven, pf, g_ledNet[regime], verdict);
  }

void PrintLedger()
  {
   Print("---- RegimeRouter ledger (", _Symbol, ") ----");
   Print("  ", LedgerLine(REGIME_TREND));
   Print("  ", LedgerLine(REGIME_RANGE));
  }

void DrawPanel()
  {
   if(!InpShowPanel)
      return;

   string modeText = "AUTO";
   if(InpForceRegime == ROUTER_ALWAYS_TREND) modeText = "FORCED TREND";
   if(InpForceRegime == ROUTER_ALWAYS_RANGE) modeText = "FORCED RANGE";

   string openText = "none";
   if(g_activeTicket != 0)
      openText = StringFormat("%s module, %s", RegimeName(g_activeRegime), g_activeDir > 0 ? "BUY" : "SELL");

   string text = StringFormat(
      "RegimeRouter  [%s]\n"
      "Regime now : %s   (votes %+d, need %+d)\n"
      "ADX %.1f   Hurst %.3f (band %.3f-%.3f)   AC(1) %+.3f\n"
      "\n"
      "%s\n"
      "%s\n"
      "\n"
      "Trades today %d / %d\n"
      "Note: ledger prints wins out of trades, not wins out of total.",
      modeText,
      RegimeName(g_regime), g_lastScore, InpMinVotes,
      g_lastADX, g_lastHurst, g_hurstLo, g_hurstHi, g_lastAC,
      LedgerLine(REGIME_TREND),
      LedgerLine(REGIME_RANGE),
      openText,
      g_tradesToday, InpMaxTradesPerDay);

   Comment(text);
  }

//+------------------------------------------------------------------+
//| Position management                                              |
//+------------------------------------------------------------------+
//| Exits belong to the broker's SL and TP. This only notices that a |
//| position has gone, books the result against the regime that      |
//| opened it, and optionally trails the stop of a trend trade once  |
//| per bar. There is no timed force-close: repeatedly firing close  |
//| requests at a position while an earlier one is still in flight   |
//| is what produces collision rejections under broker latency.      |
//+------------------------------------------------------------------+
void OnPositionClosed()
  {
   double net = 0.0;
   if(HistorySelectByPosition(g_activeTicket))
     {
      int deals = HistoryDealsTotal();
      for(int i = 0; i < deals; i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0)
            continue;
         net += HistoryDealGetDouble(d, DEAL_PROFIT)
              + HistoryDealGetDouble(d, DEAL_SWAP)
              + HistoryDealGetDouble(d, DEAL_COMMISSION)
              + HistoryDealGetDouble(d, DEAL_FEE);
        }
     }

   int regime = g_activeRegime;
   if(regime > REGIME_NEUTRAL && regime < REGIME_COUNT)
     {
      g_ledTrades[regime]++;
      g_ledNet[regime] += net;
      if(net > 0.0)
        {
         g_ledWins[regime]++;
         g_ledGrossWin[regime] += net;
        }
      else
         g_ledGrossLoss[regime] -= net;
     }

   if(InpVerboseLog)
      PrintFormat("CLOSED  %s module  %s  net %+.2f  |  %s",
                  RegimeName(regime),
                  net > 0.0 ? "WIN" : "LOSS",
                  net,
                  LedgerLine(regime));

   g_activeTicket = 0;
   g_activeRegime = REGIME_NEUTRAL;
   g_activeDir    = 0;
  }

//+------------------------------------------------------------------+
//| Trail a trend trade's stop, at most once per bar, and only when  |
//| the new stop is both better than the old one and far enough from |
//| the market for the broker to accept it. A failure is logged and  |
//| dropped - the position already has a valid stop, so retrying     |
//| hard buys nothing and risks colliding with an in-flight request. |
//+------------------------------------------------------------------+
void TrailTrendStop()
  {
   if(!InpTrendUseTrailing)
      return;
   if(g_activeRegime != REGIME_TREND || g_activeTicket == 0)
      return;
   if(!PositionSelectByTicket(g_activeTicket))
      return;
   if(iTime(_Symbol, _Period, 0) == g_activeBar)
      return;                                   // never trail on the entry bar

   double atr = GetATR();
   if(atr <= 0.0)
      return;

   double trailDist  = InpTrendTrailATRMult * atr;
   double minStop    = GetMinStopDistance(_Symbol) * 1.5;
   if(trailDist < minStop)
      trailDist = minStop;

   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   long   type      = PositionGetInteger(POSITION_TYPE);
   int    digits    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point     = GetPoint();

   double newSL = 0.0;

   if(type == POSITION_TYPE_BUY)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      newSL = NormalizeDouble(bid - trailDist, digits);
      if(newSL <= currentSL + point) return;   // not an improvement
      if(bid - newSL < minStop)      return;   // too close for the broker to accept
     }
   else if(type == POSITION_TYPE_SELL)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      newSL = NormalizeDouble(ask + trailDist, digits);
      if(currentSL > 0.0 && newSL >= currentSL - point) return;   // not an improvement
      if(newSL - ask < minStop)                         return;   // too close for the broker to accept
     }
   else
      return;

   if(!trade.PositionModify(g_activeTicket, newSL, currentTP))
     {
      if(InpVerboseLog)
         PrintFormat("Trailing stop modify skipped: %d %s",
                     trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Entry                                                            |
//+------------------------------------------------------------------+
void TryEnter(const int regime)
  {
   if(regime <= REGIME_NEUTRAL)
      return;
   if(!InSession())
      return;
   if(g_tradesToday >= InpMaxTradesPerDay)
      return;

   //--- daily loss brake
   if(g_dayStartBalance > 0.0)
     {
      double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBalance;
      if(dayPnL <= -InpDailyLossLimitPercent / 100.0 * g_dayStartBalance)
         return;
     }

   //--- which module speaks for this regime
   int    dir = 0;
   double z   = 0.0;
   if(regime == REGIME_TREND)
      dir = TrendSignal();
   else
      dir = RangeSignal(z);

   if(dir == 0)
      return;

   double atr = GetATR();
   if(atr <= 0.0)
      return;

   double spreadPoints = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spreadPoints > InpMaxSpreadPoints)
      return;

   double point  = GetPoint();
   double slMult = (regime == REGIME_TREND) ? InpTrendSLATRMult : InpRangeSLATRMult;
   double tpMult = (regime == REGIME_TREND) ? InpTrendTPATRMult : InpRangeTPATRMult;

   double slDist = slMult * atr;
   double tpDist = tpMult * atr;

   //--- never send a stop tighter than the broker's own minimum
   double minStopDist = GetMinStopDistance(_Symbol) * 1.5;
   slDist = MathMax(slDist, minStopDist);
   tpDist = MathMax(tpDist, minStopDist);

   //--- a target the spread can eat is not a target
   if(tpDist < spreadPoints * point * InpMinTPToSpreadRatio)
      return;

   double valuePerPoint = ValuePerPoint(_Symbol);
   double slDistPoints  = slDist / point;
   if(valuePerPoint <= 0.0 || slDistPoints <= 0.0)
      return;

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;
   double lot        = NormalizeLot(riskAmount / (slDistPoints * valuePerPoint), _Symbol);
   if(lot <= 0.0)
      return;

   //--- the regime is stamped into the magic so the ledger can be
   //--- rebuilt from history later, on any machine, after any restart
   trade.SetExpertMagicNumber(MagicForRegime(regime));

   string comment = StringFormat("RR-%s", RegimeName(regime));

   //--- Open bare, attach stops from the REAL fill price. Stops computed
   //--- from a pre-trade snapshot can be invalid relative to the price
   //--- the order actually filled at once any latency is involved.
   bool sent = (dir > 0) ? trade.Buy(lot, _Symbol, 0.0, 0.0, 0.0, comment)
                         : trade.Sell(lot, _Symbol, 0.0, 0.0, 0.0, comment);

   if(!sent)
     {
      PrintFormat("Order failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return;
     }

   if(!PositionSelect(_Symbol))
     {
      Print("Order sent but the resulting position could not be found.");
      return;
     }

   ulong  newTicket = (ulong)PositionGetInteger(POSITION_TICKET);
   double fill      = PositionGetDouble(POSITION_PRICE_OPEN);
   int    digits    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double sl = (dir > 0) ? fill - slDist : fill + slDist;
   double tp = (dir > 0) ? fill + tpDist : fill - tpDist;
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   if(!trade.PositionModify(newTicket, sl, tp))
     {
      //--- An unprotected position is the one failure mode that can end an
      //--- account in a single trade. If the stop will not attach, the
      //--- position goes away now.
      PrintFormat("Failed to attach SL/TP (%d %s) - closing the position for safety.",
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
      if(!trade.PositionClose(newTicket))
         Print("WARNING: the unprotected position could not be closed either. Check it manually.");
      return;
     }

   g_activeTicket = newTicket;
   g_activeRegime = regime;
   g_activeDir    = dir;
   g_activeBar    = iTime(_Symbol, _Period, 0);
   g_tradesToday++;

   if(InpVerboseLog)
     {
      if(regime == REGIME_TREND)
         PrintFormat("ENTRY  TREND module  %s  fill %.5f  SL %.5f  TP %.5f  lot %.2f  |  ADX %.1f  H %.3f  AC %+.3f  votes %+d",
                     dir > 0 ? "BUY" : "SELL", fill, sl, tp, lot,
                     g_lastADX, g_lastHurst, g_lastAC, g_lastScore);
      else
         PrintFormat("ENTRY  RANGE module  %s  fill %.5f  SL %.5f  TP %.5f  lot %.2f  |  z %+.2f  ADX %.1f  H %.3f  AC %+.3f  votes %+d",
                     dir > 0 ? "BUY" : "SELL", fill, sl, tp, lot, z,
                     g_lastADX, g_lastHurst, g_lastAC, g_lastScore);

      PrintFormat("  prior record for this regime: %s", LedgerLine(regime));
     }
  }

//+------------------------------------------------------------------+
//| Lifecycle                                                        |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpMinVotes < 1 || InpMinVotes > 3)
     {
      Print("InpMinVotes must be 1, 2 or 3.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpTrendFastMA >= InpTrendSlowMA)
     {
      Print("InpTrendFastMA must be smaller than InpTrendSlowMA.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpHurstBars < 64)
     {
      Print("InpHurstBars must be at least 64 for a usable R/S estimate.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpRangeMAPeriod < 5 || InpBreakoutBars < 5)
     {
      Print("InpRangeMAPeriod and InpBreakoutBars must be at least 5.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpHurstAdaptive && InpHurstLowerPct >= InpHurstUpperPct)
     {
      Print("InpHurstLowerPct must be smaller than InpHurstUpperPct.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetExpertMagicNumber(InpMagicBase);

   //--- so the panel shows the fixed band until the adaptive one calibrates
   g_hurstLo = InpHurstRangeLevel;
   g_hurstHi = InpHurstTrendLevel;
   ArrayResize(g_hurstHist, 0);

   g_adxHandle  = iADX(_Symbol, _Period, InpADXPeriod);
   g_atrHandle  = iATR(_Symbol, _Period, InpATRPeriod);
   g_fastHandle = iMA(_Symbol, _Period, InpTrendFastMA, 0, MODE_EMA, PRICE_CLOSE);
   g_slowHandle = iMA(_Symbol, _Period, InpTrendSlowMA, 0, MODE_EMA, PRICE_CLOSE);

   if(g_adxHandle  == INVALID_HANDLE || g_atrHandle  == INVALID_HANDLE ||
      g_fastHandle == INVALID_HANDLE || g_slowHandle == INVALID_HANDLE)
     {
      Print("Failed to create one of the indicator handles.");
      return(INIT_FAILED);
     }

   g_minBars = InpHurstBars + 2;
   if(InpAutoCorrBars + 2 > g_minBars) g_minBars = InpAutoCorrBars + 2;
   if(InpTrendSlowMA  + 2 > g_minBars) g_minBars = InpTrendSlowMA  + 2;
   if(InpADXPeriod * 3    > g_minBars) g_minBars = InpADXPeriod * 3;
   if(InpBreakoutBars + 3 > g_minBars) g_minBars = InpBreakoutBars + 3;
   if(InpRangeMAPeriod+ 2 > g_minBars) g_minBars = InpRangeMAPeriod+ 2;

   //--- adopt an already-open position of ours, so a restart mid-trade
   //--- does not orphan it or misfile its result
   if(PositionSelect(_Symbol))
     {
      int regime = RegimeFromMagic(PositionGetInteger(POSITION_MAGIC));
      if(regime > REGIME_NEUTRAL)
        {
         g_activeTicket = (ulong)PositionGetInteger(POSITION_TICKET);
         g_activeRegime = regime;
         g_activeDir    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
        }
     }

   RebuildLedgerFromHistory();
   PrintLedger();
   DrawPanel();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_adxHandle  != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   if(g_atrHandle  != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_fastHandle != INVALID_HANDLE) IndicatorRelease(g_fastHandle);
   if(g_slowHandle != INVALID_HANDLE) IndicatorRelease(g_slowHandle);

   PrintLedger();
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   CheckDailyReset();

   //--- notice a closed position on any tick, so the ledger is current
   if(g_activeTicket != 0 && !PositionSelectByTicket(g_activeTicket))
     {
      OnPositionClosed();
      DrawPanel();
     }

   //--- everything else is bar-close work
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == g_lastBarTime)
      return;
   g_lastBarTime = barTime;

   if(Bars(_Symbol, _Period) < g_minBars)
      return;

   g_regime = ClassifyRegime();

   if(InpVerboseLog && g_regime != g_lastRegime)
     {
      PrintFormat("Regime -> %s   (votes %+d of 3, need %+d)   ADX %.1f  Hurst %.3f [band %.3f-%.3f]  AC(1) %+.3f",
                  RegimeName(g_regime), g_lastScore, InpMinVotes,
                  g_lastADX, g_lastHurst, g_hurstLo, g_hurstHi, g_lastAC);
      g_lastRegime = g_regime;
     }

   if(g_activeTicket != 0)
     {
      TrailTrendStop();
      DrawPanel();
      return;                                  // one position at a time
     }

   TryEnter(g_regime);
   DrawPanel();
  }
//+------------------------------------------------------------------+
