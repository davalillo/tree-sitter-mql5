//+------------------------------------------------------------------+
//|                         GDS_Renko_Brick_Statistics_v0.10.mq5     |
//|                     Golden Delta - CodeBase Edition              |
//|                         https://goldendeltaea.com/                |
//+------------------------------------------------------------------+
#property copyright "Golden Delta"
#property link      "https://goldendeltaea.com/"
#property version   "0.10"
#property description "Compact statistics panel for classic fixed-size Renko built directly from BID ticks."
#property description "Shows direction balance, reversal rate, run lengths and brick formation speed."
#property description "No DLLs, custom symbols, offline charts or external indicators are required."
#property indicator_chart_window
#property indicator_plots 0

#include <Canvas\Canvas.mqh>

input double InpBrickSize      = 1.00; // Brick size in price units
input int    InpLookbackBricks = 200;  // Completed bricks used for statistics

#define GDS_HISTORY_TICKS       400000
#define GDS_MAX_STORED_BRICKS     4000
#define GDS_PANEL_WIDTH            430
#define GDS_PANEL_HEIGHT           292
#define GDS_PANEL_X                 10
#define GDS_PANEL_Y                 24

const color GDS_BG       = C'14,18,24';
const color GDS_FRAME    = C'55,68,82';
const color GDS_TEXT     = clrWhite;
const color GDS_MUTED    = C'160,170,180';
const color GDS_UP       = clrDeepSkyBlue;
const color GDS_DOWN     = clrTomato;
const color GDS_ACCENT   = clrGold;

struct SRenkoBrick
  {
   double open;
   double close;
   int    direction;
   long   time_msc;
  };

class CRenkoBuilder
  {
private:
   double m_size;
   bool   m_has_anchor;
   double m_anchor;
   double m_last_close;
   int    m_last_dir;

   void AddBrick(SRenkoBrick &out[],
                 const double open_price,
                 const double close_price,
                 const int direction,
                 const long time_msc)
     {
      const int n=ArraySize(out);
      ArrayResize(out,n+1);
      out[n].open=NormalizeDouble(open_price,_Digits);
      out[n].close=NormalizeDouble(close_price,_Digits);
      out[n].direction=direction;
      out[n].time_msc=time_msc;
     }

public:
   CRenkoBuilder(void)
     {
      m_size=0.0;
      Reset();
     }

   void Init(const double brick_size)
     {
      m_size=brick_size;
      Reset();
     }

   void Reset(void)
     {
      m_has_anchor=false;
      m_anchor=0.0;
      m_last_close=0.0;
      m_last_dir=0;
     }

   int PushPrice(const double price,const long time_msc,SRenkoBrick &out[])
     {
      ArrayResize(out,0);
      if(m_size<=0.0 || price<=0.0)
         return 0;

      if(!m_has_anchor)
        {
         m_anchor=price;
         m_has_anchor=true;
         return 0;
        }

      int added=0;

      if(m_last_dir==0)
        {
         while(price>=m_anchor+m_size)
           {
            const double brick_open=m_anchor;
            m_anchor+=m_size;
            m_last_close=m_anchor;
            m_last_dir=+1;
            AddBrick(out,brick_open,m_last_close,+1,time_msc);
            added++;
           }

         while(price<=m_anchor-m_size)
           {
            const double brick_open=m_anchor;
            m_anchor-=m_size;
            m_last_close=m_anchor;
            m_last_dir=-1;
            AddBrick(out,brick_open,m_last_close,-1,time_msc);
            added++;
           }
         return added;
        }

      bool changed=true;
      while(changed)
        {
         changed=false;

         if(m_last_dir>0)
           {
            if(price>=m_last_close+m_size)
              {
               const double brick_open=m_last_close;
               const double brick_close=m_last_close+m_size;
               AddBrick(out,brick_open,brick_close,+1,time_msc);
               m_last_close=brick_close;
               added++;
               changed=true;
              }
            else if(price<=m_last_close-2.0*m_size)
              {
               const double brick_open=m_last_close-m_size;
               const double brick_close=m_last_close-2.0*m_size;
               AddBrick(out,brick_open,brick_close,-1,time_msc);
               m_last_close=brick_close;
               m_last_dir=-1;
               added++;
               changed=true;
              }
           }
         else
           {
            if(price<=m_last_close-m_size)
              {
               const double brick_open=m_last_close;
               const double brick_close=m_last_close-m_size;
               AddBrick(out,brick_open,brick_close,-1,time_msc);
               m_last_close=brick_close;
               added++;
               changed=true;
              }
            else if(price>=m_last_close+2.0*m_size)
              {
               const double brick_open=m_last_close+m_size;
               const double brick_close=m_last_close+2.0*m_size;
               AddBrick(out,brick_open,brick_close,+1,time_msc);
               m_last_close=brick_close;
               m_last_dir=+1;
               added++;
               changed=true;
              }
           }
        }

      return added;
     }
  };

CRenkoBuilder g_builder;
SRenkoBrick   g_bricks[];
CCanvas       g_canvas;

string g_canvas_name="";
bool   g_canvas_ready=false;
bool   g_history_ready=false;
int    g_history_attempts=0;
ulong  g_last_tick_msc=0;
double g_last_price=0.0;

void TrimToMaximum(void)
  {
   const int total=ArraySize(g_bricks);
   if(total<=GDS_MAX_STORED_BRICKS)
      return;

   const int remove_count=total-GDS_MAX_STORED_BRICKS;
   for(int i=0;i<GDS_MAX_STORED_BRICKS;i++)
      g_bricks[i]=g_bricks[i+remove_count];
   ArrayResize(g_bricks,GDS_MAX_STORED_BRICKS);
  }

void AppendBricks(SRenkoBrick &added[])
  {
   const int n=ArraySize(added);
   if(n<=0)
      return;

   const int old=ArraySize(g_bricks);
   ArrayResize(g_bricks,old+n);
   for(int i=0;i<n;i++)
      g_bricks[old+i]=added[i];
   TrimToMaximum();
  }

bool ProcessPrice(const double price,const long time_msc)
  {
   SRenkoBrick added[];
   if(g_builder.PushPrice(price,time_msc,added)<=0)
      return false;
   AppendBricks(added);
   return true;
  }

void DestroyCanvas(void)
  {
   if(g_canvas_ready)
      g_canvas.Destroy();
   g_canvas_ready=false;
  }

bool EnsureCanvas(void)
  {
   if(g_canvas_ready)
      return true;

   ObjectDelete(0,g_canvas_name);
   if(!g_canvas.CreateBitmapLabel(0,0,g_canvas_name,GDS_PANEL_X,GDS_PANEL_Y,
                                  GDS_PANEL_WIDTH,GDS_PANEL_HEIGHT,COLOR_FORMAT_XRGB_NOALPHA))
     {
      Print("GDS Renko Brick Statistics: could not create canvas. Error ",GetLastError());
      return false;
     }

   g_canvas_ready=true;
   ObjectSetInteger(0,g_canvas_name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_XDISTANCE,GDS_PANEL_X);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_YDISTANCE,GDS_PANEL_Y);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_BACK,false);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_HIDDEN,true);
   g_canvas.FontSet("Consolas",12);
   return true;
  }

void DrawTextPair(const int y,const string label,const string value,const color value_color=clrWhite)
  {
   g_canvas.TextOut(18,y,label,ColorToARGB(GDS_MUTED,255));
   g_canvas.TextOut(252,y,value,ColorToARGB(value_color,255));
  }

void RenderPanel(void)
  {
   if(!EnsureCanvas())
      return;

   g_canvas.Erase(ColorToARGB(GDS_BG,255));
   g_canvas.Rectangle(0,0,GDS_PANEL_WIDTH-1,GDS_PANEL_HEIGHT-1,ColorToARGB(GDS_FRAME,255));
   g_canvas.TextOut(18,12,"GDS RENKO BRICK STATISTICS",ColorToARGB(GDS_ACCENT,255));

   const int total=ArraySize(g_bricks);
   if(!g_history_ready || total<=0)
     {
      g_canvas.TextOut(18,44,(g_history_ready ? "Waiting for completed Renko bricks..." :
                                              "Loading BID tick history..."),ColorToARGB(GDS_MUTED,255));
      g_canvas.Update(true);
      return;
     }

   int n=InpLookbackBricks;
   if(n>total) n=total;
   if(n<1) n=1;
   const int first=total-n;

   int up=0;
   int down=0;
   int reversals=0;
   int runs=0;
   int max_run=0;
   int current_run=1;
   int run_len=0;
   int prev_dir=0;

   for(int i=first;i<total;i++)
     {
      const int dir=g_bricks[i].direction;
      if(dir>0) up++; else if(dir<0) down++;

      if(i==first || dir!=prev_dir)
        {
         if(i>first)
            reversals++;
         runs++;
         run_len=1;
        }
      else
         run_len++;

      if(run_len>max_run)
         max_run=run_len;
      if(i==total-1)
         current_run=run_len;
      prev_dir=dir;
     }

   const double up_pct=(n>0 ? 100.0*up/n : 0.0);
   const double down_pct=(n>0 ? 100.0*down/n : 0.0);
   const double balance=(n>0 ? 100.0*(up-down)/n : 0.0);
   const double reversal_rate=(n>1 ? 100.0*reversals/(n-1) : 0.0);
   const double avg_run=(runs>0 ? (double)n/runs : 0.0);

   double span_hours=0.0;
   double bricks_per_hour=0.0;
   double avg_minutes=0.0;
   if(n>1)
     {
      const long dt=g_bricks[total-1].time_msc-g_bricks[first].time_msc;
      if(dt>0)
        {
         span_hours=(double)dt/3600000.0;
         bricks_per_hour=(double)(n-1)/span_hours;
         avg_minutes=60.0/bricks_per_hour;
        }
     }

   const string dir_text=(g_bricks[total-1].direction>0 ? "UP" : "DOWN");
   const color dir_color=(g_bricks[total-1].direction>0 ? GDS_UP : GDS_DOWN);

   g_canvas.TextOut(18,38,"Brick: "+DoubleToString(InpBrickSize,_Digits)+
                          "   Sample: "+IntegerToString(n)+" / "+IntegerToString(total),
                    ColorToARGB(GDS_TEXT,255));
   g_canvas.Line(16,62,GDS_PANEL_WIDTH-16,62,ColorToARGB(GDS_FRAME,255));

   DrawTextPair(72,"Up bricks",IntegerToString(up)+"  ("+DoubleToString(up_pct,1)+"%)",GDS_UP);
   DrawTextPair(94,"Down bricks",IntegerToString(down)+"  ("+DoubleToString(down_pct,1)+"%)",GDS_DOWN);
   DrawTextPair(116,"Direction balance",DoubleToString(balance,1)+"%",(balance>=0.0 ? GDS_UP : GDS_DOWN));
   DrawTextPair(138,"Reversal rate",DoubleToString(reversal_rate,1)+"%");
   DrawTextPair(160,"Average run length",DoubleToString(avg_run,2)+" bricks");
   DrawTextPair(182,"Maximum run",IntegerToString(max_run)+" bricks");
   DrawTextPair(204,"Current run",dir_text+"  "+IntegerToString(current_run)+" bricks",dir_color);
   DrawTextPair(226,"Formation speed",(bricks_per_hour>0.0 ? DoubleToString(bricks_per_hour,2)+" bricks/hour" : "n/a"));
   DrawTextPair(248,"Average brick time",(avg_minutes>0.0 ? DoubleToString(avg_minutes,2)+" min" : "n/a"));

   // Compact direction bar at the bottom.
   const int bar_x1=18;
   const int bar_x2=GDS_PANEL_WIDTH-18;
   const int bar_y1=274;
   const int bar_y2=282;
   g_canvas.Rectangle(bar_x1,bar_y1,bar_x2,bar_y2,ColorToARGB(GDS_FRAME,255));
   if(n>0)
     {
      const int inner_w=(bar_x2-bar_x1-2);
      const int split=bar_x1+1+(int)MathRound(inner_w*up_pct/100.0);
      if(split>bar_x1+1)
         g_canvas.FillRectangle(bar_x1+1,bar_y1+1,MathMin(split,bar_x2-1),bar_y2-1,ColorToARGB(GDS_UP,255));
      if(split<bar_x2-1)
         g_canvas.FillRectangle(MathMax(split+1,bar_x1+1),bar_y1+1,bar_x2-1,bar_y2-1,ColorToARGB(GDS_DOWN,255));
     }

   g_canvas.Update(true);
  }

bool LoadTickHistory(void)
  {
   g_history_attempts++;
   MqlTick ticks[];
   ResetLastError();
   const int count=CopyTicks(_Symbol,ticks,COPY_TICKS_ALL,0,GDS_HISTORY_TICKS);
   if(count<=0)
     {
      g_history_ready=false;
      RenderPanel();
      if(g_history_attempts==1 || (g_history_attempts%10)==0)
         Print("GDS Renko Brick Statistics: waiting for tick history. Error ",GetLastError());
      return false;
     }

   ArrayResize(g_bricks,0);
   g_builder.Init(InpBrickSize);
   g_last_tick_msc=0;
   g_last_price=0.0;

   for(int i=0;i<count;i++)
     {
      const double price=(ticks[i].bid>0.0 ? ticks[i].bid : ticks[i].last);
      if(price>0.0)
         ProcessPrice(price,(long)ticks[i].time_msc);
     }

   g_last_tick_msc=ticks[count-1].time_msc;
   g_last_price=(ticks[count-1].bid>0.0 ? ticks[count-1].bid : ticks[count-1].last);
   g_history_ready=true;
   TrimToMaximum();
   RenderPanel();
   return true;
  }

void ProcessLatestTick(void)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   const double price=(tick.bid>0.0 ? tick.bid : tick.last);
   if(price<=0.0)
      return;
   if(tick.time_msc==g_last_tick_msc && price==g_last_price)
      return;

   const bool new_brick=ProcessPrice(price,(long)tick.time_msc);
   g_last_tick_msc=tick.time_msc;
   g_last_price=price;
   if(new_brick)
      RenderPanel();
  }

int OnInit(void)
  {
   if(InpBrickSize<=0.0)
     {
      Print("GDS Renko Brick Statistics: Brick Size must be greater than zero.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLookbackBricks<10 || InpLookbackBricks>GDS_MAX_STORED_BRICKS)
     {
      Print("GDS Renko Brick Statistics: Lookback must be between 10 and ",GDS_MAX_STORED_BRICKS," bricks.");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_canvas_name="GDS_RBS_CANVAS_"+IntegerToString((int)ChartID());
   g_canvas_ready=false;
   g_history_ready=false;
   g_history_attempts=0;
   g_last_tick_msc=0;
   g_last_price=0.0;
   ArrayResize(g_bricks,0);
   g_builder.Init(InpBrickSize);

   IndicatorSetString(INDICATOR_SHORTNAME,"GDS Renko Brick Statistics");
   EnsureCanvas();
   RenderPanel();
   LoadTickHistory();
   ProcessLatestTick();
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   DestroyCanvas();
   ObjectDelete(0,g_canvas_name);
   ChartRedraw(0);
  }

void OnTimer(void)
  {
   if(!g_history_ready)
     {
      LoadTickHistory();
      if(!g_history_ready)
         return;
     }
   ProcessLatestTick();
  }

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(id==CHARTEVENT_CHART_CHANGE)
      RenderPanel();
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
   if(g_history_ready)
      ProcessLatestTick();
   return rates_total;
  }
//+------------------------------------------------------------------+
