//+------------------------------------------------------------------+
//|              MSB_Pro_ALGO_Neon_Account_Dashboard.mq5             |
//| Author: Kemal Mustafa Ozkan                                      |
//| Free MT5 account dashboard for CodeBase                          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Kemal Mustafa Ozkan"
#property link      "https://www.mql5.com/en/users/mustafa_ozkan"
#property version   "1.23"
#property description "MSB Pro ALGO Neon Account Dashboard for MetaTrader 5."
#property description "Displays balance, equity, floating P/L, today's realized P/L,"
#property description "closed trades, win rate and open positions. No trading logic."
#property indicator_chart_window
#property indicator_plots 0

input int    InpPanelX            = 18;       // Panel X position
input int    InpPanelY            = 38;       // Panel Y position
input int    InpRefreshSeconds    = 1;        // Refresh interval (seconds)
input int    InpMaxPositionRows   = 5;        // Maximum open-position rows
input bool   InpShowOpenPositions = true;     // Show open positions table
input color  InpAccentColor       = C'0,229,255';    // Neon cyan
input color  InpAccentSoft        = C'82,242,255';   // Soft neon cyan
input color  InpProfitColor       = C'0,255,156';    // Profit green
input color  InpLossColor         = C'255,59,107';   // Loss red/pink

const color CLR_PANEL      = C'4,8,16';
const color CLR_PANEL_2    = C'6,12,22';
const color CLR_CARD       = C'8,15,28';
const color CLR_CARD_2     = C'10,18,34';
const color CLR_BORDER     = C'24,74,98';
const color CLR_TEXT       = C'231,247,255';
const color CLR_MUTED      = C'112,160,178';
const color CLR_GLOW_DARK  = C'0,70,95';
const color CLR_WHITE      = C'255,255,255';
const color CLR_OPEN_GLOW  = C'0,92,58';
const color CLR_CLOSE_GLOW = C'105,20,42';

string g_prefix = "";
int    g_width  = 730;
int    g_height = 442;
bool   g_dirty  = false;

string ObjName(const string suffix)
{
   return g_prefix + suffix;
}

int VisibleRows()
{
   if(InpMaxPositionRows < 1)
      return 1;
   if(InpMaxPositionRows > 5)
      return 5;
   return InpMaxPositionRows;
}

void DeleteDashboard()
{
   if(g_prefix != "")
      ObjectsDeleteAll(0, g_prefix);
}

void DeleteObjectBySuffix(const string suffix)
{
   const string name = ObjName(suffix);
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
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
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpPanelX + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpPanelY + y);
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
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpPanelX + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpPanelY + y);
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
   const string glow = ObjName(suffix + "_glow");
   const string main = ObjName(suffix);

   if(!MakeLabelCore(glow, text, x + 1, y + 1, size, glow_clr, font, anchor))
      return false;
   if(!MakeLabelCore(main, text, x, y, size, main_clr, font, anchor))
      return false;

   ObjectSetInteger(0, glow, OBJPROP_ZORDER, 1);
   ObjectSetInteger(0, main, OBJPROP_ZORDER, 2);
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

void UpdateMarketFrame(const bool market_open)
{
   const color state_clr = (market_open ? InpProfitColor : InpLossColor);
   const color glow_clr  = (market_open ? CLR_OPEN_GLOW : CLR_CLOSE_GLOW);

   // The selected chart symbol (_Symbol) controls both the status text and
   // the full outer neon frame. Internal dashboard accents stay cyan.
   SetRectColors("panel", CLR_PANEL, state_clr);
   SetRectColors("frame_top_glow", glow_clr, glow_clr);
   SetRectColors("frame_bottom_glow", glow_clr, glow_clr);
   SetRectColors("frame_left_glow", glow_clr, glow_clr);
   SetRectColors("frame_right_glow", glow_clr, glow_clr);
   SetRectColors("frame_top", state_clr, state_clr);
   SetRectColors("frame_bottom", state_clr, state_clr);
   SetRectColors("frame_left", state_clr, state_clr);
   SetRectColors("frame_right", state_clr, state_clr);

   SetGlowLabel("market_status",
                (market_open ? "MARKET OPEN" : "MARKET CLOSED"),
                state_clr,
                glow_clr);
}

color PnlColor(const double value)
{
   if(value > 0.0000001)
      return InpProfitColor;
   if(value < -0.0000001)
      return InpLossColor;
   return InpAccentSoft;
}

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

string MoneyText(const double value, const bool signed_value = false)
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

   string raw = DoubleToString(abs_value, 2);
   const int dot_pos = StringFind(raw, ".");
   string int_part = raw;
   string dec_part = "00";
   if(dot_pos >= 0)
   {
      int_part = StringSubstr(raw, 0, dot_pos);
      dec_part = StringSubstr(raw, dot_pos + 1);
   }
   return sign + GroupIntegerPart(int_part) + "." + dec_part;
}

string PercentText(const double value)
{
   return DoubleToString(value, 1) + "%";
}

string ShortText(const string value, const int max_len)
{
   if(StringLen(value) <= max_len)
      return value;
   if(max_len <= 3)
      return StringSubstr(value, 0, max_len);
   return StringSubstr(value, 0, max_len - 3) + "...";
}


// Returns true when the current chart symbol is inside one of the broker-defined
// trading sessions for the current broker-server day/time.
bool IsMarketOpenForSymbol(const string symbol)
{
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
      return false;

   const long trade_mode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   if(trade_mode == SYMBOL_TRADE_MODE_DISABLED)
      return false;

   const datetime now = TimeCurrent();
   MqlDateTime cur;
   TimeToStruct(now, cur);

   ENUM_DAY_OF_WEEK dow = (ENUM_DAY_OF_WEEK)cur.day_of_week;
   const int now_sec = cur.hour * 3600 + cur.min * 60 + cur.sec;

   for(uint session = 0; session < 24; session++)
   {
      datetime from_time = 0;
      datetime to_time   = 0;
      if(!SymbolInfoSessionTrade(symbol, dow, session, from_time, to_time))
         break;

      MqlDateTime from_dt, to_dt;
      TimeToStruct(from_time, from_dt);
      TimeToStruct(to_time, to_dt);

      const int from_sec = from_dt.hour * 3600 + from_dt.min * 60 + from_dt.sec;
      const int to_sec   = to_dt.hour   * 3600 + to_dt.min   * 60 + to_dt.sec;

      // A session with identical start/end is treated as a 24-hour session.
      if(from_sec == to_sec)
         return true;

      // Normal same-day session.
      if(from_sec < to_sec)
      {
         if(now_sec >= from_sec && now_sec < to_sec)
            return true;
      }
      else
      {
         // Session crosses midnight.
         if(now_sec >= from_sec || now_sec < to_sec)
            return true;
      }
   }

   // If the broker exposes no trading-session schedule, do not claim OPEN.
   return false;
}

datetime BrokerDayStart()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
}

struct DailyStats
{
   double realized;
   int    closed_positions;
   int    wins;
   int    losses;
   double win_rate;
};

DailyStats GetDailyStats()
{
   DailyStats st;
   st.realized         = 0.0;
   st.closed_positions = 0;
   st.wins             = 0;
   st.losses           = 0;
   st.win_rate         = 0.0;

   const datetime from = BrokerDayStart();
   const datetime to   = TimeCurrent();

   if(!HistorySelect(from, to))
      return st;

   long   position_ids[];
   double position_pnl[];
   int    position_count = 0;

   const int deals_total = HistoryDealsTotal();

   for(int i = 0; i < deals_total; i++)
   {
      const ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;

      const long deal_type = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(deal_type != DEAL_TYPE_BUY && deal_type != DEAL_TYPE_SELL)
         continue;

      const double net = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                       + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                       + HistoryDealGetDouble(ticket, DEAL_SWAP)
                       + HistoryDealGetDouble(ticket, DEAL_FEE);

      st.realized += net;

      const long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT)
         continue;

      const long position_id = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      if(position_id <= 0)
         continue;

      int found = -1;
      for(int p = 0; p < position_count; p++)
      {
         if(position_ids[p] == position_id)
         {
            found = p;
            break;
         }
      }

      if(found < 0)
      {
         ArrayResize(position_ids, position_count + 1);
         ArrayResize(position_pnl, position_count + 1);
         position_ids[position_count] = position_id;
         position_pnl[position_count] = net;
         position_count++;
      }
      else
      {
         position_pnl[found] += net;
      }
   }

   st.closed_positions = position_count;

   for(int p = 0; p < position_count; p++)
   {
      if(position_pnl[p] > 0.0000001)
         st.wins++;
      else if(position_pnl[p] < -0.0000001)
         st.losses++;
   }

   const int decided = st.wins + st.losses;
   if(decided > 0)
      st.win_rate = 100.0 * (double)st.wins / (double)decided;

   return st;
}

struct PositionStats
{
   int    total;
   int    buys;
   int    sells;
};

PositionStats GetPositionStats()
{
   PositionStats ps;
   ps.total = 0;
   ps.buys  = 0;
   ps.sells = 0;

   const int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      ps.total++;
      const long type = PositionGetInteger(POSITION_TYPE);
      if(type == POSITION_TYPE_BUY)
         ps.buys++;
      else if(type == POSITION_TYPE_SELL)
         ps.sells++;

   }

   return ps;
}

void CreateCard(const string id,
                const string title,
                const int x,
                const int y,
                const int w,
                const int h)
{
   MakeRect(id + "_bg_glow", x - 1, y - 1, w + 2, h + 2, CLR_PANEL_2, CLR_GLOW_DARK);
   MakeRect(id + "_bg",      x,     y,     w,     h,     CLR_CARD,    CLR_BORDER);
   MakeGlowLabel(id + "_title", title, x + 14, y + 11, 9, InpAccentSoft, CLR_GLOW_DARK, "Segoe UI Semibold");
   MakeLabel(id + "_value", "0.00", x + 14, y + 36, 15, CLR_WHITE, "Segoe UI Semibold");
}

void BuildDashboard()
{
   DeleteDashboard();

   const int outer_w = g_width;
   const int outer_h = (InpShowOpenPositions ? g_height : 272);

   MakeRect("panel_shadow", 2, 2, outer_w, outer_h, CLR_PANEL_2, CLR_GLOW_DARK);
   MakeRect("panel", 0, 0, outer_w, outer_h, CLR_PANEL, InpLossColor);

   // Outer status frame: default CLOSED until the first live refresh.
   // Glow layer (4 px) plus bright inner layer (2 px).
   MakeRect("frame_top_glow",    0, 0,           outer_w, 4, CLR_CLOSE_GLOW, CLR_CLOSE_GLOW);
   MakeRect("frame_bottom_glow", 0, outer_h - 4, outer_w, 4, CLR_CLOSE_GLOW, CLR_CLOSE_GLOW);
   MakeRect("frame_left_glow",   0, 0,           4, outer_h, CLR_CLOSE_GLOW, CLR_CLOSE_GLOW);
   MakeRect("frame_right_glow",  outer_w - 4, 0, 4, outer_h, CLR_CLOSE_GLOW, CLR_CLOSE_GLOW);

   MakeRect("frame_top",    1, 1,           outer_w - 2, 2, InpLossColor, InpLossColor);
   MakeRect("frame_bottom", 1, outer_h - 3, outer_w - 2, 2, InpLossColor, InpLossColor);
   MakeRect("frame_left",   1, 1,           2, outer_h - 2, InpLossColor, InpLossColor);
   MakeRect("frame_right",  outer_w - 3, 1, 2, outer_h - 2, InpLossColor, InpLossColor);

   MakeGlowLabel("brand", "MSB PRO ALGO NEON ACCOUNT DASHBOARD", 18, 18, 14, CLR_WHITE, CLR_GLOW_DARK, "Segoe UI Semibold");
   MakeGlowLabel("market_status", "MARKET CLOSED", outer_w - 18, 20, 10, InpLossColor, CLR_CLOSE_GLOW, "Segoe UI Semibold", ANCHOR_RIGHT_UPPER);

   const int card_y = 58;
   const int card_w = 163;
   const int card_h = 78;
   const int gap    = 12;

   CreateCard("balance",  "BALANCE",        18,                         card_y, card_w, card_h);
   CreateCard("equity",   "EQUITY",         18 + (card_w + gap),        card_y, card_w, card_h);
   CreateCard("floating", "FLOATING P/L",   18 + 2 * (card_w + gap),    card_y, card_w, card_h);
   CreateCard("today",    "TODAY REALIZED", 18 + 3 * (card_w + gap),    card_y, card_w, card_h);

   const int row_y = 149;
   MakeRect("stats_bg_glow", 17, row_y - 1, outer_w - 38, 80, CLR_PANEL_2, CLR_GLOW_DARK);
   MakeRect("stats_bg",      18, row_y,     outer_w - 40, 78, CLR_CARD_2, CLR_BORDER);

   MakeGlowLabel("closed_title", "CLOSED TODAY", 34,  row_y + 14, 9, InpAccentSoft, CLR_GLOW_DARK, "Segoe UI Semibold");
   MakeLabel("closed_value", "0",    34,  row_y + 39, 13, CLR_WHITE, "Segoe UI Semibold");

   MakeGlowLabel("win_title",    "WIN RATE",     202, row_y + 14, 9, InpAccentSoft, CLR_GLOW_DARK, "Segoe UI Semibold");
   MakeLabel("win_value", "0.0%",  202, row_y + 39, 13, CLR_WHITE, "Segoe UI Semibold");

   MakeGlowLabel("open_title",   "OPEN POSITIONS", 350, row_y + 14, 9, InpAccentSoft, CLR_GLOW_DARK, "Segoe UI Semibold");
   MakeLabel("open_value", "0",   350, row_y + 39, 13, CLR_WHITE, "Segoe UI Semibold");

   MakeGlowLabel("bs_title",     "BUY / SELL",   515, row_y + 14, 9, InpAccentSoft, CLR_GLOW_DARK, "Segoe UI Semibold");
   MakeLabel("bs_value", "0 / 0", 515, row_y + 39, 13, CLR_WHITE, "Segoe UI Semibold");

   if(InpShowOpenPositions)
   {
      const int table_y = 242;
      MakeGlowLabel("positions_header", "OPEN POSITIONS", 18, table_y, 11, InpAccentColor, CLR_GLOW_DARK, "Segoe UI Semibold");

      MakeRect("table_bg_glow", 17, table_y + 23, outer_w - 38, 157, CLR_PANEL_2, CLR_GLOW_DARK);
      MakeRect("table_bg",      18, table_y + 24, outer_w - 40, 154, CLR_CARD,    CLR_BORDER);
      MakeRect("table_line",    34, table_y + 49, outer_w - 72, 1, InpAccentColor, InpAccentColor);

      MakeGlowLabel("h_symbol", "SYMBOL", 36,  table_y + 34, 8, InpAccentSoft, CLR_GLOW_DARK, "Segoe UI Semibold");
      MakeGlowLabel("h_type",   "TYPE",   205, table_y + 34, 8, InpAccentSoft, CLR_GLOW_DARK, "Segoe UI Semibold");
      MakeGlowLabel("h_volume", "VOLUME", 315, table_y + 34, 8, InpAccentSoft, CLR_GLOW_DARK, "Segoe UI Semibold");
      MakeGlowLabel("h_price",  "OPEN",   430, table_y + 34, 8, InpAccentSoft, CLR_GLOW_DARK, "Segoe UI Semibold");
      MakeGlowLabel("h_pnl",    "P/L",    585, table_y + 34, 8, InpAccentSoft, CLR_GLOW_DARK, "Segoe UI Semibold");

      // Stable, single-layer row labels. They are created once and only their
      // text/color changes, which avoids MT5 flicker from delete/recreate cycles.
      const int rows = VisibleRows();
      for(int r = 0; r < rows; r++)
      {
         const int yy = table_y + 63 + r * 20;
         const string base = "r" + IntegerToString(r);
         MakeLabel(base + "_symbol", " ", 36,  yy, 9, CLR_TEXT);
         MakeLabel(base + "_type",   " ", 205, yy, 9, InpAccentSoft, "Segoe UI Semibold");
         MakeLabel(base + "_volume", " ", 315, yy, 9, InpAccentSoft);
         MakeLabel(base + "_price",  " ", 430, yy, 9, CLR_TEXT);
         MakeLabel(base + "_pnl",    " ", 585, yy, 9, CLR_TEXT, "Segoe UI Semibold");
      }
      MakeLabel("more", " ", 36, table_y + 164, 8, InpAccentSoft);
   }
   ChartRedraw(0);
}

void UpdatePositionRows()
{
   if(!InpShowOpenPositions)
      return;

   const int max_rows = VisibleRows();
   const int total = PositionsTotal();
   const int table_y = 242;

   int row = 0;
   for(int i = 0; i < total && row < max_rows; i++)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      const string symbol = PositionGetString(POSITION_SYMBOL);
      const long   type   = PositionGetInteger(POSITION_TYPE);
      const double volume = PositionGetDouble(POSITION_VOLUME);
      const double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      const double pnl    = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      const int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      const string base   = "r" + IntegerToString(row);

      SetLabel(base + "_symbol", ShortText(symbol, 15), CLR_TEXT);
      SetLabel(base + "_type", (type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
               (type == POSITION_TYPE_BUY ? InpProfitColor : InpLossColor));
      SetLabel(base + "_volume", DoubleToString(volume, 2), InpAccentSoft);
      SetLabel(base + "_price", DoubleToString(open, digits), CLR_TEXT);
      SetLabel(base + "_pnl", (pnl > 0.0 ? "+" : "") + DoubleToString(pnl, 2), PnlColor(pnl));
      row++;
   }

   // Clear unused rows without deleting/recreating chart objects.
   for(int r = row; r < max_rows; r++)
   {
      const string base = "r" + IntegerToString(r);
      SetLabel(base + "_symbol", " ", CLR_TEXT);
      SetLabel(base + "_type",   " ", InpAccentSoft);
      SetLabel(base + "_volume", " ", InpAccentSoft);
      SetLabel(base + "_price",  " ", CLR_TEXT);
      SetLabel(base + "_pnl",    " ", CLR_TEXT);
   }

   if(total > max_rows)
      SetLabel("more", "+" + IntegerToString(total - max_rows) + " more position(s)", InpAccentSoft);
   else
      SetLabel("more", " ", InpAccentSoft);
}

void RefreshDashboard()
{
   g_dirty = false;
   const double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   const double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   const double floating = AccountInfoDouble(ACCOUNT_PROFIT);

   const DailyStats ds    = GetDailyStats();
   const PositionStats ps = GetPositionStats();

   // _Symbol is always the symbol of the chart where the indicator is attached.
   // Changing the selected chart product automatically changes this status/frame.
   const bool market_open = IsMarketOpenForSymbol(_Symbol);
   UpdateMarketFrame(market_open);

   SetLabel("balance_value", MoneyText(balance), CLR_WHITE);
   SetLabel("equity_value", MoneyText(equity), PnlColor(equity - balance));
   SetLabel("floating_value", MoneyText(floating, true), PnlColor(floating));
   SetLabel("today_value", MoneyText(ds.realized, true), PnlColor(ds.realized));

   SetLabel("closed_value", IntegerToString(ds.closed_positions), InpAccentSoft);
   SetLabel("win_value", PercentText(ds.win_rate),
            (ds.closed_positions > 0 ? (ds.win_rate >= 50.0 ? InpProfitColor : InpLossColor) : InpAccentSoft));
   SetLabel("open_value", IntegerToString(ps.total), InpAccentSoft);
   SetLabel("bs_value", IntegerToString(ps.buys) + " / " + IntegerToString(ps.sells), InpAccentSoft);

   UpdatePositionRows();

   if(g_dirty)
      ChartRedraw(0);
}

int OnInit()
{
   g_prefix = "MSB_NAD_" + IntegerToString((int)ChartID()) + "_";
   IndicatorSetString(INDICATOR_SHORTNAME, "MSB Pro ALGO Neon Account Dashboard");
   BuildDashboard();
   RefreshDashboard();
   const int refresh_seconds = (InpRefreshSeconds < 1 ? 1 : InpRefreshSeconds);
   EventSetTimer(refresh_seconds);
   return INIT_SUCCEEDED;
}

// Required event handler for a custom indicator.
// This dashboard uses timer/account data rather than indicator buffers.
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

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteDashboard();
   ChartRedraw(0);
}

void OnTimer()
{
   RefreshDashboard();
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
      ChartRedraw(0);
}
