//+------------------------------------------------------------------+
//|                                      GDS_Renko_Canvas_Donchian_v0.10.mq5 |
//|                     Golden Delta - CodeBase Edition              |
//|                         https://goldendeltaea.com/                |
//+------------------------------------------------------------------+
#property copyright "Golden Delta"
#property link      "https://goldendeltaea.com/"
#property version   "0.10"
#property description "Classic fixed-size Renko rendered with one MQL5 Canvas layer plus a Donchian Channel."
#property description "The channel uses only previous completed internal Renko bricks; the current brick is excluded."
#property description "No DLLs, custom symbols, offline charts or external indicators are required."
#property indicator_chart_window
#property indicator_plots 0

#include <Canvas\Canvas.mqh>

//--- Intentionally compact CodeBase inputs.
input double InpBrickSize       = 1.00; // Brick size in price units
input int    InpDonchianPeriod  = 20;   // Channel period in previous completed Renko bricks

//--- Internal presentation/history settings.
#define GDS_HISTORY_TICKS          300000
#define GDS_MAX_STORED_BRICKS        2000
#define GDS_TARGET_BRICK_PX             12
#define GDS_MIN_BRICK_PX                 4
#define GDS_LEFT_INSET_PX                 8
#define GDS_RIGHT_INSET_PX                8
#define GDS_PRICE_SCALE_MARGIN_PX         64
#define GDS_PRICE_PADDING_BRICKS         1.5

const color GDS_UP_COLOR     = clrDeepSkyBlue;
const color GDS_DOWN_COLOR   = clrTomato;
const color GDS_BORDER_COLOR = clrBlack;
const color GDS_BG_COLOR     = clrBlack;
const color GDS_TEXT_COLOR   = clrSilver;
const color GDS_DC_OUTER_COLOR = clrDeepSkyBlue;
const color GDS_DC_MIDDLE_COLOR= clrGold;

//+------------------------------------------------------------------+
//| One completed Renko brick.                                      |
//+------------------------------------------------------------------+
struct SRenkoBrick
  {
   double open;
   double close;
   int    direction; // +1 up, -1 down
   long   serial;
  };

//+------------------------------------------------------------------+
//| Minimal classic fixed-size Renko builder.                        |
//| Continuation: one brick. Reversal: two bricks from last close.   |
//+------------------------------------------------------------------+
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
                 const int direction)
     {
      const int n=ArraySize(out);
      ArrayResize(out,n+1);
      out[n].open=NormalizeDouble(open_price,_Digits);
      out[n].close=NormalizeDouble(close_price,_Digits);
      out[n].direction=direction;
      out[n].serial=0;
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

   int PushPrice(const double price,SRenkoBrick &out[])
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

      // First confirmed direction starts one brick from the anchor.
      if(m_last_dir==0)
        {
         while(price>=m_anchor+m_size)
           {
            const double brick_open=m_anchor;
            m_anchor+=m_size;
            m_last_close=m_anchor;
            m_last_dir=+1;
            AddBrick(out,brick_open,m_last_close,+1);
            added++;
           }

         while(price<=m_anchor-m_size)
           {
            const double brick_open=m_anchor;
            m_anchor-=m_size;
            m_last_close=m_anchor;
            m_last_dir=-1;
            AddBrick(out,brick_open,m_last_close,-1);
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
               AddBrick(out,brick_open,brick_close,+1);
               m_last_close=brick_close;
               added++;
               changed=true;
              }
            else if(price<=m_last_close-2.0*m_size)
              {
               const double brick_open=m_last_close-m_size;
               const double brick_close=m_last_close-2.0*m_size;
               AddBrick(out,brick_open,brick_close,-1);
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
               AddBrick(out,brick_open,brick_close,-1);
               m_last_close=brick_close;
               added++;
               changed=true;
              }
            else if(price>=m_last_close+2.0*m_size)
              {
               const double brick_open=m_last_close+m_size;
               const double brick_close=m_last_close+2.0*m_size;
               AddBrick(out,brick_open,brick_close,+1);
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
long   g_next_serial=1;
ulong  g_last_tick_msc=0;
double g_last_price=0.0;
int    g_canvas_width=0;
int    g_canvas_height=0;

//--- Original chart appearance. Restored on indicator removal.
bool   g_chart_style_saved=false;
long   g_saved_chart_up=0;
long   g_saved_chart_down=0;
long   g_saved_candle_bull=0;
long   g_saved_candle_bear=0;
long   g_saved_chart_line=0;
long   g_saved_chart_foreground=0;
long   g_saved_show_grid=0;
long   g_saved_show_date_scale=0;
long   g_saved_show_price_scale=0;
long   g_saved_show_bid_line=0;
long   g_saved_show_ask_line=0;
long   g_saved_show_object_descr=0;
long   g_saved_scale_fix=0;
double g_saved_fixed_min=0.0;
double g_saved_fixed_max=0.0;

//+------------------------------------------------------------------+
bool SaveChartStyle(void)
  {
   bool ok=true;
   if(!ChartGetInteger(0,CHART_COLOR_CHART_UP,0,g_saved_chart_up)) ok=false;
   if(!ChartGetInteger(0,CHART_COLOR_CHART_DOWN,0,g_saved_chart_down)) ok=false;
   if(!ChartGetInteger(0,CHART_COLOR_CANDLE_BULL,0,g_saved_candle_bull)) ok=false;
   if(!ChartGetInteger(0,CHART_COLOR_CANDLE_BEAR,0,g_saved_candle_bear)) ok=false;
   if(!ChartGetInteger(0,CHART_COLOR_CHART_LINE,0,g_saved_chart_line)) ok=false;
   if(!ChartGetInteger(0,CHART_FOREGROUND,0,g_saved_chart_foreground)) ok=false;
   if(!ChartGetInteger(0,CHART_SHOW_GRID,0,g_saved_show_grid)) ok=false;
   if(!ChartGetInteger(0,CHART_SHOW_DATE_SCALE,0,g_saved_show_date_scale)) ok=false;
   if(!ChartGetInteger(0,CHART_SHOW_PRICE_SCALE,0,g_saved_show_price_scale)) ok=false;
   if(!ChartGetInteger(0,CHART_SHOW_BID_LINE,0,g_saved_show_bid_line)) ok=false;
   if(!ChartGetInteger(0,CHART_SHOW_ASK_LINE,0,g_saved_show_ask_line)) ok=false;
   if(!ChartGetInteger(0,CHART_SHOW_OBJECT_DESCR,0,g_saved_show_object_descr)) ok=false;
   if(!ChartGetInteger(0,CHART_SCALEFIX,0,g_saved_scale_fix)) ok=false;
   if(!ChartGetDouble(0,CHART_FIXED_MIN,0,g_saved_fixed_min)) ok=false;
   if(!ChartGetDouble(0,CHART_FIXED_MAX,0,g_saved_fixed_max)) ok=false;
   g_chart_style_saved=ok;
   return ok;
  }

//+------------------------------------------------------------------+
void PrepareRenkoChart(void)
  {
   long bg=0;
   if(!ChartGetInteger(0,CHART_COLOR_BACKGROUND,0,bg))
      bg=(long)GDS_BG_COLOR;

   // Hide the host price drawing: the normal chart is only a container.
   ChartSetInteger(0,CHART_COLOR_CHART_UP,bg);
   ChartSetInteger(0,CHART_COLOR_CHART_DOWN,bg);
   ChartSetInteger(0,CHART_COLOR_CANDLE_BULL,bg);
   ChartSetInteger(0,CHART_COLOR_CANDLE_BEAR,bg);
   ChartSetInteger(0,CHART_COLOR_CHART_LINE,bg);
   ChartSetInteger(0,CHART_FOREGROUND,false);
   ChartSetInteger(0,CHART_SHOW_GRID,false);
   ChartSetInteger(0,CHART_SHOW_DATE_SCALE,false);
   ChartSetInteger(0,CHART_SHOW_PRICE_SCALE,true);
   ChartSetInteger(0,CHART_SHOW_BID_LINE,false);
   ChartSetInteger(0,CHART_SHOW_ASK_LINE,false);
   // Keep labels/descriptions from unrelated chart objects out of the visual layer.
   ChartSetInteger(0,CHART_SHOW_OBJECT_DESCR,false);
  }

//+------------------------------------------------------------------+
void RestoreChartStyle(void)
  {
   if(!g_chart_style_saved)
      return;

   ChartSetInteger(0,CHART_COLOR_CHART_UP,g_saved_chart_up);
   ChartSetInteger(0,CHART_COLOR_CHART_DOWN,g_saved_chart_down);
   ChartSetInteger(0,CHART_COLOR_CANDLE_BULL,g_saved_candle_bull);
   ChartSetInteger(0,CHART_COLOR_CANDLE_BEAR,g_saved_candle_bear);
   ChartSetInteger(0,CHART_COLOR_CHART_LINE,g_saved_chart_line);
   ChartSetInteger(0,CHART_FOREGROUND,g_saved_chart_foreground);
   ChartSetInteger(0,CHART_SHOW_GRID,g_saved_show_grid);
   ChartSetInteger(0,CHART_SHOW_DATE_SCALE,g_saved_show_date_scale);
   ChartSetInteger(0,CHART_SHOW_PRICE_SCALE,g_saved_show_price_scale);
   ChartSetInteger(0,CHART_SHOW_BID_LINE,g_saved_show_bid_line);
   ChartSetInteger(0,CHART_SHOW_ASK_LINE,g_saved_show_ask_line);
   ChartSetInteger(0,CHART_SHOW_OBJECT_DESCR,g_saved_show_object_descr);
   ChartSetDouble(0,CHART_FIXED_MIN,g_saved_fixed_min);
   ChartSetDouble(0,CHART_FIXED_MAX,g_saved_fixed_max);
   ChartSetInteger(0,CHART_SCALEFIX,g_saved_scale_fix);
  }

//+------------------------------------------------------------------+
void DestroyCanvas(void)
  {
   if(g_canvas_ready)
      g_canvas.Destroy();
   g_canvas_ready=false;
   g_canvas_width=0;
   g_canvas_height=0;
  }

//+------------------------------------------------------------------+
bool EnsureCanvas(void)
  {
   const int chart_width=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   const int chart_height=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   if(chart_width<=GDS_PRICE_SCALE_MARGIN_PX+40 || chart_height<=80)
      return false;

   const int wanted_width=chart_width-GDS_PRICE_SCALE_MARGIN_PX;
   const int wanted_height=chart_height;

   if(g_canvas_ready && wanted_width==g_canvas_width && wanted_height==g_canvas_height)
      return true;

   DestroyCanvas();
   ObjectDelete(0,g_canvas_name);

   if(!g_canvas.CreateBitmapLabel(0,0,g_canvas_name,0,0,wanted_width,wanted_height,COLOR_FORMAT_XRGB_NOALPHA))
     {
      Print("GDS Renko Canvas + Donchian: could not create canvas. Error ",GetLastError());
      return false;
     }

   g_canvas_ready=true;
   g_canvas_width=wanted_width;
   g_canvas_height=wanted_height;

   ObjectSetInteger(0,g_canvas_name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_XDISTANCE,0);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_YDISTANCE,0);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_BACK,false);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_HIDDEN,true);

   g_canvas.FontSet("Consolas",13);
   return true;
  }

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
void AppendBricks(SRenkoBrick &added[])
  {
   const int n=ArraySize(added);
   if(n<=0)
      return;

   const int old=ArraySize(g_bricks);
   ArrayResize(g_bricks,old+n);
   for(int i=0;i<n;i++)
     {
      added[i].serial=g_next_serial++;
      g_bricks[old+i]=added[i];
     }
   TrimToMaximum();
  }

//+------------------------------------------------------------------+
bool ProcessPrice(const double price)
  {
   SRenkoBrick added[];
   if(g_builder.PushPrice(price,added)<=0)
      return false;
   AppendBricks(added);
   return true;
  }

//+------------------------------------------------------------------+
bool ComputeDonchianAt(const int index,double &middle,double &upper,double &lower)
  {
   middle=0.0;
   upper=0.0;
   lower=0.0;

   // Causal convention: the newly completed brick at 'index' is NOT part
   // of its own channel. Use the previous N completed bricks only.
   if(InpDonchianPeriod<2 || index<InpDonchianPeriod || index>=ArraySize(g_bricks))
      return false;

   upper=-DBL_MAX;
   lower= DBL_MAX;

   for(int k=index-InpDonchianPeriod;k<index;k++)
     {
      const SRenkoBrick brick=g_bricks[k];
      const double hi=MathMax(brick.open,brick.close);
      const double lo=MathMin(brick.open,brick.close);
      upper=MathMax(upper,hi);
      lower=MathMin(lower,lo);
     }

   if(upper<=-DBL_MAX/2.0 || lower>=DBL_MAX/2.0 || upper<lower)
      return false;

   middle=0.5*(upper+lower);
   return true;
  }

//+------------------------------------------------------------------+
int ChooseVisibleCount(const int brick_px,double &min_price,double &max_price)
  {
   min_price=0.0;
   max_price=0.0;

   const int total=ArraySize(g_bricks);
   if(total<=0 || brick_px<=0 || g_canvas_width<=0 || g_canvas_height<=0)
      return 0;

   int horizontal_capacity=(g_canvas_width-GDS_LEFT_INSET_PX-GDS_RIGHT_INSET_PX)/brick_px;
   if(horizontal_capacity<1) horizontal_capacity=1;
   const int max_count=(total<horizontal_capacity ? total : horizontal_capacity);
   const double available_price_span=((double)g_canvas_height/brick_px)*InpBrickSize;
   const double allowed_data_span=available_price_span-2.0*GDS_PRICE_PADDING_BRICKS*InpBrickSize;
   if(allowed_data_span<InpBrickSize)
      return 0;

   double lo=DBL_MAX;
   double hi=-DBL_MAX;
   int best=0;

   for(int n=1;n<=max_count;n++)
     {
      const int i=total-n;
      const SRenkoBrick brick=g_bricks[i];
      lo=MathMin(lo,MathMin(brick.open,brick.close));
      hi=MathMax(hi,MathMax(brick.open,brick.close));

      // Keep the visible Donchian channel inside the same fixed price scale.
      double dc_mid=0.0,dc_upper=0.0,dc_lower=0.0;
      if(ComputeDonchianAt(i,dc_mid,dc_upper,dc_lower))
        {
         lo=MathMin(lo,dc_lower);
         hi=MathMax(hi,dc_upper);
        }

      if((hi-lo)<=allowed_data_span+0.1*_Point)
        {
         best=n;
         min_price=lo;
         max_price=hi;
        }
      else
         break; // Adding older bricks cannot reduce the price range.
     }

   return best;
  }

//+------------------------------------------------------------------+
int PriceToCanvasY(const double price,const double fixed_min,const double fixed_max)
  {
   if(fixed_max<=fixed_min || g_canvas_height<=1)
      return 0;

   const double ratio=(fixed_max-price)/(fixed_max-fixed_min);
   int y=(int)MathRound(ratio*(g_canvas_height-1));
   if(y<0) y=0;
   if(y>=g_canvas_height) y=g_canvas_height-1;
   return y;
  }

//+------------------------------------------------------------------+
//| Draw a visually stronger Donchian boundary.                  |
//+------------------------------------------------------------------+
void DrawOuterBandSegment(const int x1,const int y1,const int x2,const int y2)
  {
   const uint c=ColorToARGB(GDS_DC_OUTER_COLOR,255);
   const int ya1=MathMax(0,MathMin(g_canvas_height-1,y1));
   const int ya2=MathMax(0,MathMin(g_canvas_height-1,y2));
   const int yb1=MathMax(0,MathMin(g_canvas_height-1,y1-1));
   const int yb2=MathMax(0,MathMin(g_canvas_height-1,y2-1));
   const int yc1=MathMax(0,MathMin(g_canvas_height-1,y1+1));
   const int yc2=MathMax(0,MathMin(g_canvas_height-1,y2+1));
   g_canvas.Line(x1,ya1,x2,ya2,c);
   // One pixel on either side keeps the band readable in thumbnails.
   g_canvas.Line(x1,yb1,x2,yb2,c);
   g_canvas.Line(x1,yc1,x2,yc2,c);
  }

//+------------------------------------------------------------------+
void DrawLoading(void)
  {
   if(!EnsureCanvas())
      return;

   g_canvas.Erase(ColorToARGB(GDS_BG_COLOR,255));
   g_canvas.TextOut(12,12,"RENKO CANVAS + DONCHIAN  |  Loading tick history...",ColorToARGB(GDS_TEXT_COLOR,255));
   g_canvas.Update(true);
  }

//+------------------------------------------------------------------+
void RenderCanvas(void)
  {
   if(!EnsureCanvas())
      return;

   g_canvas.Erase(ColorToARGB(GDS_BG_COLOR,255));

   const int total=ArraySize(g_bricks);
   if(!g_history_ready || total<=0)
     {
      const string status=(g_history_ready ? "RENKO CANVAS + DONCHIAN  |  Waiting for first brick..." :
                                             "RENKO CANVAS + DONCHIAN  |  Loading tick history...");
      g_canvas.TextOut(12,12,status,ColorToARGB(GDS_TEXT_COLOR,255));
      g_canvas.Update(true);
      return;
     }

   int brick_px=GDS_TARGET_BRICK_PX;
   double min_price=0.0;
   double max_price=0.0;
   int visible=ChooseVisibleCount(brick_px,min_price,max_price);

   // Very small chart windows may need smaller square bricks.
   while(visible<=0 && brick_px>GDS_MIN_BRICK_PX)
     {
      brick_px--;
      visible=ChooseVisibleCount(brick_px,min_price,max_price);
     }

   if(visible<=0)
     {
      g_canvas.TextOut(12,12,"RENKO CANVAS + DONCHIAN  |  Chart window is too small",ColorToARGB(GDS_TEXT_COLOR,255));
      g_canvas.Update(true);
      return;
     }

   // Fix the chart scale so one price brick equals one square canvas brick.
   // Center the visible Renko path vertically. ChooseVisibleCount() already
   // guarantees enough room for the configured top/bottom padding.
   const double full_price_span=((double)g_canvas_height/brick_px)*InpBrickSize;
   const double data_mid=0.5*(min_price+max_price);
   const double fixed_min=data_mid-0.5*full_price_span;
   const double fixed_max=data_mid+0.5*full_price_span;

   ChartSetInteger(0,CHART_SCALEFIX,true);
   ChartSetDouble(0,CHART_FIXED_MIN,fixed_min);
   ChartSetDouble(0,CHART_FIXED_MAX,fixed_max);

   const int first=total-visible;
   const int right_edge=g_canvas_width-GDS_RIGHT_INSET_PX;
   const int start_x=right_edge-visible*brick_px;

   for(int i=first;i<total;i++)
     {
      const SRenkoBrick brick=g_bricks[i];
      const int slot=i-first;
      const int x1=start_x+slot*brick_px;
      const int x2=x1+brick_px-1;
      const double top_price=MathMax(brick.open,brick.close);
      const double bottom_price=MathMin(brick.open,brick.close);
      int y1=PriceToCanvasY(top_price,fixed_min,fixed_max);
      int y2=PriceToCanvasY(bottom_price,fixed_min,fixed_max);
      if(y2<y1)
        {
         const int temp=y1;
         y1=y2;
         y2=temp;
        }

      // Force the final visual height to the same size as the width.
      // Rounding in price-to-pixel conversion can otherwise differ by one pixel.
      const int middle=(y1+y2)/2;
      y1=middle-brick_px/2;
      y2=y1+brick_px-1;

      if(y2<0 || y1>=g_canvas_height)
         continue;
      if(y1<0) y1=0;
      if(y2>=g_canvas_height) y2=g_canvas_height-1;

      const color fill=(brick.direction>0 ? GDS_UP_COLOR : GDS_DOWN_COLOR);
      g_canvas.FillRectangle(x1,y1,x2,y2,ColorToARGB(fill,255));
      g_canvas.Rectangle(x1,y1,x2,y2,ColorToARGB(GDS_BORDER_COLOR,255));
     }

   // Donchian overlay. Each point uses the PREVIOUS N completed Renko
   // bricks. The current completed brick is deliberately excluded.
   bool have_prev=false;
   int prev_x=0;
   int prev_y_upper=0;
   int prev_y_mid=0;
   int prev_y_lower=0;

   for(int i=first;i<total;i++)
     {
      double dc_mid=0.0,dc_upper=0.0,dc_lower=0.0;
      if(!ComputeDonchianAt(i,dc_mid,dc_upper,dc_lower))
        {
         have_prev=false;
         continue;
        }

      const int slot=i-first;
      const int x=start_x+slot*brick_px+brick_px/2;
      const int y_upper=PriceToCanvasY(dc_upper,fixed_min,fixed_max);
      const int y_mid=PriceToCanvasY(dc_mid,fixed_min,fixed_max);
      const int y_lower=PriceToCanvasY(dc_lower,fixed_min,fixed_max);

      if(have_prev)
        {
         // Donchian is naturally a step channel: keep the previous level
         // horizontal until the new completed Renko brick updates it.
         DrawOuterBandSegment(prev_x,prev_y_upper,x,prev_y_upper);
         if(y_upper!=prev_y_upper)
            DrawOuterBandSegment(x,prev_y_upper,x,y_upper);

         DrawOuterBandSegment(prev_x,prev_y_lower,x,prev_y_lower);
         if(y_lower!=prev_y_lower)
            DrawOuterBandSegment(x,prev_y_lower,x,y_lower);

         const uint mid_color=ColorToARGB(GDS_DC_MIDDLE_COLOR,255);
         g_canvas.Line(prev_x,prev_y_mid,x,prev_y_mid,mid_color);
         if(y_mid!=prev_y_mid)
            g_canvas.Line(x,prev_y_mid,x,y_mid,mid_color);
        }

      prev_x=x;
      prev_y_upper=y_upper;
      prev_y_mid=y_mid;
      prev_y_lower=y_lower;
      have_prev=true;
     }

   const string header="RENKO CANVAS + DONCHIAN  |  Brick: "+DoubleToString(InpBrickSize,_Digits)+
                       "  |  Channel: "+IntegerToString(InpDonchianPeriod);
   g_canvas.TextOut(12,12,header,ColorToARGB(GDS_TEXT_COLOR,255));
   g_canvas.Update(true);
  }

//+------------------------------------------------------------------+
bool LoadTickHistory(void)
  {
   g_history_attempts++;

   MqlTick ticks[];
   ResetLastError();
   const int count=CopyTicks(_Symbol,ticks,COPY_TICKS_ALL,0,GDS_HISTORY_TICKS);
   if(count<=0)
     {
      g_history_ready=false;
      DrawLoading();
      if(g_history_attempts==1 || (g_history_attempts%10)==0)
         Print("GDS Renko Canvas + Donchian: waiting for tick history. Error ",GetLastError());
      return false;
     }

   ArrayResize(g_bricks,0);
   g_builder.Init(InpBrickSize);
   g_next_serial=1;
   g_last_tick_msc=0;
   g_last_price=0.0;

   for(int i=0;i<count;i++)
     {
      const double price=(ticks[i].bid>0.0 ? ticks[i].bid : ticks[i].last);
      if(price>0.0)
         ProcessPrice(price);
     }

   g_last_tick_msc=ticks[count-1].time_msc;
   g_last_price=(ticks[count-1].bid>0.0 ? ticks[count-1].bid : ticks[count-1].last);
   g_history_ready=true;
   TrimToMaximum();
   RenderCanvas();
   return true;
  }

//+------------------------------------------------------------------+
void ProcessLatestTick(void)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   const double price=(tick.bid>0.0 ? tick.bid : tick.last);
   if(price<=0.0)
      return;

   // OnCalculate and OnTimer may see the same tick.
   if(tick.time_msc==g_last_tick_msc && price==g_last_price)
      return;

   const bool new_brick=ProcessPrice(price);
   g_last_tick_msc=tick.time_msc;
   g_last_price=price;

   if(new_brick)
      RenderCanvas();
  }

//+------------------------------------------------------------------+
int OnInit(void)
  {
   if(InpBrickSize<=0.0)
     {
      Print("GDS Renko Canvas + Donchian: Brick Size must be greater than zero.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpDonchianPeriod<2)
     {
      Print("GDS Renko Canvas + Donchian: Donchian period must be at least 2.");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_canvas_name="GDS_RCD_CANVAS_"+IntegerToString((int)ChartID());

   if(SaveChartStyle())
      PrepareRenkoChart();
   else
      Print("GDS Renko Canvas + Donchian: could not save all chart properties.");

   g_canvas_ready=false;
   g_history_ready=false;
   g_history_attempts=0;
   g_next_serial=1;
   g_last_tick_msc=0;
   g_last_price=0.0;
   ArrayResize(g_bricks,0);
   g_builder.Init(InpBrickSize);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      "GDS Renko Canvas + Donchian ("+DoubleToString(InpBrickSize,_Digits)+")");

   EnsureCanvas();
   DrawLoading();
   LoadTickHistory();
   ProcessLatestTick();

   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   DestroyCanvas();
   ObjectDelete(0,g_canvas_name);
   RestoreChartStyle();
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
void OnTimer(void)
  {
   if(!g_history_ready)
     {
      LoadTickHistory();
      if(!g_history_ready)
         return;
     }

   ProcessLatestTick();

   const int chart_width=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   const int chart_height=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   const int wanted_width=chart_width-GDS_PRICE_SCALE_MARGIN_PX;
   if(!g_canvas_ready || wanted_width!=g_canvas_width || chart_height!=g_canvas_height)
      RenderCanvas();
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(id==CHARTEVENT_CHART_CHANGE)
      RenderCanvas();
  }

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
   if(g_history_ready)
      ProcessLatestTick();
   return rates_total;
  }
//+------------------------------------------------------------------+
