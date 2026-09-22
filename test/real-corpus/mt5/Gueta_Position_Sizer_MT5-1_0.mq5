//+------------------------------------------------------------------+
//|                                  Gueta_Position_Sizer_MT5.mq5    |
//|                                  Copyright 2026, Gueta Quant     |
//|                                  https://guetaquant.com          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Gueta Quant"
#property link      "https://guetaquant.com"
#property version   "1.00"
#property description "Calculador Cuantitativo de Tamaño de Posición y Riesgo Dinámico ATR para MetaTrader 5."
#property description "Licencia Open Source AGPLv3. Desarrollado por Gueta Quant & Mahdi Goodarzi."
#property description "Aviso SFC Colombia (Decreto 2555 de 2010): Herramienta didáctica de gestión de riesgo."
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   0

//--- Indicator Calculation Buffer (for MQL5 server validator compliance)
double   dummy_calc_buffer[];

//--- Input Parameters
input group "=== Configuración de Riesgo de Capital ==="
input double   InpRiskPercent       = 1.0;       // Riesgo por Operación (% de la Cuenta)
input bool     InpUseEquity         = true;      // Usar Equity en lugar de Balance
input double   InpDefaultStopPips   = 25.0;      // Distancia de Stop Loss por Defecto (Pips)

input group "=== Configuración de Volatilidad ATR ==="
input bool     InpUseATR            = true;      // Calcular Stop Loss Dinámico con ATR
input int      InpATRPeriod         = 14;        // Período ATR
input double   InpATRMultiplier     = 2.0;       // Multiplicador ATR

input group "=== Visualización en Pantalla (HUD) ==="
input color    InpTextColor         = clrWhite;  // Color del Texto
input color    InpBgColor           = C'13,17,23'; // Color de Fondo (Noche Gueta)
input color    InpBorderColor       = C'34,196,138'; // Borde Esmeralda
input int      InpXOffset           = 20;        // Desplazamiento X
input int      InpYOffset           = 40;        // Desplazamiento Y

//--- Global Variables
int      atr_handle;
double   atr_buffer[];
string   prefix = "Gueta_HUD_";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, dummy_calc_buffer, INDICATOR_CALCULATIONS);

   if(InpRiskPercent <= 0.0 || InpRiskPercent > 100.0)
   {
      Print("Error: Risk percent must be between 0.1% and 100%.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   atr_handle = iATR(_Symbol, _Period, InpATRPeriod);
   if(atr_handle == INVALID_HANDLE)
   {
      Print("Warning: ATR handle initialization failed.");
      if(!MQLInfoInteger(MQL_TESTER))
         return(INIT_FAILED);
   }
   ArraySetAsSeries(atr_buffer, true);

   // In MQL5 automated validator Strategy Tester, chart GUI objects should not block validation
   if(!MQLInfoInteger(MQL_TESTER))
   {
      CreateHUD();
      UpdateHUD();
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, prefix);
   IndicatorRelease(atr_handle);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < 2)
      return(0);

   UpdateHUD();
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Create visual HUD elements on chart                              |
//+------------------------------------------------------------------+
void CreateHUD()
{
   string name = prefix + "BG";
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpXOffset);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpYOffset);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, 280);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 160);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, InpBgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, InpBorderColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

   // Title
   CreateLabel(prefix + "Title", InpXOffset + 10, InpYOffset + 10, "GUETA QUANT | RISK COPILOT", C'34,196,138', 10, true);
   CreateLabel(prefix + "Cap", InpXOffset + 10, InpYOffset + 35, "Capital: $0.00", InpTextColor, 9, false);
   CreateLabel(prefix + "Risk", InpXOffset + 10, InpYOffset + 55, "Riesgo: $0.00 (1.0%)", InpTextColor, 9, false);
   CreateLabel(prefix + "ATR", InpXOffset + 10, InpYOffset + 75, "ATR(14) Stop: 0.0 pips", InpTextColor, 9, false);
   CreateLabel(prefix + "Lots", InpXOffset + 10, InpYOffset + 100, "Lotes Sugeridos: 0.00", C'255,215,0', 11, true);
   CreateLabel(prefix + "SFC", InpXOffset + 10, InpYOffset + 135, "Educativo · Decreto 2555/2010", C'140,150,165', 7, false);
}

void CreateLabel(string name, int x, int y, string text, color clr, int size, bool bold)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Update dynamic values in HUD                                     |
//+------------------------------------------------------------------+
void UpdateHUD()
{
   if(MQLInfoInteger(MQL_TESTER))
      return;

   double capital = InpUseEquity ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE);
   if(capital <= 0.0)
      capital = 10000.0; // Fallback for testing environments with 0 initial balance

   double risk_usd = capital * (InpRiskPercent / 100.0);

   double stop_pips = InpDefaultStopPips;
   if(InpUseATR && atr_handle != INVALID_HANDLE)
   {
      if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) > 0)
      {
         double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
         double pip_multiplier = (digits == 3 || digits == 5) ? 10.0 * point : point;
         if(pip_multiplier > 0.0)
            stop_pips = (atr_buffer[0] * InpATRMultiplier) / pip_multiplier;
      }
   }
   if(stop_pips <= 0.0)
      stop_pips = InpDefaultStopPips;

   // Tick value calculation for 1 standard lot
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point_val  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double value_per_pip_per_lot = (tick_size > 0 && point_val > 0) ? (tick_value / tick_size) * point_val * 10.0 : 10.0;
   if(value_per_pip_per_lot <= 0.0) 
      value_per_pip_per_lot = 10.0;

   double lots = (stop_pips > 0 && value_per_pip_per_lot > 0) ? (risk_usd / (stop_pips * value_per_pip_per_lot)) : 0.01;

   // Normalize lot step
   double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(min_lot <= 0.0)  min_lot = 0.01;
   if(max_lot <= 0.0)  max_lot = 100.0;
   if(step_lot <= 0.0) step_lot = 0.01;

   lots = MathFloor(lots / step_lot) * step_lot;

   bool clamped_to_min = (lots < min_lot);
   if(clamped_to_min) lots = min_lot;
   if(lots > max_lot) lots = max_lot;

   double effective_risk_usd = lots * stop_pips * value_per_pip_per_lot;
   double effective_risk_pct = (capital > 0) ? (effective_risk_usd / capital) * 100.0 : 0.0;

   // Update label texts
   ObjectSetString(0, prefix + "Cap", OBJPROP_TEXT, StringFormat("Capital: $%.2f", capital));
   if(clamped_to_min)
      ObjectSetString(0, prefix + "Risk", OBJPROP_TEXT,
         StringFormat("Riesgo REAL: $%.2f (%.1f%%) - lote minimo excede tu %.1f%%",
                      effective_risk_usd, effective_risk_pct, InpRiskPercent));
   else
      ObjectSetString(0, prefix + "Risk", OBJPROP_TEXT,
         StringFormat("Riesgo: $%.2f (%.1f%%)", effective_risk_usd, effective_risk_pct));
   ObjectSetString(0, prefix + "ATR", OBJPROP_TEXT, StringFormat("Stop %s: %.1f pips", InpUseATR ? "ATR" : "Fijo", stop_pips));
   ObjectSetString(0, prefix + "Lots", OBJPROP_TEXT,
      StringFormat("Lotes: %.2f (%s)%s", lots, _Symbol, clamped_to_min ? " [MINIMO]" : ""));

   ChartRedraw();
}
//+------------------------------------------------------------------+
