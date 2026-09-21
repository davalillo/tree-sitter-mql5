//+------------------------------------------------------------------+
//|                                          AurumNeuro Vanguard.mq5 |
//|                               Copyright 2023-2025, Ritz_EANEHA™  |
//|                     Neural Risk Architect v1.0 – Gold Optimized  |
//+------------------------------------------------------------------+
#property copyright     "Copyright 2023-2025, Ritz_EANEHA"
#property link          "https://www.mql5.com/en/users/ritzfalih"
#property version       "1.0"
#property strict

// ARCHITECTURE CONSTANTS
#define L1_SIZE           1024
#define STATE_POOL_SIZE   65536
#define INPUT_NODES       5
#define HIDDEN_NODES      12
#define OUTPUT_NODES      3

enum ENUM_LOT_TYPE {
   FIX_LOT,          // FIX LOT
   RISK_PERCENT      // RISK PERCENT
};

// STRUCTURES
struct MarketState {
   double price;
   double velocity;
   double curvature;
   double entropy;
   double cpd;
   double hamiltonian;
   long   timestamp;
};

struct MLResult {
   double confidence;
   double tp_multiplier;
   double sl_multiplier;
};

/*
+------------------------------------------------------------------+
|                 EDUCATIONAL CODE DISCLAIMER                     |
+------------------------------------------------------------------+
| This source code is provided strictly for educational, learning, |
| research, and development purposes.                              |
|                                                                  |
| The published code is NOT intended to be considered a finished,  |
| production-ready trading system and should NOT be used directly  |
| for live trading without further development, modification,      |
| optimization, validation, and comprehensive testing.             |
|                                                                  |
| Users are responsible for reviewing the entire code,             |
| understanding its logic, adapting it to their own requirements,  |
| and performing appropriate backtesting, forward testing, and     |
| demo-account testing before considering any live deployment.     |
|                                                                  |
| Trading financial instruments, including XAUUSD / Gold, involves |
| substantial risk. Market conditions can change rapidly, and      |
| losses may exceed expectations due to volatility, spread,        |
| slippage, execution delays, leverage, gaps, liquidity conditions,|
| technical failures, or other market and operational factors.     |
|                                                                  |
| Past performance, backtest results, optimization results, or     |
| simulated performance do not guarantee or imply future results.  |
|                                                                  |
| The developer does not provide any guarantee regarding the       |
| profitability, accuracy, stability, reliability, or performance  |
| of this code or any modified version derived from it.            |
|                                                                  |
| By using, modifying, compiling, testing, or deploying this code, |
| the user acknowledges and accepts full responsibility for all    |
| trading decisions, risks, losses, damages, and consequences      |
| resulting from its use.                                          |
|                                                                  |
| The developer shall NOT be held responsible or liable for any    |
| direct or indirect loss, financial damage, account loss, missed  |
| opportunities, system failure, or other consequences arising     |
| from the use of this code for live or simulated trading.         |
|                                                                  |
| Always test thoroughly in a controlled environment and use       |
| appropriate risk management before considering any live use.     |
+------------------------------------------------------------------+
*/


input string          ___1___          = "--- Neural Advisor ---";
input double          InpLearningRate  = 0.01;        // Neural learning rate
input double          InpVetoThreshold = 0.45;        // Veto decision threshold
input double          InpCutlossThresh = 0.30;        // Cut-loss threshold

input string          ___2___          = "--- Gatekeeper Settings ---";
input int             CooldownSeconds  = 30;          // Minimum time between entries
input int             MaxSpreadPoints  = 200;         // Maximum allowed SPREAD (points)
input int             MagicNumber      = 12345;       // EA magic number

input string          ___3___          = "--- Money Management ---";
input ENUM_LOT_TYPE   InpLotType       = RISK_PERCENT;   // Lot sizing method
input double          InpFixedLot      = 0.01;           // Fixed lot size
input double          InpRiskPercent   = 1.0;            // Risk per trade (%)
input double          InpCommission    = 0.09;           // COMMISSION PER LOT (account currency)
input double          InpMaxSLPoints   = 1500.0;         // Maximum Stop Loss distance (points)
input double          InpMaxTPPoints   = 2500.0;         // Maximum Take Profit distance (points)

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input string          ___4___          = "--- Trailing Stop (ATR) ---";
input bool            InpUseTrailing   = false;        // Enable ATR trailing stop (default=true)
input int             InpATRPeriod     = 14;          // ATR calculation period
input double          InpATRStartMult  = 1.0;         // ATR multiplier to start trailing
input double          InpATRStepMult   = 0.1;         // ATR multiplier for trailing step
input bool            InpTrailingAggressive      = false;    // Enable aggressive trailing (default=true)
input double          InpAggressiveStartFactor   = 0.6;      // Aggressive start multiplier factor
input double          InpAggressiveStepFactor    = 0.4;      // Aggressive step multiplier
input double          InpSpeedThreshold      = 2.0;      // Speed ​​threshold (ATR multiplier)
input double          InpSpeedWidenFactor    = 1.8;      // Widening factor at high speeds
input int             InpSpeedLookbackTicks  = 10;       // Number of ticks to measure speed

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input string          ___5___          = "--- Risk-Reward (Hard Close Profit) ---";
input bool            InpUseRR         = true;        // Enable Risk-Reward target
input double          InpRRatio        = 1.0;         // Risk-Reward ratio

input string          ___6___          = "--- Debug Settings ---";
input bool            InpPrintDebug   = false;        // Enable debug messages
input int             InpDebugInterval = 5;           // Debug message interval (seconds)


datetime LastTradeTime     = 0;
ulong    LastTradeTick     = 0;
bool     TradeBusy         = false;
int      atr_handle        = INVALID_HANDLE;
datetime LastActionBarTime = 0;
int      LastPosCount      = 0;
double   point, tick_size, tick_value;

MarketState g_last_bar_state;
bool       g_state_saved = false;
datetime   g_last_train_bar = 0;
datetime   g_last_debug_time = 0;
datetime   g_last_trail_time = 0;   // last trailing SL update (throttle)


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DebugPrint(string msg)
{
   if(!InpPrintDebug) return;
   if(TimeCurrent() - g_last_debug_time >= InpDebugInterval) {
      Print(msg);
      g_last_debug_time = TimeCurrent();
   }
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CML_Advisor
{
private:
   double W_in_hid[INPUT_NODES][HIDDEN_NODES];
   double W_hid_out[HIDDEN_NODES][OUTPUT_NODES];
   double B_hid[HIDDEN_NODES];
   double B_out[OUTPUT_NODES];
   double lr;
   double hid_output[HIDDEN_NODES];
   double last_inputs[INPUT_NODES];
   double max_tp_scale, max_sl_scale;
   bool   scales_initialized;

   double Sigmoid(double x)
   {
      return 1.0 / (1.0 + MathExp(-x));
   }
   double SigmoidDerivative(double x)
   {
      return x * (1.0 - x);
   }
   double TanhDerivative(double x)
   {
      return 1.0 - (x * x);
   }
   double RandomWeight()
   {
      return ((double)MathRand() / 32767.0) * 2.0 - 1.0;
   }

public:
   CML_Advisor()
   {
      lr = InpLearningRate;
      MathSrand((uint)(MagicNumber > 0 ? MagicNumber : 20260909));
      for(int i=0; i<INPUT_NODES; i++)
         for(int j=0; j<HIDDEN_NODES; j++)
            W_in_hid[i][j] = RandomWeight();
      for(int j=0; j<HIDDEN_NODES; j++) {
         B_hid[j] = RandomWeight();
         for(int k=0; k<OUTPUT_NODES; k++)
            W_hid_out[j][k] = RandomWeight();
      }
      for(int k=0; k<OUTPUT_NODES; k++)
         B_out[k] = RandomWeight();
      scales_initialized = false;
      max_tp_scale = 3.0;
      max_sl_scale = 2.0;
   }

   void InitializeScales(double atr)
   {
      if(scales_initialized) return;
      double max_tp = 0, max_sl = 0;
      int bars = 100;
      double atr_arr[];
      ArrayResize(atr_arr, bars);
      if(CopyBuffer(atr_handle, 0, 0, bars, atr_arr) != bars) {
         DebugPrint("Failed to retrieve ATR for ML initialization; using default.");
         return;
      }
      for(int i=0; i<bars; i++) {
         double open  = iOpen(_Symbol, PERIOD_CURRENT, i);
         double close = iClose(_Symbol, PERIOD_CURRENT, i);
         double high  = iHigh(_Symbol, PERIOD_CURRENT, i);
         double low   = iLow(_Symbol, PERIOD_CURRENT, i);
         double range = MathAbs(close - open);
         double retrace = (close > open) ? (open - low) : (high - open);
         double atr_val = atr_arr[i];
         if(atr_val > 0) {
            double tp_ratio = range / atr_val;
            double sl_ratio = retrace / atr_val;
            if(tp_ratio > max_tp) max_tp = tp_ratio;
            if(sl_ratio > max_sl) max_sl = sl_ratio;
         }
      }
      if(max_tp > 0) max_tp_scale = max_tp * 1.2;
      if(max_sl > 0) max_sl_scale = max_sl * 1.2;
      scales_initialized = true;
      DebugPrint("ML scales: TP_max=" + DoubleToString(max_tp_scale,2) +
                 " SL_max=" + DoubleToString(max_sl_scale,2));
   }

   MLResult Predict(double v, double c, double e, double cpd, double h)
   {
      last_inputs[0] = MathArctan(v);
      last_inputs[1] = MathArctan(c);
      last_inputs[2] = MathArctan(e);
      last_inputs[3] = cpd / 10.0;
      last_inputs[4] = MathArctan(h);
      MLResult res;
      double final_output[OUTPUT_NODES] = {B_out[0], B_out[1], B_out[2]};
      for(int j=0; j<HIDDEN_NODES; j++) {
         double sum = B_hid[j];
         for(int i=0; i<INPUT_NODES; i++)
            sum += last_inputs[i] * W_in_hid[i][j];
         hid_output[j] = MathTanh(sum);
         for(int k=0; k<OUTPUT_NODES; k++)
            final_output[k] += hid_output[j] * W_hid_out[j][k];
      }
      res.confidence    = Sigmoid(final_output[0]);
      res.tp_multiplier = Sigmoid(final_output[1]) * max_tp_scale;
      res.sl_multiplier = Sigmoid(final_output[2]) * max_sl_scale;
      return res;
   }

   void Train(double target_dir, double target_tp_raw, double target_sl_raw)
   {
      if(!scales_initialized) return;
      double target_tp = MathMin(target_tp_raw / max_tp_scale, 1.0);
      double target_sl = MathMin(target_sl_raw / max_sl_scale, 1.0);
      double final_output[OUTPUT_NODES] = {B_out[0], B_out[1], B_out[2]};
      for(int j=0; j<HIDDEN_NODES; j++) {
         double sum = B_hid[j];
         for(int i=0; i<INPUT_NODES; i++)
            sum += last_inputs[i] * W_in_hid[i][j];
         hid_output[j] = MathTanh(sum);
         for(int k=0; k<OUTPUT_NODES; k++)
            final_output[k] += hid_output[j] * W_hid_out[j][k];
      }
      double pred_dir = Sigmoid(final_output[0]);
      double pred_tp  = Sigmoid(final_output[1]);
      double pred_sl  = Sigmoid(final_output[2]);
      double target[OUTPUT_NODES] = {target_dir, target_tp, target_sl};
      double pred[OUTPUT_NODES]   = {pred_dir, pred_tp, pred_sl};
      double error_out[OUTPUT_NODES], gradient_out[OUTPUT_NODES];
      for(int k=0; k<OUTPUT_NODES; k++) {
         error_out[k] = target[k] - pred[k];
         gradient_out[k] = error_out[k] * SigmoidDerivative(pred[k]);
         B_out[k] += lr * gradient_out[k];
      }
      for(int j=0; j<HIDDEN_NODES; j++) {
         double error_hid = 0;
         for(int k=0; k<OUTPUT_NODES; k++) {
            error_hid += gradient_out[k] * W_hid_out[j][k];
            W_hid_out[j][k] += lr * gradient_out[k] * hid_output[j];
         }
         double gradient_hid = error_hid * TanhDerivative(hid_output[j]);
         for(int i=0; i<INPUT_NODES; i++)
            W_in_hid[i][j] += lr * gradient_hid * last_inputs[i];
         B_hid[j] += lr * gradient_hid;
      }
   }
};

CML_Advisor ML_Brain;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CUMDE_Kernel
{
private:
   MarketState    m_pool[STATE_POOL_SIZE];
   MarketState    m_l1_buffer[L1_SIZE];
   ushort         m_free_ptr;
   int            m_head;
   double         m_cpd, m_hamiltonian, m_cpd_smooth, m_scale;
   bool           m_shadow_mode;
public:
   CUMDE_Kernel() : m_free_ptr(0), m_head(0), m_cpd(0.0),
      m_shadow_mode(true), m_cpd_smooth(0.0) {}
   void InitScale()
   {
      point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      m_scale = (point < 0.01) ? 1000.0 : 100.0;
   }
   void UpdateState(double price, double vol, double spread)
   {
      m_head = (m_head + 1) & (L1_SIZE - 1);
      double prev_price = m_l1_buffer[(m_head + L1_SIZE - 1) & (L1_SIZE - 1)].price;
      double vel = (price - prev_price) * m_scale;
      m_l1_buffer[m_head].price     = price;
      m_l1_buffer[m_head].velocity  = vel;
      m_l1_buffer[m_head].curvature = vel * 0.5;
      m_l1_buffer[m_head].entropy   = spread * vol;
      m_l1_buffer[m_head].timestamp = TimeCurrent();
   }
   void EvaluatePhysics()
   {
      double v = m_l1_buffer[m_head].velocity;
      double s = m_l1_buffer[m_head].entropy;
      double raw_cpd = MathAbs(v * (1.0 / (s + 0.0001)));
      double current_cpd = MathMin(raw_cpd, 10.0);
      m_cpd_smooth = 0.95 * m_cpd_smooth + 0.05 * current_cpd;
      m_cpd = m_cpd_smooth;
      m_hamiltonian = (v * v) + (s * 0.5);
      m_shadow_mode = (m_cpd < 0.60);
      m_l1_buffer[m_head].cpd        = m_cpd;
      m_l1_buffer[m_head].hamiltonian= m_hamiltonian;
   }
   MarketState GetCurrentState() const
   {
      return m_l1_buffer[m_head];
   }
   ENUM_ORDER_TYPE GetCausalDirection() const
   {
      return (m_l1_buffer[m_head].velocity > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   }
   bool IsInShadowMode() const
   {
      return m_shadow_mode;
   }
   double GetCPD() const
   {
      return m_cpd;
   }
};
CUMDE_Kernel UMDE;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CanTrade()
{
   if(TradeBusy) {
      DebugPrint("DEBUG: TradeBusy true");
      return false;
   }
   if(TimeCurrent() - LastTradeTime < CooldownSeconds) {
      DebugPrint("DEBUG: Cooldown not passed");
      return false;
   }
   ulong tick = GetTickCount64();
   if(tick == LastTradeTick) {
      DebugPrint("DEBUG: Same tick");
      return false;
   }
   LastTradeTick = tick;
   return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool SpreadOK()
{
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
                    SymbolInfoDouble(_Symbol, SYMBOL_BID)) / point;
   bool ok = (spread <= MaxSpreadPoints);
   if(!ok) DebugPrint("DEBUG: Spread too high: " + DoubleToString(spread,1));
   return ok;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool ProcessStateLocks()
{
   int current_pos = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         current_pos++;
   }
   datetime current_bar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(current_pos < LastPosCount) LastActionBarTime = current_bar;
   LastPosCount = current_pos;
   if(current_pos == 0 && current_bar > LastActionBarTime) {
      LastActionBarTime = 0;
      return false;
   }
   bool blocked = (current_pos > 0) || (current_bar <= LastActionBarTime);
   if(blocked) DebugPrint("DEBUG: ProcessStateLocks blocked, pos=" + IntegerToString(current_pos) +
                             " bar=" + TimeToString(current_bar) +
                             " lastAction=" + TimeToString(LastActionBarTime));
   return blocked;
}

//+------------------------------------------------------------------+
//| Hitung lot maksimum yang terjangkau berdasarkan free margin      |
//+------------------------------------------------------------------+
double GetMaxAffordableLot(ENUM_ORDER_TYPE type, double price)
{
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(free_margin <= 0.0) return 0.0;

   double margin_per_lot = 0.0;
   if(!OrderCalcMargin(type, _Symbol, 1.0, price, margin_per_lot))
      return 0.0;
   if(margin_per_lot <= 0.0) return 0.0;

   // Gunakan maksimal 50% dari free margin agar ada buffer
   double usable = free_margin * 0.5;
   double lots   = usable / margin_per_lot;

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step) * step;

   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(lots > max_lot) lots = max_lot;
   return lots;
}

//+------------------------------------------------------------------+
//| Hitung lot berdasarkan risk%, di-cap oleh free margin            |
//+------------------------------------------------------------------+
double GetLotSize(double sl_dist_price, ENUM_ORDER_TYPE type = ORDER_TYPE_BUY, double price = 0.0)
{
   double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step_lot <= 0) step_lot = 0.01;

   double lot = min_lot;

   // ---- Mode FIXED LOT ----
   if(InpLotType == FIX_LOT) {
      lot = MathFloor(InpFixedLot / step_lot) * step_lot;
      lot = MathMax(min_lot, MathMin(max_lot, lot));
   }
   // ---- Mode RISK PERCENT ----
   else {
      if(sl_dist_price <= 0 || tick_size <= 0 || tick_value <= 0) {
         DebugPrint("DEBUG: invalid SL/tick params, fallback to min_lot");
         lot = min_lot;
      }
      else {
         double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
         double risk_amount = balance * (InpRiskPercent / 100.0);
         double sl_ticks    = sl_dist_price / tick_size;
         if(sl_ticks <= 0) sl_ticks = 1.0;

         double raw_lot = risk_amount / (sl_ticks * tick_value);
         lot = MathFloor(raw_lot / step_lot) * step_lot;
         lot = MathMax(min_lot, MathMin(max_lot, lot));
      }
   }

   // ---- CAP oleh free margin ----
   if(price <= 0.0)
      price = (type == ORDER_TYPE_BUY) ?
              SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
              SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double affordable = GetMaxAffordableLot(type, price);
   if(affordable < min_lot) {
      Print("Not enough free margin to open even min_lot. Free=",
            DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE),2));
      return 0.0; // Sinyal: jangan trade
   }
   if(lot > affordable) {
      lot = MathFloor(affordable / step_lot) * step_lot;
      DebugPrint("Lot capped by free margin to " + DoubleToString(lot,2));
   }

   return lot;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetMinProfitPoints(double lot)
{
   if(tick_value <= 0 || point <= 0) return 10.0; // fallback
   double total_commission = (lot / 0.01) * InpCommission;
   double target_currency = total_commission * 2.0;
   return (target_currency / tick_value) * (tick_size / point);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action = TRADE_ACTION_DEAL;
   req.position = ticket;
   req.symbol = _Symbol;
   req.volume = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   req.type = (pos_type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.price = (req.type == ORDER_TYPE_SELL) ?
               SymbolInfoDouble(_Symbol, SYMBOL_BID) :
               SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) req.type_filling = ORDER_FILLING_FOK;
   else if((filling & SYMBOL_FILLING_IOC) != 0) req.type_filling = ORDER_FILLING_IOC;
   else req.type_filling = ORDER_FILLING_RETURN;
   req.magic = MagicNumber;
   bool success = OrderSend(req, res);
   if(!success)
      Print("ClosePosition failed: ", GetLastError(), " Retcode: ", res.retcode);
   return success;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
   if(!InpUseTrailing) return;
   // Throttle: avoid per-tick SL modification spam (max 1 update / 5 sec)
   if(TimeCurrent() - g_last_trail_time < 5) return;
   g_last_trail_time = TimeCurrent();
   double atr[];
   if(CopyBuffer(atr_handle, 0, 0, 1, atr) < 1) return;
   double atrPoints = atr[0] / point;
   // Calculate the current price velocity.
   double speed = 0.0;
   if(InpSpeedLookbackTicks > 1) {
      double price_now = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double price_prev = iClose(_Symbol, PERIOD_CURRENT, 1); // alternative: price a few ticks ago
      // Or use the price from the previous tick: it can be stored globally.
      // Here, we use a comparison with the closing price of the previous bar.
      speed = MathAbs(price_now - price_prev) / (atr[0] + 0.000001);
   }
   double startPoints = InpATRStartMult * atrPoints;
   double stepPoints  = InpATRStepMult  * atrPoints;
   // If aggressive mode is active, reduce start & step.
   if(InpTrailingAggressive) {
      startPoints *= InpAggressiveStartFactor;
      stepPoints  *= InpAggressiveStepFactor;
   }
   // If the speed exceeds the threshold, widen the step.
   if(speed > InpSpeedThreshold) {
      stepPoints *= InpSpeedWidenFactor;
   }
   // Ensure the step is at least 1 point.
   if(stepPoints < 1.0) stepPoints = 1.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      double currentSL  = PositionGetDouble(POSITION_SL);
      double currentTP  = PositionGetDouble(POSITION_TP);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profitPoints = (posType == POSITION_TYPE_BUY) ?
                            (bid - entryPrice) / point :
                            (entryPrice - ask) / point;
      if(profitPoints < startPoints) continue;
      double newSL = 0.0;
      if(posType == POSITION_TYPE_BUY) {
         newSL = bid - stepPoints * point;
         if(newSL <= currentSL) continue;
      } else {
         newSL = ask + stepPoints * point;
         if(newSL >= currentSL) continue;
      }
      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action   = TRADE_ACTION_SLTP;
      req.symbol   = _Symbol;
      req.position = ticket;
      req.sl       = NormalizeDouble(newSL, _Digits);
      req.tp       = currentTP;
      req.magic    = MagicNumber;
      if(OrderSend(req, res))
         Print("Trailing updated ticket=", ticket, " to SL=", DoubleToString(newSL, _Digits));
   }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ManageHardCloseCutloss()
{
   MarketState state = UMDE.GetCurrentState();
   MLResult ml = ML_Brain.Predict(state.velocity, state.curvature,
                                  state.entropy, state.cpd, state.hamiltonian);
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) &&
         PositionGetString(POSITION_SYMBOL) == _Symbol) {
         long type = PositionGetInteger(POSITION_TYPE);
         double profit = PositionGetDouble(POSITION_PROFIT);
         if(profit < 0) {
            bool cutloss = false;
            if(type == POSITION_TYPE_BUY && ml.confidence < InpCutlossThresh)
               cutloss = true;
            if(type == POSITION_TYPE_SELL && ml.confidence > (1.0 - InpCutlossThresh))
               cutloss = true;
            if(cutloss) {
               Print("HARD CLOSE CUTLOSS triggered for ticket=", ticket);
               ClosePosition(ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ManageHardCloseProfit()
{
   if(!InpUseRR) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL  = PositionGetDouble(POSITION_SL);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(currentSL == 0) continue;
      double slPoints = (posType == POSITION_TYPE_BUY) ?
                        (entryPrice - currentSL) / point :
                        (currentSL - entryPrice) / point;
      if(slPoints <= 0) continue;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profitPoints = (posType == POSITION_TYPE_BUY) ?
                            (bid - entryPrice) / point :
                            (entryPrice - ask) / point;
      if(profitPoints >= InpRRatio * slPoints) {
         Print("RR hit: ticket=", ticket, " profit=", DoubleToString(profitPoints,1),
               " pts, SL=", DoubleToString(slPoints,1),
               " RR=", DoubleToString(InpRRatio,1));
         ClosePosition(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double lot, double sl, double tp)
{
   TradeBusy = true;
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.volume = lot;
   long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) req.type_filling = ORDER_FILLING_FOK;
   else if((filling & SYMBOL_FILLING_IOC) != 0) req.type_filling = ORDER_FILLING_IOC;
   else req.type_filling = ORDER_FILLING_RETURN;
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.type = type;
   req.price = (type == ORDER_TYPE_BUY) ?
               SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
               SymbolInfoDouble(_Symbol, SYMBOL_BID);
   req.sl = NormalizeDouble(sl, _Digits);
   req.tp = NormalizeDouble(tp, _Digits);
   req.magic = MagicNumber;
   if(!OrderSend(req, res)) {
      Print("Order Failed: ", GetLastError(), " Retcode: ", res.retcode);
   } else {
      LastTradeTime = TimeCurrent();
      LastActionBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
      Print("Order placed Ticket=", res.order, " Lot=", DoubleToString(lot,2));
   }
   TradeBusy = false;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   UMDE.InitScale();
   point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(point <= 0 || tick_size <= 0 || tick_value <= 0) {
      Print("Error: Invalid parameter symbol.");
      return INIT_FAILED;
   }
   atr_handle = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   if(atr_handle == INVALID_HANDLE) {
      Print("Failed to create ATR handle");
      return INIT_FAILED;
   }
   double atr_first[];
   if(CopyBuffer(atr_handle, 0, 0, 1, atr_first) == 1)
      ML_Brain.InitializeScales(atr_first[0]);
      // --- GUARD: Check the minimum capital to avoid a "no money" situation. ---
   double min_required = 100.0; // adjust (e.g., $100)
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal < min_required) {
      Print("WARNING: Balance ", DoubleToString(bal,2),
            " too small. EA requires a minimum ", DoubleToString(min_required,2));
      // This does not cause an initialization failure, but the entry will be automatically blocked by GetMaxAffordableLot().
   }
   Print("AurumNeuro Vanguard Ready");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(atr_handle != INVALID_HANDLE)
      IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
{
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t)) return;
   double mid = (t.bid + t.ask) * 0.5;
   UMDE.UpdateState(mid, (double)t.volume, t.ask - t.bid);
   UMDE.EvaluatePhysics();
   // --- Position management ---
   ApplyTrailingStop();
   ManageHardCloseCutloss();
   ManageHardCloseProfit();
   // --- Training ML ---
   datetime current_bar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(current_bar != g_last_train_bar) {
      if(g_state_saved) {
         double open_prev  = iOpen(_Symbol, PERIOD_CURRENT, 1);
         double close_prev = iClose(_Symbol, PERIOD_CURRENT, 1);
         double high_prev  = iHigh(_Symbol, PERIOD_CURRENT, 1);
         double low_prev   = iLow(_Symbol, PERIOD_CURRENT, 1);
         double atr_prev[];
         if(CopyBuffer(atr_handle, 0, 1, 1, atr_prev) == 1 && atr_prev[0] > 0) {
            double atr_val = atr_prev[0];
            double target_dir = (close_prev > open_prev) ? 1.0 : 0.0;
            double target_tp  = MathAbs(close_prev - open_prev) / atr_val;
            double target_sl  = (close_prev > open_prev) ?
                                (open_prev - low_prev) / atr_val :
                                (high_prev - open_prev) / atr_val;
            ML_Brain.Predict(g_last_bar_state.velocity,
                             g_last_bar_state.curvature,
                             g_last_bar_state.entropy,
                             g_last_bar_state.cpd,
                             g_last_bar_state.hamiltonian);
            ML_Brain.Train(target_dir, target_tp, target_sl);
         }
      }
      g_last_bar_state = UMDE.GetCurrentState();
      g_state_saved = true;
      g_last_train_bar = current_bar;
   }
      // --- GUARD: Check minimum free margin. ---
   if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < 10.0) {
      DebugPrint("DEBUG: Free margin too low, skip entry");
      return;
   }
   // --- Gatekeeper Entry ---
   if(PositionSelect(_Symbol)) {
      DebugPrint("DEBUG: Already has position, skip entry");
      return;
   }
   if(ProcessStateLocks()) {
      DebugPrint("DEBUG: ProcessStateLocks blocked");
      return;
   }
   if(!CanTrade()) {
      DebugPrint("DEBUG: CanTrade false");
      return;
   }
   if(!SpreadOK()) {
      DebugPrint("DEBUG: Spread not OK");
      return;
   }
   // --- Entry ---
   double cpd = UMDE.GetCPD();
   bool shadow = UMDE.IsInShadowMode();
   DebugPrint("DEBUG: CPD=" + DoubleToString(cpd,2) + " Shadow=" + (shadow ? "true" : "false"));
   if(cpd > 0.50 && !shadow) {
      ENUM_ORDER_TYPE umde_intent = UMDE.GetCausalDirection();
      MarketState state = UMDE.GetCurrentState();
      MLResult ml = ML_Brain.Predict(state.velocity, state.curvature,
                                     state.entropy, state.cpd, state.hamiltonian);
      bool ml_approves = false;
      if(umde_intent == ORDER_TYPE_BUY && ml.confidence > InpVetoThreshold)
         ml_approves = true;
      if(umde_intent == ORDER_TYPE_SELL && ml.confidence < (1.0 - InpVetoThreshold))
         ml_approves = true;
      DebugPrint("DEBUG: UMDE intent=" + EnumToString(umde_intent) +
                 " ML.conf=" + DoubleToString(ml.confidence,2) +
                 " Veto=" + DoubleToString(InpVetoThreshold,2) +
                 " Approved=" + (ml_approves ? "true" : "false"));
      if(ml_approves) {
         double atr[];
         if(CopyBuffer(atr_handle, 0, 0, 1, atr) < 1) return;
         double base_atr = atr[0];
         // SL calculation with a safety margin
         double sl_mult = MathMax(ml.sl_multiplier, 1.5); // minimal 1.5
         double pred_sl_points = (base_atr * sl_mult * 2.5) / point;
         double pred_tp_points;
         if(InpUseRR) {
            pred_tp_points = pred_sl_points * InpRRatio;
         } else {
            pred_tp_points = (base_atr * ml.tp_multiplier) / point;
         }
         // Limitation
         if(pred_tp_points > InpMaxTPPoints) pred_tp_points = InpMaxTPPoints;
         if(pred_sl_points > InpMaxSLPoints) pred_sl_points = InpMaxSLPoints;
         if(pred_sl_points < 10) pred_sl_points = 10;
         if(pred_tp_points < pred_sl_points * 1.2) // minimal TP > SL
            pred_tp_points = pred_sl_points * 1.5;
         // Minimum commission
         double temp_lot = (InpLotType == FIX_LOT) ? InpFixedLot : 0.01;
         double min_profit = GetMinProfitPoints(temp_lot);
         if(pred_tp_points < min_profit) pred_tp_points = min_profit + 20;
         if(pred_sl_points < min_profit) pred_sl_points = min_profit;
         //double final_lot = GetLotSize(pred_sl_points * point);
         double entry_price = (umde_intent == ORDER_TYPE_BUY) ? t.ask : t.bid;
         double final_lot = GetLotSize(pred_sl_points * point, umde_intent, entry_price);
if(final_lot <= 0.0) {
   DebugPrint("DEBUG: lot=0, skip entry (insufficient margin)");
   return;
}
         double sl = (umde_intent == ORDER_TYPE_BUY) ?
                     entry_price - (pred_sl_points * point) :
                     entry_price + (pred_sl_points * point);
         double tp = (umde_intent == ORDER_TYPE_BUY) ?
                     entry_price + (pred_tp_points * point) :
                     entry_price - (pred_tp_points * point);
         sl = NormalizeDouble(sl, _Digits);
         tp = NormalizeDouble(tp, _Digits);
         ExecuteTrade(umde_intent, final_lot, sl, tp);
         Print("Entry: TP=", DoubleToString(pred_tp_points,1),
               " SL=", DoubleToString(pred_sl_points,1),
               " Lot=", DoubleToString(final_lot,2));
      }
   } else {
      DebugPrint("DEBUG: CPD or Shadow blocked entry");
   }
}

//+------------------------------------------------------------------+
