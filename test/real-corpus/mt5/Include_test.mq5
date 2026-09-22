//+------------------------------------------------------------------+
//|                                                     Include test |
//|                                  Copyright 2026, Romeo Luvisotto |
//|                  // https://www.mql5.com/en/users/romeoluvisotto |
//+------------------------------------------------------------------+
#include <CRiskCalculator.mqh>

// Helper function to render a high-contrast panel on the chart
void DrawChartPanel(const string &lines[])
  {
   int x = 20, y = 30;
   int width = 280, lineHeight = 18;
   int height = (ArraySize(lines) * lineHeight) + 20;

// 1. Create Background Box (Visible on white, black, or custom charts)
   string bgName = "RiskCalc_BG";
   if(ObjectFind(0, bgName) < 0)
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);

   ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, clrDarkSlateGray);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);

// 2. Render Text Lines inside the panel
   for(int i = 0; i < ArraySize(lines); i++)
     {
      string lblName = "RiskCalc_Lbl_" + IntegerToString(i);
      if(ObjectFind(0, lblName) < 0)
         ObjectCreate(0, lblName, OBJ_LABEL, 0, 0, 0);

      ObjectSetInteger(0, lblName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, lblName, OBJPROP_XDISTANCE, x + 12);
      ObjectSetInteger(0, lblName, OBJPROP_YDISTANCE, y + 10 + (i * lineHeight));
      ObjectSetString(0, lblName, OBJPROP_TEXT, lines[i]);
      ObjectSetString(0, lblName, OBJPROP_FONT, "Segoe UI");
      ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, lblName, OBJPROP_COLOR, (i == 0) ? clrYellow : clrWhite);
      ObjectSetInteger(0, lblName, OBJPROP_SELECTABLE, false);
     }

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnStart()
  {
// Instantiate the risk calculator
   CRiskCalculator riskCalc;

   string symbol     = _Symbol;
   double riskAmount = 100.0; // Target risk in account currency
   double slPips     = 25.0;  // Stop Loss distance in pips

// Calculate parameters
   double lotSize      = riskCalc.CalculateLotSize(symbol, riskAmount, slPips);
   double pipValPerLot = riskCalc.GetPipValuePerLot(symbol);

// Prepare output lines
   string info[6];
   info[0] = "=== RISK & POSITION CALCULATOR ===";
   info[1] = "Symbol: " + symbol;
   info[2] = "Account Currency: " + AccountInfoString(ACCOUNT_CURRENCY);
   info[3] = "Target Risk: $" + DoubleToString(riskAmount, 2);
   info[4] = "Calculated Lot Size: " + DoubleToString(lotSize, 2) + " lots";
   info[5] = "Pip Value (1 Lot): " + DoubleToString(pipValPerLot, 2);

// Display GUI panel on chart
   DrawChartPanel(info);
  }
//+------------------------------------------------------------------+
