//+------------------------------------------------------------------+
//|                 MSB_Pro_ALGO_Position_Risk_Monitor.mq5           |
//| Author: Kemal Mustafa Ozkan                                      |
//| Free MT5 position risk dashboard for MQL5 CodeBase               |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Kemal Mustafa Ozkan"
#property link      "https://www.mql5.com/en/users/mustafa_ozkan"
#property version   "1.03"
#property description "MSB Pro ALGO Position Risk Monitor for MetaTrader 5."
#property description "Monitors open-position stop-loss risk using broker symbol specifications."
#property description "Read-only utility. It does not open, modify or close trades."
#property indicator_chart_window
#property indicator_plots 0

//--- User settings
input int    InpPanelX          = 18;       // Panel X position
input int    InpPanelY          = 38;       // Panel Y position
input int    InpRefreshSeconds  = 1;        // Refresh interval (seconds)
input int    InpMaxRows         = 6;        // Maximum displayed positions
input bool   InpAutoCoexist     = true;     // Auto-position beside Account Dashboard
input double InpLowRiskPct      = 2.00;     // Low-risk ceiling (%)
input double InpHighRiskPct     = 5.00;     // High-risk threshold (%)
input color  InpAccentColor     = C'0,229,255';    // Neon cyan
input color  InpAccentSoft      = C'82,242,255';   // Soft neon cyan
input color  InpProfitColor     = C'0,255,156';    // Neon green
input color  InpWarningColor    = C'255,211,74';   // Neon yellow
input color  InpLossColor       = C'255,59,107';   // Neon red/pink

//--- Theme
const color CLR_PANEL      = C'4,8,16';
const color CLR_PANEL_2    = C'6,12,22';
const color CLR_CARD       = C'8,15,28';
const color CLR_CARD_2     = C'10,18,34';
const color CLR_BORDER     = C'24,74,98';
const color CLR_TEXT       = C'231,247,255';
const color CLR_MUTED      = C'112,160,178';
const color CLR_WHITE      = C'255,255,255';
const color CLR_GLOW_CYAN  = C'0,70,95';
const color CLR_GLOW_GREEN = C'0,92,58';
const color CLR_GLOW_RED   = C'105,20,42';
const color CLR_GLOW_YEL   = C'105,78,18';

string g_prefix = "";
bool   g_dirty  = false;
int    g_width  = 700;
int    g_height = 470;
int    g_panel_x = 18;
int    g_panel_y = 38;

void BuildDashboard();

//+------------------------------------------------------------------+
//| Data structures                                                  |
//+------------------------------------------------------------------+
struct RiskItem
{
   ulong  ticket;
   string symbol;
   long   type;
   double volume;
   double open_price;
   double stop_loss;
   double risk_money;
   double risk_pct;
   bool   has_sl;
   bool   protected_sl;
   bool   calc_ok;
};

struct RiskSummary
{
   int    total_positions;
   int    with_sl;
   int    without_sl;
   int    protected_sl;
   int    calc_errors;
   double total_lots;
   double known_risk;
   double risk_pct;
   double max_single_risk;
};

//+------------------------------------------------------------------+
//| Object helpers                                                   |
//+------------------------------------------------------------------+
string ObjName(const string suffix)
{
   return g_prefix + suffix;
}

int VisibleRows()
{
   if(InpMaxRows < 1)
      return 1;
   if(InpMaxRows > 8)
      return 8;
   return InpMaxRows;
}

void DeleteDashboard()
{
   if(g_prefix != "")
      ObjectsDeleteAll(0, g_prefix);
}

void ResolvePanelPosition(int &target_x, int &target_y)
{
   target_x = InpPanelX;
   target_y = InpPanelY;

   if(!InpAutoCoexist)
      return;

   const string chart_id = IntegerToString((int)ChartID());
   const string account_panel = "MSB_NAD_" + chart_id + "_panel";
   if(ObjectFind(0, account_panel) < 0)
      return;

   const int ax = (int)ObjectGetInteger(0, account_panel, OBJPROP_XDISTANCE);
   const int ay = (int)ObjectGetInteger(0, account_panel, OBJPROP_YDISTANCE);
   const int aw = (int)ObjectGetInteger(0, account_panel, OBJPROP_XSIZE);
   const int ah = (int)ObjectGetInteger(0, account_panel, OBJPROP_YSIZE);
   const int chart_w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   const int chart_h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);

   // Prefer side-by-side. With the compact 700 px risk panel, this fits
   // common wide-screen MT5 layouts and avoids chart-object overlap.
   const int right_x = ax + aw + 12;
   if(right_x + g_width <= chart_w - 6)
   {
      target_x = right_x;
      target_y = ay;
      return;
   }

   // If the chart is too narrow, try directly below the account dashboard.
   const int below_y = ay + ah + 12;
   if(below_y + g_height <= chart_h - 6)
   {
      target_x = ax;
      target_y = below_y;
      return;
   }

   // Last resort: right-align the risk monitor. This keeps its title/status
   // visible instead of silently hiding it behind the other dashboard.
   target_x = MathMax(4, chart_w - g_width - 6);
   target_y = ay + 28;
}

bool SyncPanelPosition()
{
   int tx, ty;
   ResolvePanelPosition(tx, ty);
   if(tx == g_panel_x && ty == g_panel_y)
      return false;

   g_panel_x = tx;
   g_panel_y = ty;
   BuildDashboard();
   return true;
}

bool MakeRect(const string suffix,
              const int x,
              const int y,
              const int w,
              const int h,
              const color bg,
              const color border)
{
   const string name = ObjName(suffix);

   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
         return false;
   }

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, g_panel_x + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, g_panel_y + y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
   return true;
}

bool MakeLabelCore(const string name,
                   const string text,
                   const int x,
                   const int y,
                   const int size,
                   const color clr,
                   const string font = "Segoe UI",
                   const ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
         return false;
   }

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, g_panel_x + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, g_panel_y + y);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   return true;
}

bool MakeLabel(const string suffix,
               const string text,
               const int x,
               const int y,
               const int size,
               const color clr,
               const string font = "Segoe UI",
               const ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER)
{
   return MakeLabelCore(ObjName(suffix), text, x, y, size, clr, font, anchor);
}

bool MakeGlowLabel(const string suffix,
                   const string text,
                   const int x,
                   const int y,
                   const int size,
                   const color main_clr,
                   const color glow_clr,
                   const string font = "Segoe UI",
                   const ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER)
{
   if(!MakeLabelCore(ObjName(suffix + "_glow"), text, x + 1, y + 1, size, glow_clr, font, anchor))
      return false;
   if(!MakeLabelCore(ObjName(suffix), text, x, y, size, main_clr, font, anchor))
      return false;

   ObjectSetInteger(0, ObjName(suffix + "_glow"), OBJPROP_ZORDER, 1);
   ObjectSetInteger(0, ObjName(suffix), OBJPROP_ZORDER, 2);
   return true;
}

void SetLabel(const string suffix, const string text, const color clr)
{
   const string name = ObjName(suffix);
   if(ObjectFind(0, name) < 0)
      return;

   bool changed = false;
   if(ObjectGetString(0, name, OBJPROP_TEXT) != text)
   {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      changed = true;
   }
   if((color)ObjectGetInteger(0, name, OBJPROP_COLOR) != clr)
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      changed = true;
   }
   if(changed)
      g_dirty = true;
}

void SetGlowLabel(const string suffix,
                  const string text,
                  const color main_clr,
                  const color glow_clr)
{
   const string main = ObjName(suffix);
   const string glow = ObjName(suffix + "_glow");
   bool changed = false;

   if(ObjectFind(0, main) >= 0)
   {
      if(ObjectGetString(0, main, OBJPROP_TEXT) != text)
      {
         ObjectSetString(0, main, OBJPROP_TEXT, text);
         changed = true;
      }
      if((color)ObjectGetInteger(0, main, OBJPROP_COLOR) != main_clr)
      {
         ObjectSetInteger(0, main, OBJPROP_COLOR, main_clr);
         changed = true;
      }
   }

   if(ObjectFind(0, glow) >= 0)
   {
      if(ObjectGetString(0, glow, OBJPROP_TEXT) != text)
      {
         ObjectSetString(0, glow, OBJPROP_TEXT, text);
         changed = true;
      }
      if((color)ObjectGetInteger(0, glow, OBJPROP_COLOR) != glow_clr)
      {
         ObjectSetInteger(0, glow, OBJPROP_COLOR, glow_clr);
         changed = true;
      }
   }

   if(changed)
      g_dirty = true;
}

void SetRectColors(const string suffix, const color bg, const color border)
{
   const string name = ObjName(suffix);
   if(ObjectFind(0, name) < 0)
      return;

   bool changed = false;
   if((color)ObjectGetInteger(0, name, OBJPROP_BGCOLOR) != bg)
   {
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
      changed = true;
   }
   if((color)ObjectGetInteger(0, name, OBJPROP_COLOR) != border)
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, border);
      changed = true;
   }
   if(changed)
      g_dirty = true;
}

//+------------------------------------------------------------------+
//| Formatting                                                       |
//+------------------------------------------------------------------+
string GroupIntegerPart(const string digits)
{
   string out = "";
   const int len = StringLen(digits);
   for(int i = 0; i < len; i++)
   {
      if(i > 0 && ((len - i) % 3) == 0)
         out += ",";
      out += StringSubstr(digits, i, 1);
   }
   return out;
}

string NumberText(const double value, const int decimals = 2, const bool signed_value = false)
{
   string sign = "";
   double abs_value = value;

   if(value < 0.0)
   {
      sign = "-";
      abs_value = -value;
   }
   else if(signed_value && value > 0.0)
   {
      sign = "+";
   }

   string raw = DoubleToString(abs_value, decimals);
   const int dot_pos = StringFind(raw, ".");
   string int_part = raw;
   string dec_part = "";

   if(dot_pos >= 0)
   {
      int_part = StringSubstr(raw, 0, dot_pos);
      dec_part = StringSubstr(raw, dot_pos + 1);
   }

   string out = sign + GroupIntegerPart(int_part);
   if(decimals > 0)
      out += "." + dec_part;
   return out;
}

string PercentText(const double value)
{
   return DoubleToString(value, 2) + "%";
}

string ShortText(const string value, const int max_len)
{
   if(StringLen(value) <= max_len)
      return value;
   if(max_len <= 3)
      return StringSubstr(value, 0, max_len);
   return StringSubstr(value, 0, max_len - 3) + "...";
}

//+------------------------------------------------------------------+
//| Risk calculations                                                |
//+------------------------------------------------------------------+
bool CalcProfitAtStop(const string symbol,
                      const long position_type,
                      const double volume,
                      const double open_price,
                      const double stop_loss,
                      double &pnl_at_sl)
{
   ENUM_ORDER_TYPE order_type = (position_type == POSITION_TYPE_SELL ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);

   ResetLastError();
   if(OrderCalcProfit(order_type, symbol, volume, open_price, stop_loss, pnl_at_sl))
      return true;

   // Retry after selecting the symbol. This helps broker-specific CFD/crypto
   // symbols whose calculation data may not yet be loaded in Market Watch.
   SymbolSelect(symbol, true);
   ResetLastError();
   if(OrderCalcProfit(order_type, symbol, volume, open_price, stop_loss, pnl_at_sl))
      return true;

   // Broker-data fallback: tick size/value are expressed in account currency
   // for one lot, so they can be used when OrderCalcProfit is unavailable.
   const double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tick_value <= 0.0)
      tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tick_size <= 0.0 || tick_value <= 0.0 || volume <= 0.0)
      return false;

   double signed_distance = 0.0;
   if(position_type == POSITION_TYPE_BUY)
      signed_distance = stop_loss - open_price;
   else
      signed_distance = open_price - stop_loss;

   pnl_at_sl = (signed_distance / tick_size) * tick_value * volume;
   return true;
}

bool BuildRiskItem(const ulong ticket, const double account_base, RiskItem &item)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;

   item.ticket       = ticket;
   item.symbol       = PositionGetString(POSITION_SYMBOL);
   item.type         = PositionGetInteger(POSITION_TYPE);
   item.volume       = PositionGetDouble(POSITION_VOLUME);
   item.open_price   = PositionGetDouble(POSITION_PRICE_OPEN);
   item.stop_loss    = PositionGetDouble(POSITION_SL);
   item.risk_money   = 0.0;
   item.risk_pct     = 0.0;
   item.has_sl       = (item.stop_loss > 0.0);
   item.protected_sl = false;
   item.calc_ok      = true;

   if(!item.has_sl)
      return true;

   double pnl_at_sl = 0.0;
   if(!CalcProfitAtStop(item.symbol,
                        item.type,
                        item.volume,
                        item.open_price,
                        item.stop_loss,
                        pnl_at_sl))
   {
      item.calc_ok = false;
      return true;
   }

   // SL already at/beyond breakeven means no entry-to-SL loss remains.
   if(pnl_at_sl >= 0.0)
   {
      item.protected_sl = true;
      item.risk_money   = 0.0;
      item.risk_pct     = 0.0;
      return true;
   }

   item.risk_money = -pnl_at_sl;
   if(account_base > 0.0)
      item.risk_pct = 100.0 * item.risk_money / account_base;

   return true;
}

int CollectRiskData(RiskItem &items[], RiskSummary &sum)
{
   ArrayResize(items, 0);

   sum.total_positions = 0;
   sum.with_sl          = 0;
   sum.without_sl       = 0;
   sum.protected_sl     = 0;
   sum.calc_errors      = 0;
   sum.total_lots       = 0.0;
   sum.known_risk       = 0.0;
   sum.risk_pct         = 0.0;
   sum.max_single_risk  = 0.0;

   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   const double base   = (equity > 0.0 ? equity : AccountInfoDouble(ACCOUNT_BALANCE));
   const int total     = PositionsTotal();

   for(int i = 0; i < total; i++)
   {
      const ulong ticket = PositionGetTicket(i);
      RiskItem item;
      if(!BuildRiskItem(ticket, base, item))
         continue;

      const int n = ArraySize(items);
      ArrayResize(items, n + 1);
      items[n] = item;

      sum.total_positions++;
      sum.total_lots += item.volume;

      if(!item.has_sl)
      {
         sum.without_sl++;
         continue;
      }

      sum.with_sl++;

      if(!item.calc_ok)
      {
         sum.calc_errors++;
         continue;
      }

      if(item.protected_sl)
         sum.protected_sl++;

      sum.known_risk += item.risk_money;
      if(item.risk_money > sum.max_single_risk)
         sum.max_single_risk = item.risk_money;
   }

   if(base > 0.0)
      sum.risk_pct = 100.0 * sum.known_risk / base;

   return ArraySize(items);
}

void RiskState(const RiskSummary &sum,
               string &state_text,
               color &state_color,
               color &glow_color)
{
   if(sum.total_positions <= 0)
   {
      state_text  = "NO POSITIONS";
      state_color = InpAccentColor;
      glow_color  = CLR_GLOW_CYAN;
      return;
   }

   if(sum.without_sl > 0)
   {
      state_text  = "NO SL";
      state_color = InpLossColor;
      glow_color  = CLR_GLOW_RED;
      return;
   }

   if(sum.calc_errors > 0)
   {
      state_text  = "CHECK RISK";
      state_color = InpWarningColor;
      glow_color  = CLR_GLOW_YEL;
      return;
   }

   if(sum.risk_pct > InpHighRiskPct)
   {
      state_text  = "HIGH RISK";
      state_color = InpLossColor;
      glow_color  = CLR_GLOW_RED;
      return;
   }

   if(sum.risk_pct > InpLowRiskPct)
   {
      state_text  = "MODERATE RISK";
      state_color = InpWarningColor;
      glow_color  = CLR_GLOW_YEL;
      return;
   }

   state_text  = "LOW RISK";
   state_color = InpProfitColor;
   glow_color  = CLR_GLOW_GREEN;
}

//+------------------------------------------------------------------+
//| UI                                                               |
//+------------------------------------------------------------------+
void CreateCard(const string id,
                const string title,
                const int x,
                const int y,
                const int w,
                const int h)
{
   MakeRect(id + "_bg_glow", x - 1, y - 1, w + 2, h + 2, CLR_PANEL_2, CLR_GLOW_CYAN);
   MakeRect(id + "_bg",      x,     y,     w,     h,     CLR_CARD,    CLR_BORDER);
   MakeGlowLabel(id + "_title", title, x + 14, y + 11, 9, InpAccentSoft, CLR_GLOW_CYAN, "Segoe UI Semibold");
   // Dynamic value = single label to avoid flicker in MT5.
   MakeLabel(id + "_value", "-", x + 14, y + 36, 15, CLR_WHITE, "Segoe UI Semibold");
}

void UpdateFrame(const color state_color, const color glow_color)
{
   SetRectColors("panel", CLR_PANEL, state_color);
   SetRectColors("frame_top_glow", glow_color, glow_color);
   SetRectColors("frame_bottom_glow", glow_color, glow_color);
   SetRectColors("frame_left_glow", glow_color, glow_color);
   SetRectColors("frame_right_glow", glow_color, glow_color);
   SetRectColors("frame_top", state_color, state_color);
   SetRectColors("frame_bottom", state_color, state_color);
   SetRectColors("frame_left", state_color, state_color);
   SetRectColors("frame_right", state_color, state_color);
}

void BuildDashboard()
{
   DeleteDashboard();

   const int outer_w = g_width;
   const int outer_h = g_height;

   MakeRect("panel_shadow", 2, 2, outer_w, outer_h, CLR_PANEL_2, CLR_GLOW_CYAN);
   MakeRect("panel", 0, 0, outer_w, outer_h, CLR_PANEL, InpAccentColor);

   MakeRect("frame_top_glow",    0, 0,           outer_w, 4, CLR_GLOW_CYAN, CLR_GLOW_CYAN);
   MakeRect("frame_bottom_glow", 0, outer_h - 4, outer_w, 4, CLR_GLOW_CYAN, CLR_GLOW_CYAN);
   MakeRect("frame_left_glow",   0, 0,           4, outer_h, CLR_GLOW_CYAN, CLR_GLOW_CYAN);
   MakeRect("frame_right_glow",  outer_w - 4, 0, 4, outer_h, CLR_GLOW_CYAN, CLR_GLOW_CYAN);

   MakeRect("frame_top",    1, 1,           outer_w - 2, 2, InpAccentColor, InpAccentColor);
   MakeRect("frame_bottom", 1, outer_h - 3, outer_w - 2, 2, InpAccentColor, InpAccentColor);
   MakeRect("frame_left",   1, 1,           2, outer_h - 2, InpAccentColor, InpAccentColor);
   MakeRect("frame_right",  outer_w - 3, 1, 2, outer_h - 2, InpAccentColor, InpAccentColor);

   MakeGlowLabel("brand", "MSB PRO ALGO POSITION RISK MONITOR", 18, 18, 12, CLR_WHITE, CLR_GLOW_CYAN, "Segoe UI Semibold");
   MakeGlowLabel("risk_status", "NO POSITIONS", outer_w - 18, 20, 10, InpAccentColor, CLR_GLOW_CYAN, "Segoe UI Semibold", ANCHOR_RIGHT_UPPER);

   const int card_y = 58;
   const int card_w = 155;
   const int card_h = 78;
   const int gap    = 10;

   CreateCard("known_risk", "KNOWN OPEN RISK", 18,                         card_y, card_w, card_h);
   CreateCard("risk_pct",   "ACCOUNT RISK",    18 + (card_w + gap),        card_y, card_w, card_h);
   CreateCard("with_sl",    "POSITIONS WITH SL",18 + 2 * (card_w + gap),   card_y, card_w, card_h);
   CreateCard("no_sl",      "POSITIONS NO SL", 18 + 3 * (card_w + gap),   card_y, card_w, card_h);

   const int row_y = 149;
   MakeRect("stats_bg_glow", 17, row_y - 1, outer_w - 34, 80, CLR_PANEL_2, CLR_GLOW_CYAN);
   MakeRect("stats_bg",      18, row_y,     outer_w - 36, 78, CLR_CARD_2, CLR_BORDER);

   MakeGlowLabel("open_title", "OPEN POSITIONS", 34,  row_y + 14, 9, InpAccentSoft, CLR_GLOW_CYAN, "Segoe UI Semibold");
   MakeLabel("open_value", "0", 34, row_y + 39, 13, InpAccentSoft, "Segoe UI Semibold");

   MakeGlowLabel("lots_title", "TOTAL LOTS", 190, row_y + 14, 9, InpAccentSoft, CLR_GLOW_CYAN, "Segoe UI Semibold");
   MakeLabel("lots_value", "0.00", 190, row_y + 39, 13, InpAccentSoft, "Segoe UI Semibold");

   MakeGlowLabel("protected_title", "PROTECTED SL", 355, row_y + 14, 9, InpAccentSoft, CLR_GLOW_CYAN, "Segoe UI Semibold");
   MakeLabel("protected_value", "0", 355, row_y + 39, 13, InpAccentSoft, "Segoe UI Semibold");

   MakeGlowLabel("maxrisk_title", "MAX SINGLE RISK", 510, row_y + 14, 9, InpAccentSoft, CLR_GLOW_CYAN, "Segoe UI Semibold");
   MakeLabel("maxrisk_value", "0.00", 510, row_y + 39, 13, InpAccentSoft, "Segoe UI Semibold");

   const int table_y = 242;
   MakeGlowLabel("positions_header", "POSITION RISK", 18, table_y, 11, InpAccentColor, CLR_GLOW_CYAN, "Segoe UI Semibold");

   MakeRect("table_bg_glow", 17, table_y + 23, outer_w - 34, 183, CLR_PANEL_2, CLR_GLOW_CYAN);
   MakeRect("table_bg",      18, table_y + 24, outer_w - 36, 180, CLR_CARD, CLR_BORDER);
   MakeRect("table_line",    34, table_y + 49, outer_w - 68, 1, InpAccentColor, InpAccentColor);

   MakeGlowLabel("h_symbol", "SYMBOL", 36,  table_y + 34, 8, InpAccentSoft, CLR_GLOW_CYAN, "Segoe UI Semibold");
   MakeGlowLabel("h_type",   "TYPE",   185, table_y + 34, 8, InpAccentSoft, CLR_GLOW_CYAN, "Segoe UI Semibold");
   MakeGlowLabel("h_lot",    "LOT",    250, table_y + 34, 8, InpAccentSoft, CLR_GLOW_CYAN, "Segoe UI Semibold");
   MakeGlowLabel("h_sl",     "STOP LOSS", 320, table_y + 34, 8, InpAccentSoft, CLR_GLOW_CYAN, "Segoe UI Semibold");
   MakeGlowLabel("h_risk",   "RISK",   465, table_y + 34, 8, InpAccentSoft, CLR_GLOW_CYAN, "Segoe UI Semibold");
   MakeGlowLabel("h_pct",    "RISK %",  585, table_y + 34, 8, InpAccentSoft, CLR_GLOW_CYAN, "Segoe UI Semibold");

   const int rows = VisibleRows();
   for(int r = 0; r < rows; r++)
   {
      const int yy = table_y + 63 + r * 22;
      MakeLabel("r" + IntegerToString(r) + "_symbol", " ", 36,  yy, 9, CLR_TEXT);
      MakeLabel("r" + IntegerToString(r) + "_type",   " ", 185, yy, 9, InpAccentSoft, "Segoe UI Semibold");
      MakeLabel("r" + IntegerToString(r) + "_lot",    " ", 250, yy, 9, CLR_TEXT);
      MakeLabel("r" + IntegerToString(r) + "_sl",     " ", 320, yy, 9, CLR_TEXT);
      MakeLabel("r" + IntegerToString(r) + "_risk",   " ", 465, yy, 9, CLR_TEXT, "Segoe UI Semibold");
      MakeLabel("r" + IntegerToString(r) + "_pct",    " ", 585, yy, 9, CLR_TEXT, "Segoe UI Semibold");
   }

   MakeLabel("more", " ", 36, table_y + 184, 8, CLR_MUTED);
   ChartRedraw(0);
}

void UpdateRows(RiskItem &items[])
{
   const int rows = VisibleRows();
   const int total = ArraySize(items);

   for(int r = 0; r < rows; r++)
   {
      SetLabel("r" + IntegerToString(r) + "_symbol", " ", CLR_TEXT);
      SetLabel("r" + IntegerToString(r) + "_type",   " ", InpAccentSoft);
      SetLabel("r" + IntegerToString(r) + "_lot",    " ", CLR_TEXT);
      SetLabel("r" + IntegerToString(r) + "_sl",     " ", CLR_TEXT);
      SetLabel("r" + IntegerToString(r) + "_risk",   " ", CLR_TEXT);
      SetLabel("r" + IntegerToString(r) + "_pct",    " ", CLR_TEXT);
   }

   for(int r = 0; r < total && r < rows; r++)
   {
      RiskItem item = items[r];
      const int digits = (int)SymbolInfoInteger(item.symbol, SYMBOL_DIGITS);

      const color type_color = (item.type == POSITION_TYPE_BUY ? InpProfitColor : InpLossColor);
      SetLabel("r" + IntegerToString(r) + "_symbol", ShortText(item.symbol, 16), CLR_TEXT);
      SetLabel("r" + IntegerToString(r) + "_type", (item.type == POSITION_TYPE_BUY ? "BUY" : "SELL"), type_color);
      SetLabel("r" + IntegerToString(r) + "_lot", DoubleToString(item.volume, 2), InpAccentSoft);

      if(!item.has_sl)
      {
         SetLabel("r" + IntegerToString(r) + "_sl", "NO SL", InpLossColor);
         SetLabel("r" + IntegerToString(r) + "_risk", "UNDEFINED", InpLossColor);
         SetLabel("r" + IntegerToString(r) + "_pct", "--", InpLossColor);
         continue;
      }

      if(!item.calc_ok)
      {
         SetLabel("r" + IntegerToString(r) + "_sl", DoubleToString(item.stop_loss, digits), InpWarningColor);
         SetLabel("r" + IntegerToString(r) + "_risk", "N/A", InpWarningColor);
         SetLabel("r" + IntegerToString(r) + "_pct", "N/A", InpWarningColor);
         continue;
      }

      SetLabel("r" + IntegerToString(r) + "_sl", DoubleToString(item.stop_loss, digits), (item.protected_sl ? InpProfitColor : CLR_TEXT));
      SetLabel("r" + IntegerToString(r) + "_risk", NumberText(item.risk_money, 2), (item.protected_sl ? InpProfitColor : InpWarningColor));
      SetLabel("r" + IntegerToString(r) + "_pct", PercentText(item.risk_pct), (item.protected_sl ? InpProfitColor : InpWarningColor));
   }

   if(total > rows)
      SetLabel("more", "+" + IntegerToString(total - rows) + " more position(s)", InpAccentSoft);
   else
      SetLabel("more", " ", CLR_MUTED);
}

void RefreshDashboard()
{
   RiskItem items[];
   RiskSummary sum;
   CollectRiskData(items, sum);

   string state_text;
   color state_color;
   color glow_color;
   RiskState(sum, state_text, state_color, glow_color);

   UpdateFrame(state_color, glow_color);
   SetGlowLabel("risk_status", state_text, state_color, glow_color);

   // Positions WITH an SL are always calculated, even if another open
   // position has no SL. A no-SL position makes total downside unbounded,
   // but it must not hide the known risk from protected/bounded positions.
   if(sum.without_sl > 0)
   {
      if(sum.with_sl > 0 && sum.known_risk > 0.0)
      {
         SetLabel("known_risk_value", NumberText(sum.known_risk, 2), InpWarningColor);
         SetLabel("risk_pct_value", ">=" + PercentText(sum.risk_pct), InpLossColor);
      }
      else
      {
         SetLabel("known_risk_value", "--", InpLossColor);
         SetLabel("risk_pct_value",   "UNBOUNDED", InpLossColor);
      }
   }
   else
   {
      SetLabel("known_risk_value", NumberText(sum.known_risk, 2), state_color);
      SetLabel("risk_pct_value", PercentText(sum.risk_pct), state_color);
   }
   SetLabel("with_sl_value", IntegerToString(sum.with_sl), (sum.with_sl > 0 ? InpProfitColor : InpAccentSoft));
   SetLabel("no_sl_value", IntegerToString(sum.without_sl), (sum.without_sl > 0 ? InpLossColor : InpProfitColor));

   SetLabel("open_value", IntegerToString(sum.total_positions), InpAccentSoft);
   SetLabel("lots_value", NumberText(sum.total_lots, 2), InpAccentSoft);
   SetLabel("protected_value", IntegerToString(sum.protected_sl), (sum.protected_sl > 0 ? InpProfitColor : InpAccentSoft));
   SetLabel("maxrisk_value", NumberText(sum.max_single_risk, 2), (sum.max_single_risk > 0.0 ? InpWarningColor : InpAccentSoft));

   UpdateRows(items);

   if(g_dirty)
   {
      ChartRedraw(0);
      g_dirty = false;
   }
}

//+------------------------------------------------------------------+
//| Indicator events                                                 |
//+------------------------------------------------------------------+

// Keep only one MSB Pro ALGO dashboard on the same chart.
// MT5 allows multiple custom indicators on one chart by default, so we
// explicitly remove the companion Account Dashboard to get EA-like replacement.
void RemoveCompanionPanel()
{
   const string other_shortname = "MSB Pro ALGO Neon Account Dashboard";
   ChartIndicatorDelete(0, 0, other_shortname);

   // Also remove any stale visual objects left from an older copy/version.
   const string other_prefix = "MSB_NAD_" + IntegerToString((int)ChartID()) + "_";
   ObjectsDeleteAll(0, other_prefix);
}

int OnInit()
{
   RemoveCompanionPanel();

   g_prefix = "MSB_PRM_" + IntegerToString((int)ChartID()) + "_";
   IndicatorSetString(INDICATOR_SHORTNAME, "MSB Pro ALGO Position Risk Monitor");

   ResolvePanelPosition(g_panel_x, g_panel_y);
   BuildDashboard();
   RefreshDashboard();

   const int refresh_seconds = (InpRefreshSeconds < 1 ? 1 : InpRefreshSeconds);
   EventSetTimer(refresh_seconds);
   return INIT_SUCCEEDED;
}

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
   return rates_total;
}

void OnTimer()
{
   if(SyncPanelPosition())
      g_dirty = true;
   RefreshDashboard();
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteDashboard();
   ChartRedraw(0);
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      if(SyncPanelPosition())
         g_dirty = true;
      ChartRedraw(0);
   }
}
