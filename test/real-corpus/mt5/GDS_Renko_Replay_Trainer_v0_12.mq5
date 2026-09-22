//+------------------------------------------------------------------+
//| GDS Renko Replay Trainer                                         |
//| Historical tick replay and ONE virtual position.                 |
//| Attach to a NEW EMPTY normal chart, not to Strategy Tester.       |
//| No broker orders. No custom symbols. No external dependencies.    |
//+------------------------------------------------------------------+
#property copyright "Golden Delta"
#property link      "https://www.mql5.com/en/code/76813"
#property version   "0.12"
#property strict
#property description "Renko training on historical Bid/Ask ticks. Virtual trades only."
#property description "Attach to a new empty normal MT5 chart. Press LOAD, then PLAY."
#property description "Start=0 selects 09:00 on the previous weekday (server time)."
#property description "Money values use frozen current contract/conversion estimates."

input datetime InpReplayStart       = 0;       // Start in broker server time; 0 = previous weekday 09:00
input int      InpReplayHours       = 6;       // Historical interval, hours (1..72)
input double   InpBrickSize         = 2.0;     // Fixed Renko brick in PRICE units, e.g. 2.0 for gold
input double   InpStopBricks        = 3.0;     // Initial virtual SL distance in bricks
input double   InpTargetBricks      = 5.0;     // Initial virtual TP distance in bricks
input double   InpVirtualLot        = 0.01;    // Virtual volume; no broker order is sent
input double   InpInitialBalance    = 10000.0; // Virtual starting balance in account currency
input double   InpCommissionLotRT   = 0.0;     // Round-turn commission per lot, account currency
input int      InpTicksPerSecond    = 50;      // Initial replay rate (1..1000 ticks/second)
input int      InpVisibleBricks     = 60;      // Visible completed bricks (20..160)

const int KEEP_BRICKS=200;
const int MAX_BRICKS_PER_TICK=4096;
const ulong CHUNK_MSC=300000;                   // Complete 5-minute windows, inclusive endpoints
const int TIMER_MS=100;
const string PREFIX="GDS_RT012_";
const color C_BG=C'14,19,29';
const color C_PANEL=C'22,30,44';
const color C_GRID=C'38,49,66';
const color C_TEXT=C'224,233,245';
const color C_MUTED=C'145,163,187';
const color C_UP=C'44,202,163';
const color C_DOWN=C'244,105,121';
const color C_ACCENT=C'79,163,255';
const color C_WARN=C'244,194,86';

struct SBrick
  {
   double open,close;
   int direction,run;
   long time_msc;
  };

// Integer quote grid prevents cumulative floating point brick drift.
class CRenko
  {
private:
   double m_tick_size;
   long m_size,m_close;
   int m_dir,m_run;
   bool m_anchor;
public:
   void Init(const double tick_size,const long size)
     {
      m_tick_size=tick_size; m_size=size; m_close=0;
      m_dir=0; m_run=0; m_anchor=false;
     }
   int Push(const double price,const long stamp,SBrick &out[])
     {
      ArrayResize(out,0);
      const long p=(long)MathRound(price/m_tick_size);
      if(!m_anchor) { m_close=p; m_anchor=true; return 0; }
      const long delta=p-m_close;
      int dir=m_dir;
      long count=0;
      bool reversal=false;
      if(m_dir==0)
        {
         if(delta>=m_size) { dir=1; count=delta/m_size; }
         else if(delta<=-m_size) { dir=-1; count=(-delta)/m_size; }
        }
      else if(m_dir>0)
        {
         if(delta>=m_size) count=delta/m_size;
         else if(delta<=-2*m_size)
           { dir=-1; reversal=true; count=(-delta)/m_size-1; }
        }
      else
        {
         if(delta<=-m_size) count=(-delta)/m_size;
         else if(delta>=2*m_size)
           { dir=1; reversal=true; count=delta/m_size-1; }
        }
      if(count>MAX_BRICKS_PER_TICK) return -1; // Atomic failure: do not truncate a tick.
      if(count==0) return 0;
      if(ArrayResize(out,(int)count)!=(int)count) return -1;
      for(int i=0;i<(int)count;i++)
        {
         const long open=m_close+((reversal && i==0) ? dir*m_size : 0);
         m_close=open+dir*m_size;
         if(dir==m_dir) m_run++;
         else { m_dir=dir; m_run=1; }
         out[i].open=open*m_tick_size;
         out[i].close=m_close*m_tick_size;
         out[i].direction=dir; out[i].run=m_run; out[i].time_msc=stamp;
        }
      return (int)count;
     }
  };

struct STrade
  {
   int id,dir;
   long entry_msc,exit_msc;
   double entry,exit,sl,tp,lot,risk,commission,gross,net,r;
   string reason;
  };

// The account model never reads future ticks or live quotes.
// Cash-per-price coefficients are frozen once when LOAD starts a session.
class CVirtualAccount
  {
private:
   bool m_open;
   int m_id,m_closed,m_wins;
   double m_start,m_balance,m_equity,m_peak,m_dd,m_dd_pct;
   double m_lot,m_commission,m_grid,m_long_gain,m_long_loss,m_short_gain,m_short_loss;
   double m_gross_profit,m_gross_loss,m_total_r,m_equity_r,m_peak_r,m_dd_r;
   STrade m_trade;
   double Cash(const int dir,const double entry,const double exit)
     {
      const double move=dir*(exit-entry);
      const double factor=(dir>0 ? (move>=0 ? m_long_gain : m_long_loss) :
                                   (move>=0 ? m_short_gain : m_short_loss));
      return move*factor;
     }
   double GridDown(const double price) { return MathFloor(price/m_grid+1e-9)*m_grid; }
   double GridUp(const double price) { return MathCeil(price/m_grid-1e-9)*m_grid; }
public:
   void Init(const double balance,const double lot,const double commission,
             const double grid,const double lg,const double ll,const double sg,const double sl)
     {
      m_open=false; m_id=0; m_closed=0; m_wins=0;
      m_start=balance; m_balance=balance; m_equity=balance; m_peak=balance;
      m_dd=0; m_dd_pct=0; m_lot=lot; m_commission=commission;
      m_grid=grid; m_long_gain=lg; m_long_loss=ll; m_short_gain=sg; m_short_loss=sl;
      m_gross_profit=0; m_gross_loss=0; m_total_r=0; m_equity_r=0;
      m_peak_r=0; m_dd_r=0;
     }
   void Mark(const MqlTick &tick)
     {
      m_equity=m_balance; m_equity_r=m_total_r;
      if(m_open)
        {
         const double price=(m_trade.dir>0 ? tick.bid : tick.ask);
         const double gross=Cash(m_trade.dir,m_trade.entry,price);
         m_equity+=gross;
         m_equity_r+=(gross-m_trade.commission)/m_trade.risk;
        }
      m_peak=MathMax(m_peak,m_equity);
      const double dd=m_peak-m_equity;
      m_dd=MathMax(m_dd,dd);
      if(m_peak>0) m_dd_pct=MathMax(m_dd_pct,100.0*dd/m_peak);
      m_peak_r=MathMax(m_peak_r,m_equity_r);
      m_dd_r=MathMax(m_dd_r,m_peak_r-m_equity_r);
     }
   bool Open(const int dir,const MqlTick &tick,const double sl_distance,const double tp_distance)
     {
      if(m_open || (dir!=1 && dir!=-1) || sl_distance<=0 || tp_distance<=0) return false;
      const double entry=(dir>0 ? tick.ask : tick.bid);
      const double sl=(dir>0 ? GridDown(entry-sl_distance) : GridUp(entry+sl_distance));
      const double tp=(dir>0 ? GridUp(entry+tp_distance) : GridDown(entry-tp_distance));
      if(sl<=0 || tp<=0) return false;
      // Reject stops already crossed by the executable side of this quote.
      if((dir>0 && (sl>=tick.bid || tp<=tick.bid)) ||
         (dir<0 && (sl<=tick.ask || tp>=tick.ask))) return false;
      const double risk=MathAbs(Cash(dir,entry,sl))+m_commission;
      if(risk<=0 || m_balance<risk) return false;
      STrade trade={};
      trade.id=++m_id; trade.dir=dir; trade.entry_msc=tick.time_msc;
      trade.entry=entry; trade.sl=sl; trade.tp=tp; trade.lot=m_lot;
      trade.risk=risk; trade.commission=m_commission;
      m_trade=trade; m_open=true;
      m_balance-=m_commission; // Entire round-turn cost reserved at entry.
      Mark(tick);
      return true;
     }
   bool Close(const MqlTick &tick,const string reason,STrade &result)
     {
      if(!m_open) return false;
      m_trade.exit_msc=tick.time_msc;
      m_trade.exit=(m_trade.dir>0 ? tick.bid : tick.ask);
      m_trade.gross=Cash(m_trade.dir,m_trade.entry,m_trade.exit);
      m_trade.net=m_trade.gross-m_trade.commission;
      m_trade.r=m_trade.net/m_trade.risk; m_trade.reason=reason;
      m_balance+=m_trade.gross; m_total_r+=m_trade.r;
      m_closed++;
      if(m_trade.net>0) { m_wins++; m_gross_profit+=m_trade.net; }
      else m_gross_loss-=m_trade.net;
      result=m_trade; m_open=false; Mark(tick);
      return true;
     }
   bool CheckStops(const MqlTick &tick,STrade &result)
     {
      if(!m_open) return false;
      const double price=(m_trade.dir>0 ? tick.bid : tick.ask);
      if((m_trade.dir>0 && price<=m_trade.sl) || (m_trade.dir<0 && price>=m_trade.sl))
         return Close(tick,"SL",result);
      if((m_trade.dir>0 && price>=m_trade.tp) || (m_trade.dir<0 && price<=m_trade.tp))
         return Close(tick,"TP",result);
      return false;
     }
   bool IsOpen(void) { return m_open; }
   void Position(STrade &trade) { trade=m_trade; }
   int Trades(void) { return m_closed; }
   double Balance(void) { return m_balance; }
   double Equity(void) { return m_equity; }
   double Drawdown(void) { return m_dd; }
   double DrawdownPct(void) { return m_dd_pct; }
   double DrawdownR(void) { return m_dd_r; }
   double TotalR(void) { return m_total_r; }
   double Net(void) { return m_balance-m_start; }
   double WinRate(void) { return (m_closed>0 ? 100.0*m_wins/m_closed : 0.0); }
   string PF(void)
     {
      if(m_gross_loss>0) return DoubleToString(m_gross_profit/m_gross_loss,2);
      return (m_gross_profit>0 ? "n/a (no losses)" : "n/a");
     }
  };

enum EPhase { IDLE, WAIT_DATA, READY, RUNNING, STEP_TICK, STEP_BRICK, FINISHED, DATA_ERROR };
CRenko g_renko;
CVirtualAccount g_account;
SBrick g_bricks[];
MqlTick g_buffer[],g_quote;
bool g_have_quote=false,g_chart_saved=false,g_rendering=false,g_valued=false;
long g_chart_show=1,g_chart_bg=0,g_chart_foreground=0;
EPhase g_phase=IDLE,g_resume=READY;
int g_buffer_index=0,g_speed=50,g_command=0,g_load_failures=0,g_file=INVALID_HANDLE;
long g_seen_ticks=0,g_bad_ticks=0,g_total_bricks=0,g_gap_count=0,g_max_gap_msc=0;
long g_last_raw_msc=0;
ulong g_from_msc=0,g_end_msc=0,g_load_from=0,g_next_retry=0,g_last_clock=0;
double g_tick_size=0,g_brick_size=0,g_tokens=0;
string g_note="Set inputs with F7. Press LOAD to start.",g_last_trade="No closed virtual trades.";
string g_base="",g_currency="",g_period="",g_end_reason="";
int g_width=1000,g_height=700;
bool g_small=false,g_history_retryable=false,g_tester_mode=false;

bool ValidQuote(const MqlTick &tick)
  {
   return tick.time_msc>0 && MathIsValidNumber(tick.bid) && MathIsValidNumber(tick.ask) &&
          tick.bid>0 && tick.ask>=tick.bid;
  }

string Stamp(const long msc)
  {
   if(msc<=0) return "--";
   return TimeToString((datetime)(msc/1000),TIME_DATE|TIME_SECONDS)+"."+
          StringFormat("%03d",(int)(msc%1000));
  }

void Pause(const string message)
  {
   if(g_phase!=IDLE && g_phase!=FINISHED && g_phase!=DATA_ERROR) g_phase=READY;
   g_tokens=0; g_note=message;
  }

void Fail(const string message,const bool retryable=false)
  {
   g_phase=DATA_ERROR; g_tokens=0; g_command=0; g_note=message;
   g_history_retryable=retryable;
   Print("GDS Renko Trainer: ",message);
  }

void KeepBrick(const SBrick &brick)
  {
   int n=ArraySize(g_bricks);
   if(n>=KEEP_BRICKS)
     {
      for(int i=1;i<n;i++) g_bricks[i-1]=g_bricks[i];
      n--;
     }
   if(ArrayResize(g_bricks,n+1)!=n+1) { Fail("Not enough memory for bricks."); return; }
   g_bricks[n]=brick;
   g_total_bricks++;
  }

bool WriteSummary(const string state)
  {
   if(g_base=="") return false;
   const int handle=FileOpen(g_base+"_summary.txt",FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ,0,CP_UTF8);
   if(handle==INVALID_HANDLE) return false;
   string text="GDS Renko Replay Trainer v0.12\r\nState: "+state+
      "\r\nSymbol: "+_Symbol+"\r\nInterval (server time): "+g_period+
      "\r\nLast replay quote: "+(g_have_quote ? Stamp(g_quote.time_msc) : "none")+
      "\r\nBrick price size: "+DoubleToString(g_brick_size,_Digits)+
      "\r\nVirtual lot: "+DoubleToString(InpVirtualLot,4)+
      "\r\nInitial SL/TP bricks: "+DoubleToString(InpStopBricks,2)+" / "+DoubleToString(InpTargetBricks,2)+
      "\r\nRound-turn commission per lot: "+DoubleToString(InpCommissionLotRT,2)+
      "\r\nAccount currency: "+g_currency+
      "\r\nInitial balance: "+DoubleToString(InpInitialBalance,2)+
      "\r\nBalance: "+DoubleToString(g_account.Balance(),2)+
      "\r\nEquity: "+DoubleToString(g_account.Equity(),2)+
      "\r\nNet balance change: "+DoubleToString(g_account.Net(),2)+
      "\r\nMaximum equity DD: "+DoubleToString(g_account.Drawdown(),2)+
      " ("+DoubleToString(g_account.DrawdownPct(),2)+"%)"+
      "\r\nMaximum normalized equity DD: "+DoubleToString(g_account.DrawdownR(),3)+" R"+
      "\r\nClosed trades: "+IntegerToString(g_account.Trades())+
      "\r\nWin rate: "+DoubleToString(g_account.WinRate(),2)+"%"+
      "\r\nPF (net closed trades): "+g_account.PF()+
      "\r\nClosed result: "+DoubleToString(g_account.TotalR(),3)+" R"+
      "\r\nOpen virtual position: "+(g_account.IsOpen() ? "YES - equity is marked, not a closed result" : "NO")+
      "\r\nConsumed rows: "+IntegerToString(g_seen_ticks)+
      "\r\nInvalid quote rows skipped: "+IntegerToString(g_bad_ticks)+
      "\r\nCompleted bricks: "+IntegerToString(g_total_bricks)+
      "\r\nQuote gaps longer than 5 minutes: "+IntegerToString(g_gap_count)+
      "\r\nLargest observed gap, seconds: "+DoubleToString(g_max_gap_msc/1000.0,3)+
      "\r\n\r\nMODEL: Historical broker Bid/Ask ticks; no OHLC-generated paths.\r\n"+
      "Commands execute on the next consumed valid quote. SL/TP use executable Bid/Ask; gaps fill at that quote.\r\n"+
      "A SESSION_END valuation uses the last available quote, not a new executable market event.\r\n"+
      "Cash valuation freezes current OrderCalcProfit coefficients at session start. Historical conversion,\r\n"+
      "historical contract changes, swap, margin/stop-out, liquidity, latency and additional slippage are not simulated.\r\n"+
      "Commission is the user-specified round-turn amount, reserved in full at virtual entry.\r\n"+
      "R denominator = initial SL cash risk + commission. No source-history completeness guarantee.\r\n"+
      "This is manual educational practice, not evidence of a persistent trading edge.\r\n";
   const uint bytes=FileWriteString(handle,text);
   FileClose(handle);
   return bytes>0;
  }

bool Journal(const STrade &trade)
  {
   if(g_file==INVALID_HANDLE) return false;
   const uint bytes=FileWrite(g_file,trade.id,(trade.dir>0 ? "BUY" : "SELL"),
      Stamp(trade.entry_msc),Stamp(trade.exit_msc),DoubleToString(trade.entry,_Digits),
      DoubleToString(trade.exit,_Digits),DoubleToString(trade.sl,_Digits),DoubleToString(trade.tp,_Digits),
      DoubleToString(trade.lot,4),DoubleToString(trade.gross,2),DoubleToString(trade.commission,2),
      DoubleToString(trade.net,2),DoubleToString(trade.r,5),trade.reason);
   FileFlush(g_file);
   g_last_trade=StringFormat("Last #%d %s | %s %s | %.2f R | %s",trade.id,
      (trade.dir>0 ? "BUY" : "SELL"),DoubleToString(trade.net,2),g_currency,trade.r,trade.reason);
   if(bytes==0) { Fail("Journal write failed. Training paused; check disk space."); return false; }
   return true;
  }

void Finish(const string reason)
  {
   // End-of-interval liquidation is an explicit mark at the last known quote.
   if(g_account.IsOpen() && g_have_quote)
     {
      STrade trade={};
      if(g_account.Close(g_quote,"SESSION_END",trade))
         if(!Journal(trade)) return;
     }
   g_command=0; g_tokens=0; g_phase=FINISHED; g_end_reason=reason;
   g_note=reason+" Export saved. NEW starts another session.";
   if(!WriteSummary("FINISHED - "+reason)) g_note="Finished, but summary export failed. CSV remains available.";
   if(g_file!=INVALID_HANDLE) { FileClose(g_file); g_file=INVALID_HANDLE; }
  }

// Return false when the current window cannot yet be safely consumed.
bool LoadChunk(void)
  {
   if(g_load_from>=g_end_msc) { Finish("Selected interval ended."); return false; }
   if(GetTickCount64()<g_next_retry) return false;
   ulong to=g_load_from+CHUNK_MSC-1;
   if(to>=g_end_msc) to=g_end_msc-1;
   ArrayResize(g_buffer,0); g_buffer_index=0;
   ResetLastError();
   const int n=CopyTicksRange(_Symbol,g_buffer,COPY_TICKS_ALL,g_load_from,to);
   const int error=GetLastError();
   // A positive partial result accompanied by TIMEOUT is NOT committed.
   if(n<0 || error!=0)
     {
      ArrayResize(g_buffer,0);
      g_load_failures++;
      g_next_retry=GetTickCount64()+2000;
      g_note=StringFormat("Waiting for history, attempt %d/3 (error %d).",g_load_failures,error);
      if(g_load_failures>=3) Fail("History unavailable/partial. Press RETRY after terminal download completes.",true);
      return false;
     }
   long last=g_last_raw_msc;
   for(int i=0;i<n;i++)
     {
      const long stamp=g_buffer[i].time_msc;
      if(stamp<(long)g_load_from || stamp>(long)to || (last>0 && stamp<last))
        {
         ArrayResize(g_buffer,0);
         Fail("Tick timestamps are out of order/range. Window was not consumed.");
         return false;
        }
      last=stamp;
     }
   g_load_from=to+1; // Complete window boundary: keep ALL equal-millisecond ticks.
   g_load_failures=0; g_next_retry=0;
   if(n==0)
     {
      g_note="No ticks in this window; checking the next window. No prices are synthesized.";
      return false;
     }
   g_note="History ready. Only consumed ticks are displayed.";
   return true;
  }

// Consumes exactly one source row. No drawing/account code receives g_buffer.
bool ConsumeOne(void)
  {
   if(g_buffer_index>=ArraySize(g_buffer)) return false;
   const MqlTick tick=g_buffer[g_buffer_index++];
   g_seen_ticks++; g_last_raw_msc=tick.time_msc;
   if(!ValidQuote(tick)) { g_bad_ticks++; return false; }
   if(g_have_quote)
     {
      const long gap=tick.time_msc-g_quote.time_msc;
      g_max_gap_msc=(long)MathMax(g_max_gap_msc,gap);
      if(gap>300000) g_gap_count++;
     }
   SBrick fresh[];
   const int n=g_renko.Push(tick.bid,tick.time_msc,fresh);
   if(n<0) { Fail("Too many bricks in one tick. Increase Brick Size and LOAD again."); return false; }
   for(int i=0;i<n;i++) KeepBrick(fresh[i]);
   if(g_phase==DATA_ERROR) return false;
   g_quote=tick; g_have_quote=true;
   const int command=g_command;
   g_command=0;
   STrade closed={};
   const bool stopped=g_account.CheckStops(tick,closed);
   if(stopped)
     {
      if(!Journal(closed)) return true;
      g_note="Virtual "+closed.reason+" filled at this quote.";
     }
   else if(command==2 && g_account.IsOpen())
     {
      if(g_account.Close(tick,"MANUAL",closed))
        {
         if(!Journal(closed)) return true;
         g_note="Virtual close filled on the next quote.";
        }
     }
   else if((command==1 || command==-1) && !g_account.IsOpen())
     {
      if(g_account.Open(command,tick,InpStopBricks*g_brick_size,InpTargetBricks*g_brick_size))
         g_note="Virtual entry filled at Ask/Bid. SL/TP are active.";
      else g_note="Entry rejected: check spread, stop distance or virtual balance.";
     }
   g_account.Mark(tick);
   return true;
  }

bool FreezeValuation(double &lg,double &ll,double &sg,double &sl)
  {
   MqlTick live={};
   if(!SymbolInfoTick(_Symbol,live) || !ValidQuote(live)) return false;
   const double price=live.bid;
   double value=0;
   if(price<=g_tick_size) return false;
   if(!OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,InpVirtualLot,price,price+g_tick_size,value) || value<=0) return false;
   lg=value/g_tick_size;
   if(!OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,InpVirtualLot,price,price-g_tick_size,value) || value>=0) return false;
   ll=-value/g_tick_size;
   if(!OrderCalcProfit(ORDER_TYPE_SELL,_Symbol,InpVirtualLot,price,price-g_tick_size,value) || value<=0) return false;
   sg=value/g_tick_size;
   if(!OrderCalcProfit(ORDER_TYPE_SELL,_Symbol,InpVirtualLot,price,price+g_tick_size,value) || value>=0) return false;
   sl=-value/g_tick_size;
   return MathIsValidNumber(lg) && MathIsValidNumber(ll) && MathIsValidNumber(sg) && MathIsValidNumber(sl);
  }

datetime DefaultStart(const datetime now)
  {
   MqlDateTime dt={};
   if(!TimeToStruct(now,dt)) return 0;
   datetime start=now-(dt.hour*3600+dt.min*60+dt.sec)-86400;
   for(int i=0;i<3;i++)
     {
      if(!TimeToStruct(start,dt)) return 0;
      if(dt.day_of_week!=0 && dt.day_of_week!=6) break;
      start-=86400;
     }
   return start+9*3600;
  }

void StartSession(void)
  {
   if(g_small) { g_note="Enlarge the chart to at least 800 x 560 pixels."; return; }
   if(g_valued && g_account.IsOpen())
     { g_note="Close the virtual position or press END before a new session."; return; }
   if(g_valued && g_phase!=FINISHED)
     { g_note="Session already loaded. Use END before NEW."; return; }
   const datetime now=TimeCurrent();
   const datetime start=(InpReplayStart>0 ? InpReplayStart : DefaultStart(now));
   const datetime end=start+(long)InpReplayHours*3600;
   if(start<=0 || end>=now)
     { g_note="Choose a fully historical interval: its end must be before server time now."; return; }
   double lg=0,ll=0,sg=0,sl=0;
   if(!FreezeValuation(lg,ll,sg,sl))
     { g_note="Cannot calculate virtual cash value. Check symbol quotes/account connection and press LOAD."; return; }
   if(g_valued && g_phase!=FINISHED) WriteSummary("STOPPED / new session");
   if(g_file!=INVALID_HANDLE) { FileClose(g_file); g_file=INVALID_HANDLE; }
   FolderCreate("GDS_Renko_Trainer");
   string symbol=_Symbol;
   StringReplace(symbol,"/","_"); StringReplace(symbol,"\\","_"); StringReplace(symbol,":","_");
   g_base="GDS_Renko_Trainer\\"+symbol+"_"+IntegerToString((long)TimeLocal())+"_"+
          IntegerToString(ChartID())+"_"+IntegerToString((long)GetTickCount64());
   g_file=FileOpen(g_base+"_trades.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';',CP_UTF8);
   if(g_file==INVALID_HANDLE) { Fail("Cannot create journal in MQL5/Files. Check filesystem permissions."); return; }
   if(FileWrite(g_file,"id","side","entry_server_time","exit_server_time","entry","exit","sl","tp",
                "virtual_lot","gross_estimate","commission","net_estimate","R","exit_reason")==0)
     { FileClose(g_file); g_file=INVALID_HANDLE; Fail("Cannot write journal header."); return; }
   FileFlush(g_file);
   g_account.Init(InpInitialBalance,InpVirtualLot,InpCommissionLotRT*InpVirtualLot,g_tick_size,lg,ll,sg,sl);
   g_renko.Init(g_tick_size,(long)MathRound(g_brick_size/g_tick_size));
   ArrayResize(g_bricks,0); ArrayResize(g_buffer,0); g_buffer_index=0;
   g_from_msc=(ulong)start*1000; g_end_msc=(ulong)end*1000; g_load_from=g_from_msc;
   g_seen_ticks=0; g_bad_ticks=0; g_total_bricks=0; g_gap_count=0; g_max_gap_msc=0; g_last_raw_msc=0;
   g_history_retryable=false; g_have_quote=false; g_command=0; g_load_failures=0; g_next_retry=0;
   g_tokens=0; g_last_clock=GetTickCount64(); g_valued=true;
   g_period=TimeToString(start,TIME_DATE|TIME_MINUTES)+" -> "+TimeToString(end,TIME_DATE|TIME_MINUTES);
   g_end_reason=""; g_phase=WAIT_DATA; g_resume=READY;
   g_last_trade="No closed virtual trades.";
   g_note="Loading historical ticks. The first download may take time.";
   Print("GDS Renko Trainer: session ",g_period,"; journal MQL5/Files/",g_base,"_trades.csv");
  }

//---------------------------- UI ------------------------------------
void Rect(const string key,const int x,const int y,const int width,const int height,
          const color background,const color border)
  {
   const string name=PREFIX+key;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,MathMax(1,width)); ObjectSetInteger(0,name,OBJPROP_YSIZE,MathMax(1,height));
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,background); ObjectSetInteger(0,name,OBJPROP_COLOR,border);
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_BACK,false); ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

// Short text objects avoid terminal-side truncation of long OBJ_LABEL strings.
// Empty labels are deleted: assigning an empty string can display "Label".
void DeleteLabel(const string key)
  {
   ObjectDelete(0,PREFIX+key);
   for(int i=1;i<8;i++) ObjectDelete(0,PREFIX+key+"_part"+IntegerToString(i));
  }

int TextWidth(const string text,const int size)
  {
   uint width=0,height=0;
   if(TextSetFont("Segoe UI",-10*size,0) && TextGetSize(text,width,height)) return (int)width;
   return (int)MathCeil(StringLen(text)*size*0.85);
  }

void Label(const string key,const string text,const int x,const int y,const color ink,const int size=10)
  {
   if(text=="") { DeleteLabel(key); return; }
   string shown=text;
   const int available=g_width-x-16;
   // Fit to the actual available chart width, rather than a fixed character count.
   if(TextWidth(shown,size)>available)
     {
      while(StringLen(shown)>0 && TextWidth(shown+"...",size)>available)
         shown=StringSubstr(shown,0,StringLen(shown)-1);
      shown+="...";
     }
   const int count=(StringLen(shown)+47)/48;
   for(int i=0;i<8;i++)
     {
      const string name=PREFIX+key+(i==0 ? "" : "_part"+IntegerToString(i));
      if(i>=count) { ObjectDelete(0,name); continue; }
      const string part=StringSubstr(shown,i*48,48);
      const int offset=(i==0 ? 0 : TextWidth(StringSubstr(shown,0,i*48),size));
      if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x+offset);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(0,name,OBJPROP_COLOR,ink); ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_FONT,"Segoe UI"); ObjectSetString(0,name,OBJPROP_TEXT,part);
     }
  }

void Button(const string key,const string text,const int x,const int y,const int width,const color bg)
  {
   const string name=PREFIX+key;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width); ObjectSetInteger(0,name,OBJPROP_YSIZE,30);
   ObjectSetInteger(0,name,OBJPROP_COLOR,C_TEXT); ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,C_GRID); ObjectSetInteger(0,name,OBJPROP_FONTSIZE,10);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,10); ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetString(0,name,OBJPROP_FONT,"Segoe UI"); ObjectSetString(0,name,OBJPROP_TEXT,text);
  }

string PhaseName(void)
  {
   if(g_phase==IDLE) return "READY TO LOAD";
   if(g_phase==WAIT_DATA) return "LOADING";
   if(g_phase==RUNNING) return "PLAYING";
   if(g_phase==STEP_TICK || g_phase==STEP_BRICK) return "STEPPING";
   if(g_phase==FINISHED) return "FINISHED";
   if(g_phase==DATA_ERROR) return "PAUSED / CHECK DATA";
   return "PAUSED";
  }

int PriceY(const double price,const double low,const double high,const int top,const int height)
  {
   return top+(int)MathRound((high-price)/(high-low)*height);
  }

void PlotLevel(const string key,const double price,const string caption,const color ink,
               const double low,const double high,const int top,const int height,const int width)
  {
   const int y=PriceY(price,low,high,top,height);
   Rect(key+"line",22,y,width,1,ink,ink);
   // Distinct horizontal lanes keep coincident levels readable without moving prices.
   const int label_x=(key=="bid" ? 28 : (key=="entry" ? 205 : (key=="sl" ? 382 : 559)));
   Label(key+"text",caption+" "+DoubleToString(price,_Digits),label_x,y-18,ink,9);
  }

void Render(void)
  {
   if(g_rendering) return;
   g_rendering=true;
   const int width=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   const int height=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   const bool resized=(width!=g_width || height!=g_height);
   if(resized) ObjectsDeleteAll(0,PREFIX); // Rebuild only our objects when geometry changes.
   g_width=width; g_height=height; g_small=(width<800 || height<560);
   if(g_small)
     {
      if(g_phase==RUNNING || g_phase==STEP_TICK || g_phase==STEP_BRICK) Pause("Chart too small; replay paused.");
      Rect("background",0,0,width,height,C_BG,C_BG);
      Label("resize","GDS RENKO TRAINER | enlarge chart to 800 x 560 pixels",16,20,C_WARN,11);
      ChartRedraw(); g_rendering=false; return;
     }
   DeleteLabel("resize");
   Rect("background",0,0,width,height,C_BG,C_BG);
   Label("title","GDS RENKO REPLAY TRAINER",22,14,C_TEXT,18);
   Label("virtual","VIRTUAL ONLY",width-142,20,C_UP,10);
   Label("subtitle",_Symbol+"  |  brick "+DoubleToString(g_brick_size,_Digits)+
         "  |  "+(g_period=="" ? "Start/duration: set in F7 inputs (server time)" : g_period),22,45,C_MUTED,10);
   Button("load",(g_phase==DATA_ERROR && g_history_retryable ? "RETRY" : (g_valued ? "LOADED" : "LOAD")),22,76,82,C_PANEL);
   Button("play",(g_phase==RUNNING ? "PAUSE" : "PLAY"),112,76,82,C_PANEL);
   Button("tick","NEXT TICK",202,76,98,C_PANEL);
   Button("brick","NEXT BRICK",308,76,110,C_PANEL);
   Button("minus","-",434,76,32,C_PANEL); Button("plus","+",472,76,32,C_PANEL);
   Label("speed",IntegerToString(g_speed)+" ticks/s",516,82,C_ACCENT,10);
   Button("export","EXPORT",width-116,76,94,C_PANEL);
   Button("buy","BUY",22,118,82,C'22,108,88');
   Button("sell","SELL",112,118,82,C'132,47,64');
   Button("close","CLOSE",202,118,98,C_PANEL);
   Button("end","END",308,118,110,C_PANEL);
   Label("risk",StringFormat("%.2f lot | SL %.1f / TP %.1f",InpVirtualLot,InpStopBricks,InpTargetBricks),434,123,C_MUTED,9);
   Button("new","NEW",width-116,118,94,C_PANEL);
   Label("model",StringFormat("Cash estimates: %s | commission RT/lot %.2f | no swap or margin model",g_currency,InpCommissionLotRT),22,158,C_MUTED,9);
   Label("clock",(g_have_quote ? "Replay  "+Stamp(g_quote.time_msc)+"  |  Bid "+DoubleToString(g_quote.bid,_Digits)+
         "  Ask "+DoubleToString(g_quote.ask,_Digits) : "Replay  -- waiting for the first historical quote"),22,181,C_TEXT,10);
   string note=g_note;
   const int max_chars=(width-44)/7;
   if(StringLen(note)>max_chars) note=StringSubstr(note,0,max_chars-3)+"...";
   Label("note",note,22,204,C_WARN,9);

   const int top=240,plot_h=height-420,plot_w=width-125;
   Rect("plot",20,top-12,width-40,plot_h+34,C_PANEL,C_GRID);
   const int n=ArraySize(g_bricks);
   const int count=MathMin(n,InpVisibleBricks);
   double low=0,high=0;
   if(g_have_quote) { low=g_quote.bid; high=g_quote.ask; }
   for(int i=n-count;i<n;i++)
     {
      low=MathMin(low,MathMin(g_bricks[i].open,g_bricks[i].close));
      high=MathMax(high,MathMax(g_bricks[i].open,g_bricks[i].close));
     }
   STrade pos={};
   if(g_valued && g_account.IsOpen())
     {
      g_account.Position(pos);
      low=MathMin(low,MathMin(pos.sl,pos.tp)); high=MathMax(high,MathMax(pos.sl,pos.tp));
     }
   if(!g_have_quote) { low=0; high=10*g_brick_size; }
   const double padding=MathMax(g_brick_size,(high-low)*0.12);
   low-=padding; high+=padding;
   for(int i=0;i<5;i++)
     {
      const double price=high-(high-low)*i/4.0;
      const int y=PriceY(price,low,high,top,plot_h);
      Rect("grid"+IntegerToString(i),22,y,plot_w,1,C_GRID,C_GRID);
      Label("axis"+IntegerToString(i),(g_have_quote ? DoubleToString(price,_Digits) : ""),width-95,y-7,C_MUTED,9);
     }
   const double spacing=(plot_w-22.0)/InpVisibleBricks;
   for(int i=0;i<InpVisibleBricks;i++)
     {
      const string key="b"+IntegerToString(i);
      if(i>=count) { ObjectDelete(0,PREFIX+key); continue; }
      const SBrick brick=g_bricks[n-count+i];
      const int x=32+(int)MathRound((InpVisibleBricks-count+i)*spacing);
      const int y1=PriceY(MathMax(brick.open,brick.close),low,high,top,plot_h);
      const int y2=PriceY(MathMin(brick.open,brick.close),low,high,top,plot_h);
      const color ink=(brick.direction>0 ? C_UP : C_DOWN);
      Rect(key,x,y1,MathMax(2,(int)spacing-2),MathMax(2,y2-y1),ink,ink);
     }
   if(g_have_quote) PlotLevel("bid",g_quote.bid,"BID",C_ACCENT,low,high,top,plot_h,plot_w);
   else { ObjectDelete(0,PREFIX+"bidline"); DeleteLabel("bidtext"); }
   if(g_valued && g_account.IsOpen())
     {
      PlotLevel("entry",pos.entry,"ENTRY",C_TEXT,low,high,top,plot_h,plot_w);
      PlotLevel("sl",pos.sl,"SL",C_DOWN,low,high,top,plot_h,plot_w);
      PlotLevel("tp",pos.tp,"TP",C_UP,low,high,top,plot_h,plot_w);
     }
   else
     {
      ObjectDelete(0,PREFIX+"entryline"); DeleteLabel("entrytext");
      ObjectDelete(0,PREFIX+"slline"); DeleteLabel("sltext");
      ObjectDelete(0,PREFIX+"tpline"); DeleteLabel("tptext");
     }
   Label("empty",(count==0 ? "Completed Renko bricks appear after price moves by one full brick." : ""),40,top+plot_h/2,C_MUTED,10);
   const int foot=height-147;
   Label("state",PhaseName()+" | rows "+IntegerToString(g_seen_ticks)+" | bricks "+IntegerToString(g_total_bricks)+
         " | skipped quotes "+IntegerToString(g_bad_ticks),22,foot,C_MUTED,9);
   Label("money",StringFormat("Balance %.2f   Equity %.2f   Max equity DD %.2f (%.2f%%)",
         g_account.Balance(),g_account.Equity(),g_account.Drawdown(),g_account.DrawdownPct()),22,foot+25,C_TEXT,11);
   Label("stats",StringFormat("Closed %d   Win %.1f%%   PF %s   Result %.2f R   DD %.2f R",g_account.Trades(),
         g_account.WinRate(),g_account.PF(),g_account.TotalR(),g_account.DrawdownR()),22,foot+50,C_TEXT,10);
   string position=(g_account.IsOpen() ? StringFormat("Open virtual #%d %s",pos.id,(pos.dir>0 ? "BUY" : "SELL")) : "No open position");
   if(g_command!=0) position+=" | QUEUED "+(g_command==2 ? "CLOSE" : (g_command>0 ? "BUY" : "SELL"))+" -> next valid tick";
   Label("position",position,22,foot+75,C_ACCENT,10);
   Label("last",g_last_trade,22,foot+99,C_MUTED,9);
   Label("hint","F7: settings | END then NEW: restart | Files: MQL5/Files/GDS_Renko_Trainer",22,height-22,C_MUTED,9);
   ChartRedraw(); g_rendering=false;
  }

void QueueCommand(const int command)
  {
   if(!g_valued || !g_have_quote || g_phase==FINISHED || g_phase==DATA_ERROR || g_small)
     { g_note="LOAD a session and display a valid historical quote first."; return; }
   if(g_command!=0) { g_note="An action is already queued for the next valid tick."; return; }
   if(command==2 && !g_account.IsOpen()) { g_note="No virtual position to close."; return; }
   if(command!=2 && g_account.IsOpen()) { g_note="One virtual position at a time. Close it first."; return; }
   g_command=command;
   g_note="Action queued. Press NEXT TICK or PLAY to execute on the next valid quote.";
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(g_tester_mode) return;
   if(id==CHARTEVENT_CHART_CHANGE) { Render(); return; }
   if(id!=CHARTEVENT_OBJECT_CLICK || StringFind(sparam,PREFIX)!=0) return;
   ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
   const string key=StringSubstr(sparam,StringLen(PREFIX));
   if(key=="load")
     {
      if(g_phase==DATA_ERROR && g_history_retryable && g_valued && g_file!=INVALID_HANDLE)
        {
         g_load_failures=0; g_next_retry=0; g_phase=WAIT_DATA; g_resume=READY;
         g_note="Retrying the unconsumed data window.";
        }
      else if(!g_valued) StartSession();
      else g_note="Already loaded. Use PLAY or NEXT BRICK; END then NEW to restart.";
     }
   else if(key=="new")
     {
      if(g_valued && g_phase!=FINISHED) g_note="Use END to finish and save this session before NEW.";
      else StartSession();
     }
   else if(key=="buy") QueueCommand(1);
   else if(key=="sell") QueueCommand(-1);
   else if(key=="close") QueueCommand(2);
   else if(key=="end" && g_valued && g_phase!=FINISHED) Finish("Session ended by user (last-quote valuation).");
   else if(key=="export")
     {
      if(WriteSummary(g_phase==FINISHED ? "FINISHED - "+g_end_reason : PhaseName()))
        {
         if(g_file!=INVALID_HANDLE) FileFlush(g_file);
         g_note="Export saved. Full file names are in the Experts journal.";
         Print("GDS Renko Trainer export: MQL5/Files/",g_base,"_trades.csv and ",g_base,"_summary.txt");
        }
      else g_note="Nothing to export yet, or file write failed.";
     }
   else if(key=="minus") { g_speed=MathMax(1,g_speed/2); g_tokens=0; }
   else if(key=="plus") { g_speed=MathMin(1000,g_speed*2); g_tokens=0; }
   else if(key=="play" || key=="tick" || key=="brick")
     {
      if(g_phase==RUNNING || g_phase==STEP_TICK || g_phase==STEP_BRICK)
         Pause("Replay paused.");
      else if(g_phase==READY && g_have_quote)
        {
         g_phase=(key=="play" ? RUNNING : (key=="tick" ? STEP_TICK : STEP_BRICK));
         g_tokens=0; g_last_clock=GetTickCount64(); g_note="Replaying historical ticks forward.";
        }
      else g_note="Press LOAD and wait for the first quote.";
     }
   Render();
  }

void OnTimer(void)
  {
   if(g_tester_mode) return;
   const ulong now=GetTickCount64();
   const ulong elapsed=(g_last_clock>0 ? now-g_last_clock : (ulong)TIMER_MS);
   g_last_clock=now;
   if(g_phase==WAIT_DATA)
     {
      if(g_buffer_index>=ArraySize(g_buffer))
        {
         if(!LoadChunk()) { Render(); return; }
        }
      // Bootstrap ONE valid quote; never scan future bricks to warm up.
      if(!g_have_quote)
        {
         int limit=500;
         while(limit-->0 && g_buffer_index<ArraySize(g_buffer) && !g_have_quote && g_phase!=DATA_ERROR)
            ConsumeOne();
         if(!g_have_quote) { Render(); return; }
        }
      if(g_phase!=DATA_ERROR && g_phase!=FINISHED) g_phase=g_resume;
      g_tokens=0; Render(); return;
     }
   if(g_phase!=RUNNING && g_phase!=STEP_TICK && g_phase!=STEP_BRICK) return;
   const EPhase operation=g_phase;
   if(operation==RUNNING) g_tokens=MathMin(2000.0,g_tokens+g_speed*MathMin((double)elapsed,1000.0)/1000.0);
   const int budget=(operation==RUNNING ? (int)g_tokens : (operation==STEP_TICK ? 500 : 3000));
   const long initial_bricks=g_total_bricks;
   int used=0;
   for(int i=0;i<budget;i++)
     {
      if(g_buffer_index>=ArraySize(g_buffer))
        {
         g_resume=operation; g_phase=WAIT_DATA;
         g_note="Loading the next historical window...";
         break;
        }
      const bool quote=ConsumeOne(); used++;
      if(g_phase==DATA_ERROR || g_phase==FINISHED) break;
      if((operation==STEP_TICK && quote) || (operation==STEP_BRICK && g_total_bricks>initial_bricks))
        { Pause("Step complete. BUY / SELL queues entry for the next tick."); break; }
      if(GetTickCount64()-now>=25) break; // Keep the panel responsive even at high speeds.
     }
   if(operation==RUNNING) g_tokens=MathMax(0.0,g_tokens-used);
   Render();
  }

int OnInit(void)
  {
   // Interactive replay is a normal-chart utility, not an automated strategy.
   // A tester run is an explicit inactive mode: no replay, files or broker orders.
   // This is not a trading test and does not claim validation success.
   g_tester_mode=(bool)MQLInfoInteger(MQL_TESTER);
   if(g_tester_mode)
     {
      Print("GDS Renko Replay Trainer: Strategy Tester inactive mode. ",
            "This utility does not perform automated trading. ",
            "Attach it to a new empty NORMAL chart and press LOAD for virtual practice.");
      return INIT_SUCCEEDED;
     }
   if(InpReplayHours<1 || InpReplayHours>72 || InpVisibleBricks<20 || InpVisibleBricks>160 ||
      InpTicksPerSecond<1 || InpTicksPerSecond>1000 ||
      !MathIsValidNumber(InpBrickSize) || InpBrickSize<=0 ||
      !MathIsValidNumber(InpStopBricks) || InpStopBricks<=0 ||
      !MathIsValidNumber(InpTargetBricks) || InpTargetBricks<=0 ||
      !MathIsValidNumber(InpVirtualLot) || InpVirtualLot<=0 ||
      !MathIsValidNumber(InpInitialBalance) || InpInitialBalance<=0 ||
      !MathIsValidNumber(InpCommissionLotRT) || InpCommissionLotRT<0)
     { Print("GDS Renko Trainer: invalid inputs."); return INIT_PARAMETERS_INCORRECT; }
   g_tick_size=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(g_tick_size<=0 || !MathIsValidNumber(g_tick_size))
     { Print("Symbol tick size is unavailable. Load symbol quotes and attach again."); return INIT_FAILED; }
   const double units=InpBrickSize/g_tick_size;
   if(units<1 || units>1e9 || MathAbs(units-MathRound(units))>1e-6)
     { Print("Brick Size must be a positive multiple of symbol trade tick size: ",g_tick_size); return INIT_PARAMETERS_INCORRECT; }
   const double minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   const double maximum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   const double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0 || minimum<=0 || maximum<minimum || InpVirtualLot<minimum-1e-9 || InpVirtualLot>maximum+1e-9 ||
      MathAbs(InpVirtualLot/step-MathRound(InpVirtualLot/step))>1e-6)
     { Print("Virtual lot must match symbol volume min/max/step; it is never increased automatically."); return INIT_PARAMETERS_INCORRECT; }
   const int windows=(int)ChartGetInteger(0,CHART_WINDOWS_TOTAL);
   for(int i=0;i<windows;i++)
      if(ChartIndicatorsTotal(0,i)>0)
        { Print("Use a new empty chart without indicators. Existing indicators were not changed."); return INIT_FAILED; }
   if(ObjectsTotal(0,-1,-1)>0)
     { Print("Use a new empty chart without drawing objects. Existing objects were not changed."); return INIT_FAILED; }
   g_brick_size=MathRound(units)*g_tick_size;
   g_currency=AccountInfoString(ACCOUNT_CURRENCY);
   g_speed=InpTicksPerSecond;
   g_chart_show=ChartGetInteger(0,CHART_SHOW);
   g_chart_bg=ChartGetInteger(0,CHART_COLOR_BACKGROUND);
   g_chart_foreground=ChartGetInteger(0,CHART_FOREGROUND);
   g_chart_saved=true;
   if(!ChartSetInteger(0,CHART_SHOW,false) ||
      !ChartSetInteger(0,CHART_COLOR_BACKGROUND,C_BG) ||
      !ChartSetInteger(0,CHART_FOREGROUND,false))
     { Print("Cannot prepare trainer chart. Original chart properties will be restored."); return INIT_FAILED; }
   g_account.Init(InpInitialBalance,InpVirtualLot,0,g_tick_size,1,1,1,1);
   g_phase=IDLE; g_valued=false; g_have_quote=false;
   g_last_clock=GetTickCount64();
   if(!EventSetMillisecondTimer(TIMER_MS))
     { Print("Cannot start replay timer."); return INIT_FAILED; }
   Render();
   Print("GDS Renko Replay Trainer v0.12: virtual only. AutoTrading is not required. Press LOAD.");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_tester_mode) return;
   EventKillTimer();
   // Removing/changing inputs saves a marked snapshot; never invent an exit.
   if(g_valued && g_phase!=FINISHED) WriteSummary("DETACHED - state not resumable; open position, if any, remains marked only");
   if(g_file!=INVALID_HANDLE) { FileFlush(g_file); FileClose(g_file); g_file=INVALID_HANDLE; }
   if(g_chart_saved)
     {
      ObjectsDeleteAll(0,PREFIX);
      ChartSetInteger(0,CHART_SHOW,g_chart_show);
      ChartSetInteger(0,CHART_COLOR_BACKGROUND,g_chart_bg);
      ChartSetInteger(0,CHART_FOREGROUND,g_chart_foreground);
      ChartRedraw();
     }
  }
//+------------------------------------------------------------------+
