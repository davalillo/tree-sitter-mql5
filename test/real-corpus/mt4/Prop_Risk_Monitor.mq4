//+------------------------------------------------------------------+
//|                                     Prop_Risk_Monitor.mq4        |
//|                                     Copyright 2026, Amanda V     |
//+------------------------------------------------------------------+
#property copyright "Amanda V"
#property version   "1.20"
#property strict
#property indicator_chart_window
#property indicator_plots 0

input group "=== Calculator Settings ==="
input double InpRiskPercent  = 1.0; // Risk per Trade (%)
input int    InpStopLossPips = 20;  // Planned Stop Loss (Pips)

input group "=== Prop Firm Rules ==="
input double InpMaxDailyDD   = 5.0; // Max Daily Drawdown Limit (%)

int OnInit() {
   EventSetTimer(1); // Atualiza o painel a cada 1 segundo
   Print("Prop Firm Risk Monitor Initialized.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   EventKillTimer();
   Comment(""); // Limpa o painel ao remover o indicador
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[],
                const double &close[], const long &tick_volume[], const long &volume[],
                const int &spread[]) {
   // O MQL4 exige a função OnCalculate, mas processamos tudo no OnTimer
   return(rates_total);
}

void OnTimer() {
   double balance = AccountBalance();
   if(balance <= 0) return;
   
   // --- DAILY DRAWDOWN CALCULATION ---
   double daily_profit = 0;
   datetime start_of_day = iTime(Symbol(), PERIOD_D1, 0);
   
   // Loop pelo histórico fechado do dia
   for(int i = 0; i < OrdersHistoryTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) {
         if(OrderCloseTime() >= start_of_day) {
            daily_profit += OrderProfit() + OrderSwap() + OrderCommission();
         }
      }
   }
   
   // Adiciona o PnL flutuante das ordens abertas
   for(int i = 0; i < OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         daily_profit += OrderProfit() + OrderSwap() + OrderCommission();
      }
   }
   
   double daily_dd_pct = (daily_profit / balance) * 100.0;
   
   // --- LOT SIZE CALCULATOR ---
   double risk_amount = balance * (InpRiskPercent / 100.0);
   double tick_value = MarketInfo(Symbol(), MODE_TICKVALUE);
   
   // Tratamento para corretoras de 5 dígitos (pontos vs pips)
   double pip_multiplier = (Digits == 3 || Digits == 5) ? 10.0 : 1.0;
   double sl_points = InpStopLossPips * pip_multiplier;
   
   double lot_size = 0;
   if(tick_value > 0 && sl_points > 0) {
       lot_size = risk_amount / (sl_points * tick_value);
   }
   
   // Normalização do Lote
   double min_lot = MarketInfo(Symbol(), MODE_MINLOT);
   double max_lot = MarketInfo(Symbol(), MODE_MAXLOT);
   double step_lot = MarketInfo(Symbol(), MODE_LOTSTEP);
   
   if(lot_size < min_lot) lot_size = min_lot;
   if(lot_size > max_lot) lot_size = max_lot;
   if(step_lot > 0) lot_size = MathRound(lot_size / step_lot) * step_lot;
   
   // --- DASHBOARD RENDER ---
   string warning = "";
   if(daily_dd_pct <= -InpMaxDailyDD) {
      warning = "\n[!] WARNING: DAILY DRAWDOWN LIMIT REACHED!";
   }
   
   string text = "=== PROP FIRM RISK MONITOR ===\n\n";
   text += "Account Balance: $" + DoubleToString(balance, 2) + "\n";
   text += "Today's Net PnL: $" + DoubleToString(daily_profit, 2) + " (" + DoubleToString(daily_dd_pct, 2) + "%)\n";
   text += "Max Allowed DD:  " + DoubleToString(InpMaxDailyDD, 1) + "%\n";
   text += "---------------------------------------\n";
   text += "=== AUTO-LOT CALCULATOR ===\n\n";
   text += "Risking: " + DoubleToString(InpRiskPercent, 1) + "% ($" + DoubleToString(risk_amount, 2) + ")\n";
   text += "Stop Loss: " + IntegerToString(InpStopLossPips) + " Pips\n\n";
   text += "-> RECOMMENDED LOT: " + DoubleToString(lot_size, 2) + "\n";
   text += warning;
   
   Comment(text);
}
//+------------------------------------------------------------------+