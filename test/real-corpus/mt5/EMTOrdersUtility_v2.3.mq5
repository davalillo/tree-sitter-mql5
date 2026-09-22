//+------------------------------------------------------------------+
//|                                           EMTOrdersUtility.mq5   |
//|                                  Copyright 2026, Urayayi Kwinika |
//|                           https://www.mql5.com/en/users/ukwinika |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Urayayi Kwinika"
#property link      "https://www.mql5.com/en/users/ukwinika"
#property version   "2.3"
#property description "Real-Time Trade Monitor & Symbol Changer, that shows your running P&L, Trade Count, and Trade Type"
#property description ""
#property description "Sorts Market Watch Symbols in Alphabetical Order & Supports Symbols with spaces (e.g. Step Index 200, US Tech 100)."
#property description "Best for fewer Symbols to reduce Screen Clutter."
#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//+------------------------------------------------------------------+
//| Enums (must be declared BEFORE inputs)                           |
//+------------------------------------------------------------------+

enum ENUM_TIME_MODE
{
   TIME_MODE_LOCAL,
   // Local time
   TIME_MODE_SERVER,
   // Server time
   TIME_MODE_GMT
   // GMT time
};

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+

input group "=== SYMBOL SETTINGS ==="
input bool   InpAutoLoadSymbols    = true;
// Auto-load symbols from Market Watch
input string InpManualSymbols      = "Step Index 200,US Tech 100,Gold Basket,EURUSD,XAUUSD";
// Manual symbols (comma separated). KEEP spaces inside names!
// Example for Deriv: Step Index 200,US Tech 100,Gold Basket
// Do NOT remove spaces. Only separate symbols with commas.
input int    InpMaxSymbols         = 28;
// Maximum symbols to display
input bool   InpAbbreviateNames    = true;
// Abbreviate symbol names (hide suffix)
input string InpSuffixToHide       = "";
// Suffix to hide (e.g. .flix, .ecn, .pro) - leave empty for auto
input bool   InpShowSymbolButtons  = true;
// Show symbol buttons

input group "=== DISPLAY SETTINGS ==="
input ENUM_BASE_CORNER InpCorner     = CORNER_LEFT_UPPER;
// Panel corner
input int    InpXOffset              = 40; 
// X offset from corner
input int    InpYOffset              = 25;
// Y offset from corner
input int    InpButtonWidth          = 100;
// Button width (pixels) - 0 = auto
input int    InpButtonHeight         = 18;
// Button height (pixels)
input int    InpButtonsPerRow        = 11;
// Symbol buttons per row
input int    InpFontSize             = 7;
// Button font size
input bool   InpShowClock            = true;
// Show clock
input ENUM_TIME_MODE InpClockMode    = TIME_MODE_SERVER;
// Clock mode
input int    InpClockYOffset         = 22;
// Clock Y offset from panel top
input int    InpTimerInterval        = 1;
// Update interval (seconds)

input group "=== COLOR SETTINGS ==="
input color  InpColorNoPosition    = clrDimGray;
// No position color
input color  InpColorProfit        = C'0,120,0';
// Profit color (Green)
input color  InpColorLoss          = C'160,0,0';
// Loss color (Red)
input color  InpColorSelected      = C'0,0,180';
// Selected symbol color (Blue)
input color  InpColorText          = clrWhite;
// Button text color
input color  InpColorTextSelected  = clrWhite;
// Selected button text color
input color  InpColorPendingBorder = clrOrange;
// Pending order border color

input group "=== ADR / RANGE SETTINGS ==="
input bool   InpShowADR            = false;
// Show ADR info on chart
input int    InpADRPeriod          = 20;
// ADR period (days)
input color  InpADRColor           = clrGray;
// ADR text color
input int    InpADRYOffset         = 60;
// ADR text Y offset

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+

string           g_symbols[];
string           g_displayNames[];
int              g_symbolCount      = 0;
int              g_actualButtonWidth = 100;
string           g_accountCurrency  = "";
const string     g_prefix           = "EMTOrdersUtility_";
const int        LABEL_LINE_HEIGHT  = 13;   // Clean spacing for P/L labels
// Height of each label line in pixels
const int        ROW_BASE_HEIGHT    = 26;
// Minimum row height (button + 1 label)

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+

int OnInit()
{
   //--- Cache account currency
   g_accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);
   if(g_accountCurrency == "")
      g_accountCurrency = "USD";

   //--- Load symbols
   if(!LoadSymbols())
   {
      Print("Failed to Load Symbols. Indicator Stopped.");
      return(INIT_FAILED);
   }

   //--- Calculate optimal button width for long names
   CalculateButtonWidth();

   //--- Create the panel
   CreatePanel();

   //--- Set timer for real-time updates
   EventSetTimer(InpTimerInterval);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Calculate optimal button width for long symbol names             |
//+------------------------------------------------------------------+

void CalculateButtonWidth()
{
   // If user set a fixed width > 0, use it
   if(InpButtonWidth > 0)
   {
      g_actualButtonWidth = InpButtonWidth;
      return;
   }

   // Auto-calculate based on longest display name
   int maxWidth = 65;
   // Minimum width
   int charWidth = 6;
   // Approximate pixel width per character at font size 7-8

   for(int i = 0; i < g_symbolCount; i++)
   {
      int textWidth = StringLen(g_displayNames[i]) * charWidth + 10;
      // +10 for padding
      if(textWidth > maxWidth)
         maxWidth = textWidth;
   }

   // Cap at reasonable max to prevent absurdly wide buttons
   if(maxWidth > 180)
      maxWidth = 180;

   g_actualButtonWidth = maxWidth;
}

//+------------------------------------------------------------------+
//| Load symbols array                                               |
//+------------------------------------------------------------------+

bool LoadSymbols()
{
   if(InpAutoLoadSymbols)
   {
      //--- Load from Market Watch
      int total = SymbolsTotal(true);

      if(total == 0)
      {
         Print("Market Watch is Empty. Please Add Symbols to Market Watch.");
         return false;
      }

      if(total > InpMaxSymbols)
         total = InpMaxSymbols;

      ArrayResize(g_symbols, total);
      ArrayResize(g_displayNames, total);
      g_symbolCount = 0;

      for(int i = 0; i < total; i++)
      {
         string sym = SymbolName(i, true);
         if(sym != "")
         {
            g_symbols[g_symbolCount] = sym;
            g_displayNames[g_symbolCount] = GetDisplayName(sym);
            g_symbolCount++;
         }
      }

      if(g_symbolCount == 0)
      {
         Print("No Symbols Could be Loaded From Market Watch.");
         return false;
      }

      ArrayResize(g_symbols, g_symbolCount);
      ArrayResize(g_displayNames, g_symbolCount);
   }
   else
   {
      //--- Parse manual symbols from comma-separated string
      string manual = InpManualSymbols;
      string sep = ",";
      ushort u_sep = StringGetCharacter(sep, 0);
      string result[];
      int k = StringSplit(manual, u_sep, result);

      if(k <= 0)
      {
         Print("No Manual Symbols Specified.");
         return false;
      }

      ArrayResize(g_symbols, k);
      ArrayResize(g_displayNames, k);
      g_symbolCount = 0;

      for(int i = 0; i < k; i++)
      {
         string sym = result[i];

         // IMPORTANT: Only trim leading/trailing spaces.
         // Do NOT remove spaces that are part of the symbol name.
         // This allows symbols like: "Step Index 200", "US Tech 100", "Gold Basket", all Synthetics Instruments like from Deriv Markets/Weltrade
         StringTrimLeft(sym);
         StringTrimRight(sym);

         if(sym == "")
            continue;

         bool isCustom;
         if(SymbolExist(sym, isCustom))
         {
            g_symbols[g_symbolCount] = sym;
            g_displayNames[g_symbolCount] = GetDisplayName(sym);
            g_symbolCount++;
         }
         else
         {
            Print("Symbol Not Found: ", sym);
         }
      }

      if(g_symbolCount == 0)
      {
         Print("No Valid Manual Symbols Found.");
         return false;
      }

      ArrayResize(g_symbols, g_symbolCount);
      ArrayResize(g_displayNames, g_symbolCount);
   }

   //--- Sort symbols alphabetically (A-Z)
   for(int i = 0; i < g_symbolCount - 1; i++)
   {
      for(int j = 0; j < g_symbolCount - i - 1; j++)
      {
         if(StringCompare(g_symbols[j], g_symbols[j + 1], false) > 0)
         {
            string temp = g_symbols[j];
            g_symbols[j] = g_symbols[j + 1];
            g_symbols[j + 1] = temp;
         }
      }
   }

   //--- Rebuild display names after sorting
   for(int i = 0; i < g_symbolCount; i++)
      g_displayNames[i] = GetDisplayName(g_symbols[i]);

   return true;
}

//+------------------------------------------------------------------+
//| Get display name (abbreviate if needed)                          |
//+------------------------------------------------------------------+

string GetDisplayName(string symbol)
{
   if(!InpAbbreviateNames)
      return symbol;

   string suffix = InpSuffixToHide;

   // Auto-detect suffix if not specified
   if(suffix == "")
   {
      // Common suffixes to auto-detect
      string commonSuffixes[] = {".flix", ".ecn", ".pro", ".std", ".raw", ".micro", ".mini", ".prime", ".classic", ".ecnpro", ".stp"};
      for(int i = 0; i < ArraySize(commonSuffixes); i++)
      {
         if(StringFind(symbol, commonSuffixes[i]) != -1)
         {
            suffix = commonSuffixes[i];
            break;
         }
      }
   }

   if(suffix != "" && StringFind(symbol, suffix) != -1)
   {
      string display = symbol;
      StringReplace(display, suffix, "");
      return display;
   }

   return symbol;
}

//+------------------------------------------------------------------+
//| Create panel with all buttons and dynamic sub-labels             |
//+------------------------------------------------------------------+

void CreatePanel()
{
   //--- Delete any existing objects first
   DeleteAllObjects();

   int x = InpXOffset;
   int y = InpYOffset;
   int bw = g_actualButtonWidth;
   int bh = InpButtonHeight;
   // Row height accommodates button + up to 3 label lines + extra padding for clean display
   int rowHeight = bh + 3 * LABEL_LINE_HEIGHT + 8;

   //--- Create clock label
   if(InpShowClock)
   {
      string clockName = g_prefix + "CLOCK";
      int clockY = y - InpClockYOffset;
      if(clockY < 0) clockY = 0;

      if(ObjectCreate(ChartID(), clockName, OBJ_LABEL, 0, 0, 0))
      {
         ObjectSetInteger(ChartID(), clockName, OBJPROP_CORNER, InpCorner);
         ObjectSetInteger(ChartID(), clockName, OBJPROP_XDISTANCE, x);
         ObjectSetInteger(ChartID(), clockName, OBJPROP_YDISTANCE, clockY);
         ObjectSetInteger(ChartID(), clockName, OBJPROP_COLOR, clrWhite);
         ObjectSetInteger(ChartID(), clockName, OBJPROP_FONTSIZE, 8);
         ObjectSetString(ChartID(), clockName, OBJPROP_FONT, "Arial");
         ObjectSetInteger(ChartID(), clockName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(ChartID(), clockName, OBJPROP_HIDDEN, true);
      }
   }

   //--- Create symbol buttons and 3 sub-label slots per symbol
   if(InpShowSymbolButtons)
   {
      for(int i = 0; i < g_symbolCount; i++)
      {
         string btnName = g_prefix + g_symbols[i];
         int row = i / InpButtonsPerRow;
         int col = i % InpButtonsPerRow;

         int btnX = x + col * (bw + 2);
         int btnY = y + row * rowHeight;

         //--- Create button
         if(ObjectCreate(ChartID(), btnName, OBJ_BUTTON, 0, 0, 0))
         {
            ObjectSetInteger(ChartID(), btnName, OBJPROP_CORNER, InpCorner);
            ObjectSetInteger(ChartID(), btnName, OBJPROP_XDISTANCE, btnX);
            ObjectSetInteger(ChartID(), btnName, OBJPROP_YDISTANCE, btnY);
            ObjectSetInteger(ChartID(), btnName, OBJPROP_XSIZE, bw);
            ObjectSetInteger(ChartID(), btnName, OBJPROP_YSIZE, bh);
            ObjectSetString(ChartID(), btnName, OBJPROP_TEXT, g_displayNames[i]);
            ObjectSetInteger(ChartID(), btnName, OBJPROP_COLOR, InpColorText);
            ObjectSetInteger(ChartID(), btnName, OBJPROP_BGCOLOR, InpColorNoPosition);
            ObjectSetInteger(ChartID(), btnName, OBJPROP_FONTSIZE, InpFontSize);
            ObjectSetInteger(ChartID(), btnName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(ChartID(), btnName, OBJPROP_HIDDEN, true);
            ObjectSetInteger(ChartID(), btnName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
         }

         //--- Create 3 sub-label slots (positions assigned dynamically in update)
         for(int slot = 0; slot < 3; slot++)
         {
            string lblName = g_prefix + "LBL_" + g_symbols[i] + "_" + IntegerToString(slot);
            int lblY = btnY + bh + 2 + slot * LABEL_LINE_HEIGHT;

            if(ObjectCreate(ChartID(), lblName, OBJ_LABEL, 0, 0, 0))
            {
               ObjectSetInteger(ChartID(), lblName, OBJPROP_CORNER, InpCorner);
               ObjectSetInteger(ChartID(), lblName, OBJPROP_XDISTANCE, btnX);
               ObjectSetInteger(ChartID(), lblName, OBJPROP_YDISTANCE, lblY);
               ObjectSetInteger(ChartID(), lblName, OBJPROP_COLOR, clrWhite);
               ObjectSetInteger(ChartID(), lblName, OBJPROP_FONTSIZE, InpFontSize);
               ObjectSetString(ChartID(), lblName, OBJPROP_FONT, "Tahoma");
               ObjectSetInteger(ChartID(), lblName, OBJPROP_SELECTABLE, false);
               ObjectSetInteger(ChartID(), lblName, OBJPROP_HIDDEN, true);
               ObjectSetInteger(ChartID(), lblName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
               ObjectSetString(ChartID(), lblName, OBJPROP_TEXT, "");
            }
         }
      }
   }

   //--- Create ADR label
   if(InpShowADR)
   {
      string adrName = g_prefix + "ADR";
      int adrY = y + InpADRYOffset;

      if(ObjectCreate(ChartID(), adrName, OBJ_LABEL, 0, 0, 0))
      {
         ObjectSetInteger(ChartID(), adrName, OBJPROP_CORNER, InpCorner);
         ObjectSetInteger(ChartID(), adrName, OBJPROP_XDISTANCE, x);
         ObjectSetInteger(ChartID(), adrName, OBJPROP_YDISTANCE, adrY);
         ObjectSetInteger(ChartID(), adrName, OBJPROP_COLOR, InpADRColor);
         ObjectSetInteger(ChartID(), adrName, OBJPROP_FONTSIZE, 8);
         ObjectSetString(ChartID(), adrName, OBJPROP_FONT, "Arial");
         ObjectSetInteger(ChartID(), adrName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(ChartID(), adrName, OBJPROP_HIDDEN, true);
      }
   }

   //--- Initial update
   UpdateButtonsAndLabels();
   UpdateClock();
   UpdateADR();
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Delete all panel objects                                         |
//+------------------------------------------------------------------+

void DeleteAllObjects()
{
   // Delete all objects that belong to this indicator (by prefix)
   int total = ObjectsTotal(ChartID(), 0, -1);

   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(ChartID(), i, 0, -1);
      if(StringFind(name, g_prefix) == 0)
         ObjectDelete(ChartID(), name);
   }
}

//+------------------------------------------------------------------+
//| Update button colors and dynamically stack sub-labels            |
//| Active trade types are assigned to consecutive slots from top    |
//| Button color = net P&L (Green=Profit, Red=Loss, DimGray=Flat)    |
//+------------------------------------------------------------------+

void UpdateButtonsAndLabels()
{
   if(!InpShowSymbolButtons)
      return;

   string currentSymbol = Symbol();
   int bh = InpButtonHeight;

   for(int i = 0; i < g_symbolCount; i++)
   {
      string btnName = g_prefix + g_symbols[i];

      if(ObjectFind(ChartID(), btnName) < 0)
         continue;

      int buyCount = 0;
      int sellCount = 0;
      int pendingCount = 0;
      double buyProfit = 0.0;
      double sellProfit = 0.0;

      //--- Count positions and profit per type for this symbol
      int posTotal = PositionsTotal();
      for(int j = 0; j < posTotal; j++)
      {
         if(PositionGetSymbol(j) == g_symbols[i])
         {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            if(posType == POSITION_TYPE_BUY)
            {
               buyCount++;
               buyProfit += profit;
            }
            else if(posType == POSITION_TYPE_SELL)
            {
               sellCount++;
               sellProfit += profit;
            }
         }
      }

      //--- Count pending orders on this symbol
      int ordTotal = OrdersTotal();
      for(int j = 0; j < ordTotal; j++)
      {
         ulong ticket = OrderGetTicket(j);
         if(ticket > 0 && OrderSelect(ticket))
         {
            if(OrderGetString(ORDER_SYMBOL) == g_symbols[i])
            {
               int type = (int)OrderGetInteger(ORDER_TYPE);
               if(type >= ORDER_TYPE_BUY_LIMIT && type <= ORDER_TYPE_SELL_STOP)
                  pendingCount++;
            }
         }
      }

      double netProfit = buyProfit + sellProfit;
      bool hasPosition = (buyCount > 0 || sellCount > 0);
      bool isSelected = (g_symbols[i] == currentSymbol);

      //--- Button color based on NET P&L
      color bgColor = InpColorNoPosition;
      color textColor = InpColorText;

      if(hasPosition)
      {
         if(netProfit > 0)
         {
            bgColor = InpColorProfit;
            textColor = InpColorText;
         }
         else if(netProfit < 0)
         {
            bgColor = InpColorLoss;
            textColor = InpColorText;
         }
         else
         {
            bgColor = InpColorNoPosition;
            textColor = InpColorText;
         }
      }
      else if(isSelected)
      {
         bgColor = InpColorSelected;
         textColor = InpColorTextSelected;
      }

      //--- Apply button colors
      ObjectSetInteger(ChartID(), btnName, OBJPROP_BGCOLOR, bgColor);
      ObjectSetInteger(ChartID(), btnName, OBJPROP_COLOR, textColor);

      //--- Pending order border
      if(pendingCount > 0)
         ObjectSetInteger(ChartID(), btnName, OBJPROP_BORDER_COLOR, InpColorPendingBorder);
      else
         ObjectSetInteger(ChartID(), btnName, OBJPROP_BORDER_COLOR, bgColor);

      //--- Get button Y position for dynamic label positioning
      int btnY = (int)ObjectGetInteger(ChartID(), btnName, OBJPROP_YDISTANCE);

      //--- Build active trade type list and assign to consecutive slots (clean spacing)
      int activeSlot = 0;
      int labelTopPad = 2;   // small gap after the button

      // Long / Buy positions
      if(buyCount > 0)
      {
         string lblName = g_prefix + "LBL_" + g_symbols[i] + "_" + IntegerToString(activeSlot);
         if(ObjectFind(ChartID(), lblName) >= 0)
         {
            string buySign = (buyProfit >= 0) ? "+" : "";
            string txt = "Buy: " + buySign + StringFormat("%.2f", buyProfit) + " | " + IntegerToString(buyCount);
            int lblY = btnY + bh + labelTopPad + activeSlot * LABEL_LINE_HEIGHT;

            ObjectSetInteger(ChartID(), lblName, OBJPROP_YDISTANCE, lblY);
            ObjectSetString(ChartID(), lblName, OBJPROP_TEXT, txt);
            ObjectSetInteger(ChartID(), lblName, OBJPROP_COLOR, ColorForProfit(buyProfit));
            ObjectSetInteger(ChartID(), lblName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
         }
         activeSlot++;
      }

      // Sell positions
      if(sellCount > 0)
      {
         string lblName = g_prefix + "LBL_" + g_symbols[i] + "_" + IntegerToString(activeSlot);
         if(ObjectFind(ChartID(), lblName) >= 0)
         {
            string sellSign = (sellProfit >= 0) ? "+" : "";
            string txt = "Sell: " + sellSign + StringFormat("%.2f", sellProfit) + " | " + IntegerToString(sellCount);
            int lblY = btnY + bh + labelTopPad + activeSlot * LABEL_LINE_HEIGHT;

            ObjectSetInteger(ChartID(), lblName, OBJPROP_YDISTANCE, lblY);
            ObjectSetString(ChartID(), lblName, OBJPROP_TEXT, txt);
            ObjectSetInteger(ChartID(), lblName, OBJPROP_COLOR, ColorForProfit(sellProfit));
            ObjectSetInteger(ChartID(), lblName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
         }
         activeSlot++;
      }

      // Pending orders
      if(pendingCount > 0)
      {
         string lblName = g_prefix + "LBL_" + g_symbols[i] + "_" + IntegerToString(activeSlot);
         if(ObjectFind(ChartID(), lblName) >= 0)
         {
            string txt = "Pending";
            if(pendingCount > 1)
               txt += " | " + IntegerToString(pendingCount);
            int lblY = btnY + bh + labelTopPad + activeSlot * LABEL_LINE_HEIGHT;

            ObjectSetInteger(ChartID(), lblName, OBJPROP_YDISTANCE, lblY);
            ObjectSetString(ChartID(), lblName, OBJPROP_TEXT, txt);
            ObjectSetInteger(ChartID(), lblName, OBJPROP_COLOR, clrWhite);
            ObjectSetInteger(ChartID(), lblName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
         }
         activeSlot++;
      }

      //--- Hide any remaining unused slots
      for(int slot = activeSlot; slot < 3; slot++)
      {
         string lblName = g_prefix + "LBL_" + g_symbols[i] + "_" + IntegerToString(slot);
         if(ObjectFind(ChartID(), lblName) >= 0)
         {
            ObjectSetString(ChartID(), lblName, OBJPROP_TEXT, "");
            ObjectSetInteger(ChartID(), lblName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
         }
      }
   }
}

//+-----------------------------------------------------------------------+
//| Return color based on profit value (green=profit, red=loss, white=0)  |
//+-----------------------------------------------------------------------+

color ColorForProfit(double profit)
{
   if(profit > 0)  return C'0,220,0';
   // Bright green
   if(profit < 0)  return C'255,80,0';
   // Bright orange-red
   return clrWhite;
   // White for zero
}

//+------------------------------------------------------------------+
//| Update clock display                                             |
//+------------------------------------------------------------------+

void UpdateClock()
{
   if(!InpShowClock)
      return;

   string clockName = g_prefix + "CLOCK";
   if(ObjectFind(ChartID(), clockName) < 0)
      return;

   datetime now = TimeCurrent();
   string timeStr = "";

   switch(InpClockMode)
   {
      case TIME_MODE_LOCAL:
      {
         timeStr = TimeToString(now, TIME_DATE|TIME_SECONDS);
         ObjectSetString(ChartID(), clockName, OBJPROP_TEXT, "Local: " + timeStr);
         break;
      }
      case TIME_MODE_SERVER:
      {
         timeStr = TimeToString(now, TIME_DATE|TIME_SECONDS);
         ObjectSetString(ChartID(), clockName, OBJPROP_TEXT, "Server: " + timeStr);
         break;
      }
      case TIME_MODE_GMT:
      {
         datetime gmtTime = TimeGMT();
         timeStr = TimeToString(gmtTime, TIME_DATE|TIME_SECONDS);
         ObjectSetString(ChartID(), clockName, OBJPROP_TEXT, "GMT: " + timeStr);
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Update ADR display                                               |
//+------------------------------------------------------------------+

void UpdateADR()
{
   if(!InpShowADR)
      return;

   string adrName = g_prefix + "ADR";
   if(ObjectFind(ChartID(), adrName) < 0)
      return;

   string sym = Symbol();

   // Calculate ADR
   double adr = CalculateADR(sym, InpADRPeriod);
   double todayRange = iHigh(sym, PERIOD_D1, 0) - iLow(sym, PERIOD_D1, 0);

   string adrText = StringFormat("ADR(%d): %.1f | Today: %.1f", InpADRPeriod, adr, todayRange);
   ObjectSetString(ChartID(), adrName, OBJPROP_TEXT, adrText);
}

//+------------------------------------------------------------------+
//| Calculate Average Daily Range                                    |
//+------------------------------------------------------------------+

double CalculateADR(string symbol, int period)
{
   if(period <= 0) return 0;

   double totalRange = 0;
   int validDays = 0;

   for(int i = 1; i <= period; i++)
   {
      double high = iHigh(symbol, PERIOD_D1, i);
      double low  = iLow(symbol, PERIOD_D1, i);

      if(high > 0 && low > 0 && high != EMPTY_VALUE && low != EMPTY_VALUE)
      {
         totalRange += (high - low);
         validDays++;
      }
   }

   if(validDays == 0) return 0;

   return totalRange / validDays;
}

//+------------------------------------------------------------------+
//| Change chart symbol                                              |
//+------------------------------------------------------------------+

void ChangeSymbol(string symbol)
{
   if(symbol == Symbol())
      return;

   if(!ChartSetSymbolPeriod(ChartID(), symbol, Period()))
      Print("Failed to Change Symbol to ", symbol, ". Error: ", GetLastError());
}

//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      string objName = sparam;

      //--- Symbol button clicked
      for(int i = 0; i < g_symbolCount; i++)
      {
         if(objName == g_prefix + g_symbols[i])
         {
            ObjectSetInteger(ChartID(), objName, OBJPROP_STATE, false);
            ChangeSymbol(g_symbols[i]);
            return;
         }
      }
   }
   else if(id == CHARTEVENT_CHART_CHANGE)
   {
      //--- Chart symbol changed externally
      UpdateButtonsAndLabels();
      UpdateClock();
      UpdateADR();
   }
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+

void OnTimer()
{
   UpdateButtonsAndLabels();
   UpdateClock();
   UpdateADR();
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
   UpdateButtonsAndLabels();
   UpdateClock();
   UpdateADR();

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+

void OnDeinit(const int reason)
{
   //--- Kill the timer
   EventKillTimer();

   //--- Force delete all objects created by this indicator
   DeleteAllObjects();

   //--- Extra safety: remove any remaining objects with our prefix
   int total = ObjectsTotal(ChartID(), 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(ChartID(), i, 0, -1);
      if(StringFind(name, g_prefix) == 0)
         ObjectDelete(ChartID(), name);
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+ End of Program