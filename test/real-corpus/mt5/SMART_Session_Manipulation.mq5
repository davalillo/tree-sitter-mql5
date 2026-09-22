#property copyright "Copyright 2026, IronHawk Capital LLC"
#property version   "3.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0
#property description "Three-symbol ICT/SMC session-liquidity scanner using closed bars only."
#property description "Validates sweep, MSS, displacement, FVG and a later retest before projection."
#property description "The optional native economic calendar is informational and disabled by default."

// Session Manipulation & Algorithmic Reaction Tracker
// Public CodeBase edition by IronHawk Capital LLC
// Closed-bar, deterministic, multi-symbol and non-trading indicator.

enum SMART_PHASE
  {
   SMART_PHASE_NONE=0,
   SMART_PHASE_SWEEP,
   SMART_PHASE_WAIT_FVG,
   SMART_PHASE_RETEST
  };

input group "Symbols and engine"
input string          InpSymbol1                    = "EURUSD"; // Empty = chart symbol
input string          InpSymbol2                    = "GBPUSD";
input string          InpSymbol3                    = "USDJPY";
input ENUM_TIMEFRAMES InpAnalysisTimeframe          = PERIOD_M5;
input int             InpHistoryBars                = 20000;
input int             InpTimerSeconds               = 1;
input int             InpServerUTCOffsetMinutes     = 9999;     // 9999 = automatic current offset

input group "UTC sessions"
input int             InpAsiaStartHour              = 0;
input int             InpAsiaStartMinute            = 0;
input int             InpAsiaEndHour                = 7;
input int             InpAsiaEndMinute              = 0;
input int             InpLondonStartHour            = 7;
input int             InpLondonStartMinute          = 0;
input int             InpLondonRangeEndHour         = 12;
input int             InpLondonRangeEndMinute       = 0;
input int             InpLondonSweepEndHour         = 10;
input int             InpLondonSweepEndMinute       = 0;
input int             InpNewYorkStartHour           = 12;
input int             InpNewYorkStartMinute         = 0;
input int             InpNewYorkEndHour             = 16;
input int             InpNewYorkEndMinute           = 0;

input group "ICT / SMC state machine"
input int             InpATRPeriod                  = 14;
input int             InpVolumeLookback             = 20;
input int             InpSwingStrength              = 2;
input int             InpSwingLookback              = 30;
input int             InpMSSBars                    = 6;
input int             InpFVGFormationBars           = 2;
input int             InpRetestBars                 = 5;
input double          InpMinimumSweepATR            = 0.05;
input double          InpMinimumDisplacementATR     = 0.30;
input double          InpMinimumFVGATR              = 0.03;
input double          InpRetestToleranceATR         = 0.10;
input double          InpStopBufferATR              = 0.15;
input double          InpMinimumRiskATR             = 0.35;
input double          InpMaximumRiskATR             = 2.50;
input double          InpMinimumProjectionRR        = 1.50;
input double          InpTP1RiskMultiple            = 1.20;
input double          InpTP2RiskMultiple            = 2.00;
input int             InpSniperThreshold            = 85;
input int             InpViableThreshold            = 70;
input int             InpDashboardSetupAgeBars      = 18;

input group "Economic calendar (optional)"
input bool            InpUseEconomicCalendar        = false;
input int             InpMinimumNewsImportance      = 3;        // 1 low, 2 moderate, 3 high
input int             InpNewsMinutesBefore          = 30;
input int             InpNewsMinutesAfter           = 10;

input group "Display"
input bool            InpShowSessionBoxes           = true;
input bool            InpShowTradeProjections       = true;
input bool            InpShowWatchMarkers           = true;
input bool            InpShowDashboard              = true;
input int             InpMaximumDisplayedSetups     = 3;
input int             InpMaximumDisplayedWatches    = 8;
input int             InpProjectionBars             = 18;
input int             InpMinimumChartProjectionBars = 4;
input int             InpDashboardX                 = 18;
input int             InpDashboardY                 = 28;
input int             InpDashboardWidth             = 760;
input color           InpAsiaColor                  = C'65,75,115';
input color           InpLondonColor                = C'45,95,130';
input color           InpNewYorkColor               = C'135,95,35';
input color           InpBullishColor               = clrLimeGreen;
input color           InpBearishColor               = clrTomato;
input color           InpRewardZoneColor            = C'28,92,62';
input color           InpRiskZoneColor              = C'105,38,50';
input color           InpFVGColor                   = C'48,62,100';
input color           InpNeutralColor               = clrSilver;
input color           InpPanelColor                 = C'12,18,28';

input group "Alerts"
input bool            InpTerminalAlerts             = true;
input bool            InpPushAlerts                 = false;
input bool            InpEmailAlerts                = false;
input bool            InpAlertOnInitialization      = false;

#define SMART_SYMBOLS       3
#define SMART_MAX_DAYS      8
#define SMART_MAX_SETUPS    32
#define SMART_MAX_WATCHES   64

struct SMART_DAY
  {
   int               key;
   bool              asia_valid;
   double            asia_high;
   double            asia_low;
   datetime          asia_start;
   datetime          asia_end;
   bool              london_valid;
   double            london_high;
   double            london_low;
   datetime          london_start;
   datetime          london_end;
   bool              newyork_valid;
   double            newyork_high;
   double            newyork_low;
   datetime          newyork_start;
   datetime          newyork_end;
  };

struct SMART_CANDIDATE
  {
   bool              active;
   int               phase;
   int               sweep_side;
   int               direction;
   int               start_index;
   int               extreme_index;
   int               mss_index;
   int               fvg_index;
   int               day_key;
   datetime          sweep_time;
   datetime          extreme_time;
   datetime          mss_time;
   datetime          fvg_time;
   double            level;
   double            extreme;
   double            structure_level;
   double            fvg_low;
   double            fvg_high;
   double            range_low;
   double            range_high;
   double            atr_at_sweep;
   string            source_session;
   int               best_score;
  };

struct SMART_SETUP
  {
   string            id;
   int               sweep_side;
   int               direction;
   int               score;
   datetime          sweep_time;
   datetime          extreme_time;
   datetime          mss_time;
   datetime          fvg_time;
   datetime          confirmed_time;
   int               confirmed_index;
   int               day_key;
   double            sweep_extreme;
   double            structure_level;
   double            fvg_low;
   double            fvg_high;
   double            entry;
   double            stop;
   double            tp1;
   double            tp2;
   double            rr;
   string            source_session;
   string            components;
  };

struct SMART_WATCH
  {
   string            id;
   int               sweep_side;
   int               direction;
   int               score;
   int               day_key;
   datetime          sweep_time;
   datetime          extreme_time;
   double            sweep_extreme;
   string            source_session;
   string            reason;
  };

struct SMART_CONTEXT
  {
   string            requested_symbol;
   string            symbol;
   bool              available;
   bool              initialized;
   datetime          last_closed_bar;
   string            status;
   string            note;
   string            session_name;
   int               phase;
   int               score;
   int               direction;
   double            rr;
   string            last_alerted_id;
   int               day_count;
   SMART_DAY         days[SMART_MAX_DAYS];
   int               setup_count;
   SMART_SETUP       setups[SMART_MAX_SETUPS];
   int               testable_count;
   int               tp1_hit_count;
   int               tp2_hit_count;
   string            news_state;
   string            news_name;
   datetime          news_time;
   int               news_importance;
   string            news_detail;
   datetime          last_news_refresh;
   int               watch_count;
   SMART_WATCH       watches[SMART_MAX_WATCHES];
  };

SMART_CONTEXT g_contexts[SMART_SYMBOLS];
int           g_next_symbol=0;
string        g_object_prefix="SMART_";

//+------------------------------------------------------------------+
string UpperCopy(const string source)
  {
   string value=source;
   StringToUpper(value);
   return value;
  }

//+------------------------------------------------------------------+
string TrimCopy(const string source)
  {
   string value=source;
   StringTrimLeft(value);
   StringTrimRight(value);
   return value;
  }

//+------------------------------------------------------------------+
string ResolveSymbol(const string requested)
  {
   string base=TrimCopy(requested);
   if(base=="")
      return _Symbol;
   if(SymbolSelect(base,true))
      return base;

   string wanted=UpperCopy(base);
   string best="";
   int best_extra=1000000;
   int total=SymbolsTotal(false);
   for(int i=0;i<total;i++)
     {
      string candidate=SymbolName(i,false);
      string upper=UpperCopy(candidate);
      int position=StringFind(upper,wanted);
      if(position<0)
         continue;
      int extra=StringLen(candidate)-StringLen(base);
      if(extra<0)
         continue;
      if(position!=0 && position+StringLen(wanted)!=StringLen(upper))
         continue;
      if(extra<best_extra)
        {
         best=candidate;
         best_extra=extra;
        }
     }
   if(best!="")
      SymbolSelect(best,true);
   return best;
  }

//+------------------------------------------------------------------+
int CurrentServerUTCOffsetMinutes()
  {
   if(InpServerUTCOffsetMinutes!=9999)
      return InpServerUTCOffsetMinutes;
   datetime server_time=TimeTradeServer();
   datetime utc_time=TimeGMT();
   if(server_time<=0 || utc_time<=0)
      return 0;
   return (int)MathRound((double)(server_time-utc_time)/60.0);
  }

//+------------------------------------------------------------------+
datetime ToUTC(const datetime server_time)
  {
   return server_time-CurrentServerUTCOffsetMinutes()*60;
  }

//+------------------------------------------------------------------+
int MinuteOfDayUTC(const datetime server_time)
  {
   MqlDateTime parts;
   TimeToStruct(ToUTC(server_time),parts);
   return parts.hour*60+parts.min;
  }

//+------------------------------------------------------------------+
int DayKeyUTC(const datetime server_time)
  {
   MqlDateTime parts;
   TimeToStruct(ToUTC(server_time),parts);
   return parts.year*10000+parts.mon*100+parts.day;
  }

//+------------------------------------------------------------------+
bool InMinuteWindow(const int minute,const int start_minute,const int end_minute)
  {
   if(start_minute==end_minute)
      return false;
   if(start_minute<end_minute)
      return minute>=start_minute && minute<end_minute;
   return minute>=start_minute || minute<end_minute;
  }

//+------------------------------------------------------------------+
bool ValidClockInput(const int hour,const int minute)
  {
   return (hour>=0 && hour<=23 && minute>=0 && minute<=59);
  }

//+------------------------------------------------------------------+
bool ValidForwardWindow(const int start_hour,const int start_minute,
                        const int end_hour,const int end_minute)
  {
   if(!ValidClockInput(start_hour,start_minute) ||
      !ValidClockInput(end_hour,end_minute))
      return false;
   return start_hour*60+start_minute<end_hour*60+end_minute;
  }

//+------------------------------------------------------------------+
int ClampInt(const int value,const int minimum,const int maximum)
  {
   return MathMax(minimum,MathMin(maximum,value));
  }

//+------------------------------------------------------------------+
string DirectionText(const int direction)
  {
   if(direction>0) return "LONG";
   if(direction<0) return "SHORT";
   return "WAIT";
  }

//+------------------------------------------------------------------+
string ScoreState(const int score)
  {
   if(score>=InpSniperThreshold) return "SNIPER";
   if(score>=InpViableThreshold) return "VIABLE";
   return "RETAIL NOISE";
  }

//+------------------------------------------------------------------+
string AnalysisTimeframeText()
  {
   string value=EnumToString(InpAnalysisTimeframe);
   StringReplace(value,"PERIOD_","");
   return value;
  }

//+------------------------------------------------------------------+
string PriceText(const string symbol,const double value)
  {
   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   return DoubleToString(value,digits);
  }

//+------------------------------------------------------------------+
void ResetDay(SMART_DAY &day,const int key)
  {
   day.key=key;
   day.asia_valid=false;
   day.asia_high=0.0;
   day.asia_low=0.0;
   day.asia_start=0;
   day.asia_end=0;
   day.london_valid=false;
   day.london_high=0.0;
   day.london_low=0.0;
   day.london_start=0;
   day.london_end=0;
   day.newyork_valid=false;
   day.newyork_high=0.0;
   day.newyork_low=0.0;
   day.newyork_start=0;
   day.newyork_end=0;
  }

//+------------------------------------------------------------------+
void ResetCandidate(SMART_CANDIDATE &candidate)
  {
   candidate.active=false;
   candidate.phase=SMART_PHASE_NONE;
   candidate.sweep_side=0;
   candidate.direction=0;
   candidate.start_index=-1;
   candidate.extreme_index=-1;
   candidate.mss_index=-1;
   candidate.fvg_index=-1;
   candidate.day_key=0;
   candidate.sweep_time=0;
   candidate.extreme_time=0;
   candidate.mss_time=0;
   candidate.fvg_time=0;
   candidate.level=0.0;
   candidate.extreme=0.0;
   candidate.structure_level=0.0;
   candidate.fvg_low=0.0;
   candidate.fvg_high=0.0;
   candidate.range_low=0.0;
   candidate.range_high=0.0;
   candidate.atr_at_sweep=0.0;
   candidate.source_session="";
   candidate.best_score=0;
  }

//+------------------------------------------------------------------+
void ResetAnalysisState(SMART_CONTEXT &context)
  {
   context.status="RETAIL NOISE";
   context.note="WAITING FOR CONFIRMED SESSION SWEEP";
   context.session_name="IDLE";
   context.phase=SMART_PHASE_NONE;
   context.score=0;
   context.direction=0;
   context.rr=0.0;
   context.day_count=0;
   context.setup_count=0;
   context.testable_count=0;
   context.tp1_hit_count=0;
   context.tp2_hit_count=0;
   context.watch_count=0;
   for(int i=0;i<SMART_MAX_DAYS;i++)
      ResetDay(context.days[i],0);
  }

//+------------------------------------------------------------------+
int FindOrCreateDay(SMART_CONTEXT &context,const int key)
  {
   for(int i=0;i<context.day_count;i++)
      if(context.days[i].key==key)
         return i;

   if(context.day_count<SMART_MAX_DAYS)
     {
      int index=context.day_count++;
      ResetDay(context.days[index],key);
      return index;
     }

   for(int i=1;i<SMART_MAX_DAYS;i++)
      context.days[i-1]=context.days[i];
   ResetDay(context.days[SMART_MAX_DAYS-1],key);
   return SMART_MAX_DAYS-1;
  }

//+------------------------------------------------------------------+
void UpdateRange(bool &valid,double &high,double &low,datetime &start_time,
                 datetime &end_time,const MqlRates &bar)
  {
   if(!valid)
     {
      valid=true;
      high=bar.high;
      low=bar.low;
      start_time=bar.time;
      end_time=bar.time;
      return;
     }
   high=MathMax(high,bar.high);
   low=MathMin(low,bar.low);
   end_time=bar.time;
  }

//+------------------------------------------------------------------+
void UpdateDayRanges(SMART_DAY &day,const MqlRates &bar)
  {
   int minute=MinuteOfDayUTC(bar.time);
   int asia_start=InpAsiaStartHour*60+InpAsiaStartMinute;
   int asia_end=InpAsiaEndHour*60+InpAsiaEndMinute;
   int london_start=InpLondonStartHour*60+InpLondonStartMinute;
   int london_end=InpLondonRangeEndHour*60+InpLondonRangeEndMinute;
   int ny_start=InpNewYorkStartHour*60+InpNewYorkStartMinute;
   int ny_end=InpNewYorkEndHour*60+InpNewYorkEndMinute;

   if(InMinuteWindow(minute,asia_start,asia_end))
      UpdateRange(day.asia_valid,day.asia_high,day.asia_low,
                  day.asia_start,day.asia_end,bar);
   if(InMinuteWindow(minute,london_start,london_end))
      UpdateRange(day.london_valid,day.london_high,day.london_low,
                  day.london_start,day.london_end,bar);
   if(InMinuteWindow(minute,ny_start,ny_end))
      UpdateRange(day.newyork_valid,day.newyork_high,day.newyork_low,
                  day.newyork_start,day.newyork_end,bar);
  }

//+------------------------------------------------------------------+
void BuildATR(const MqlRates &rates[],double &atr[])
  {
   int count=ArraySize(rates);
   ArrayResize(atr,count);
   if(count<=0)
      return;
   double running=0.0;
   for(int i=0;i<count;i++)
     {
      double previous_close=(i>0 ? rates[i-1].close : rates[i].close);
      double tr=MathMax(rates[i].high-rates[i].low,
                        MathMax(MathAbs(rates[i].high-previous_close),
                                MathAbs(rates[i].low-previous_close)));
      if(i<InpATRPeriod)
        {
         running+=tr;
         atr[i]=(i==InpATRPeriod-1 ? running/InpATRPeriod : 0.0);
        }
      else
         atr[i]=(atr[i-1]*(InpATRPeriod-1)+tr)/InpATRPeriod;
     }
  }

//+------------------------------------------------------------------+
double VolumeZScore(const MqlRates &rates[],const int index)
  {
   int start=MathMax(0,index-InpVolumeLookback);
   int count=index-start;
   if(count<5)
      return 0.0;
   double mean=0.0;
   for(int i=start;i<index;i++)
      mean+=(double)rates[i].tick_volume;
   mean/=count;
   double variance=0.0;
   for(int i=start;i<index;i++)
     {
      double delta=(double)rates[i].tick_volume-mean;
      variance+=delta*delta;
     }
   variance/=count;
   double deviation=MathSqrt(variance);
   if(deviation<=0.0)
      return 0.0;
   return ((double)rates[index].tick_volume-mean)/deviation;
  }

//+------------------------------------------------------------------+
int VolumePoints(const MqlRates &rates[],const int index)
  {
   double z=VolumeZScore(rates,index);
   if(z>=1.00) return 5;
   return 0;
  }

//+------------------------------------------------------------------+
string PhaseText(const int phase)
  {
   if(phase==SMART_PHASE_SWEEP) return "SWEEP";
   if(phase==SMART_PHASE_WAIT_FVG) return "MSS";
   if(phase==SMART_PHASE_RETEST) return "FVG";
   return "SCAN";
  }

//+------------------------------------------------------------------+
int EventDepthPoints(const SMART_CANDIDATE &candidate)
  {
   if(candidate.atr_at_sweep<=0.0)
      return 10;
   double penetration=(candidate.sweep_side>0
                       ? candidate.extreme-candidate.level
                       : candidate.level-candidate.extreme);
   double ratio=penetration/candidate.atr_at_sweep;
   if(ratio>=0.20) return 15;
   return 10;
  }

//+------------------------------------------------------------------+
int DirectionalBodyPoints(const MqlRates &bar,const double atr,
                          const int direction)
  {
   if(atr<=0.0)
      return 0;
   bool directional=(direction>0 ? bar.close>bar.open : bar.close<bar.open);
   if(!directional)
      return 0;
   double ratio=MathAbs(bar.close-bar.open)/atr;
   if(ratio>=2.0*InpMinimumDisplacementATR) return 10;
   if(ratio>=InpMinimumDisplacementATR) return 5;
   return 0;
  }

//+------------------------------------------------------------------+
bool IsConfirmedSwingHigh(const MqlRates &rates[],const int index,
                          const int strength)
  {
   int count=ArraySize(rates);
   if(index-strength<0 || index+strength>=count)
      return false;
   for(int offset=1;offset<=strength;offset++)
      if(rates[index].high<=rates[index-offset].high ||
         rates[index].high<=rates[index+offset].high)
         return false;
   return true;
  }

//+------------------------------------------------------------------+
bool IsConfirmedSwingLow(const MqlRates &rates[],const int index,
                         const int strength)
  {
   int count=ArraySize(rates);
   if(index-strength<0 || index+strength>=count)
      return false;
   for(int offset=1;offset<=strength;offset++)
      if(rates[index].low>=rates[index-offset].low ||
         rates[index].low>=rates[index+offset].low)
         return false;
   return true;
  }

//+------------------------------------------------------------------+
bool FindStructureLevel(const MqlRates &rates[],const int sweep_index,
                        const int direction,double &level)
  {
   int latest=sweep_index-InpSwingStrength-1;
   int first=(int)MathMax(InpSwingStrength,sweep_index-InpSwingLookback);
   for(int index=latest;index>=first;index--)
     {
      bool found=(direction>0
                  ? IsConfirmedSwingHigh(rates,index,InpSwingStrength)
                  : IsConfirmedSwingLow(rates,index,InpSwingStrength));
      if(found)
        {
         double candidate_level=(direction>0 ? rates[index].high
                                             : rates[index].low);
         if(direction>0 && candidate_level<=rates[sweep_index].close)
            continue;
         if(direction<0 && candidate_level>=rates[sweep_index].close)
            continue;
         level=candidate_level;
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
bool IsMarketStructureShift(const MqlRates &bar,const double atr,
                            const SMART_CANDIDATE &candidate)
  {
   if(atr<=0.0 || MathAbs(bar.close-bar.open)<InpMinimumDisplacementATR*atr)
      return false;
   if(candidate.direction>0)
      return bar.close>candidate.structure_level && bar.close>bar.open;
   return bar.close<candidate.structure_level && bar.close<bar.open;
  }

//+------------------------------------------------------------------+
bool FindDirectionalFVG(const MqlRates &rates[],const double &atr[],
                        const int index,const int direction,
                        double &fvg_low,double &fvg_high)
  {
   if(index<2 || atr[index]<=0.0)
      return false;
   double minimum_gap=InpMinimumFVGATR*atr[index];
   if(direction>0)
     {
      double gap=rates[index].low-rates[index-2].high;
      if(gap<minimum_gap)
         return false;
      fvg_low=rates[index-2].high;
      fvg_high=rates[index].low;
      return true;
     }
   double gap=rates[index-2].low-rates[index].high;
   if(gap<minimum_gap)
      return false;
   fvg_low=rates[index].high;
   fvg_high=rates[index-2].low;
   return true;
  }

//+------------------------------------------------------------------+
bool IsFVGRetest(const MqlRates &bar,const double atr,
                 const SMART_CANDIDATE &candidate)
  {
   double tolerance=InpRetestToleranceATR*atr;
   bool overlaps=(bar.low<=candidate.fvg_high+tolerance &&
                  bar.high>=candidate.fvg_low-tolerance);
   if(!overlaps)
      return false;
   double midpoint=(candidate.fvg_low+candidate.fvg_high)*0.5;
   return (candidate.direction>0 ? bar.close>midpoint
                                 : bar.close<midpoint);
  }

//+------------------------------------------------------------------+
int FVGPoints(const SMART_CANDIDATE &candidate)
  {
   if(candidate.atr_at_sweep<=0.0)
      return 15;
   double ratio=(candidate.fvg_high-candidate.fvg_low)/candidate.atr_at_sweep;
   return (ratio>=0.15 ? 20 : 15);
  }

//+------------------------------------------------------------------+
bool CompleteICTSequence(const SMART_CANDIDATE &candidate,
                         const int retest_index,const int rates_count)
  {
   if(candidate.phase!=SMART_PHASE_RETEST || candidate.direction==0)
      return false;
   if(candidate.start_index<0 || candidate.mss_index<=candidate.start_index ||
      candidate.fvg_index<candidate.mss_index ||
      retest_index<=candidate.fvg_index || retest_index>=rates_count)
      return false;
   if(candidate.structure_level<=0.0 || candidate.extreme<=0.0 ||
      candidate.fvg_low<=0.0 || candidate.fvg_high<=candidate.fvg_low)
      return false;
   return true;
  }

//+------------------------------------------------------------------+
int CalculateQualityScore(const MqlRates &rates[],const double &atr[],
                          const int index,const SMART_CANDIDATE &candidate,
                          string &components)
  {
   components="INCOMPLETE ICT SEQUENCE";
   if(!CompleteICTSequence(candidate,index,ArraySize(rates)) ||
      candidate.mss_index>=ArraySize(atr))
      return 0;
   int sweep=EventDepthPoints(candidate);
   int displacement=DirectionalBodyPoints(rates[candidate.mss_index],
                                           atr[candidate.mss_index],
                                           candidate.direction);
   int fvg=FVGPoints(candidate);
   int volume=VolumePoints(rates,candidate.mss_index);
   int score=15+sweep+20+displacement+fvg+15+volume;
   components=StringFormat("LQ15 SW%d MS20 DP%d FV%d RT15 TV%d",
                           sweep,displacement,fvg,volume);
   return ClampInt(score,0,100);
  }

//+------------------------------------------------------------------+
void AddSetup(SMART_CONTEXT &context,const SMART_SETUP &setup)
  {
   if(context.setup_count<SMART_MAX_SETUPS)
     {
      context.setups[context.setup_count++]=setup;
      return;
     }
   for(int i=1;i<SMART_MAX_SETUPS;i++)
      context.setups[i-1]=context.setups[i];
   context.setups[SMART_MAX_SETUPS-1]=setup;
  }

//+------------------------------------------------------------------+
void AddWatch(SMART_CONTEXT &context,const SMART_CANDIDATE &candidate,
              const string reason)
  {
   for(int i=context.watch_count-1;i>=0;i--)
     {
      if(context.watches[i].day_key<candidate.day_key)
         break;
      if(context.watches[i].day_key==candidate.day_key &&
         context.watches[i].sweep_side==candidate.sweep_side &&
         context.watches[i].source_session==candidate.source_session)
         return;
     }
   SMART_WATCH watch;
   watch.id=StringFormat("%s_W_%I64d_%d",context.symbol,
                         (long)candidate.sweep_time,candidate.sweep_side);
   watch.sweep_side=candidate.sweep_side;
   watch.direction=candidate.direction;
   watch.score=candidate.best_score;
   watch.day_key=candidate.day_key;
   watch.sweep_time=candidate.sweep_time;
   watch.extreme_time=candidate.extreme_time;
   watch.sweep_extreme=candidate.extreme;
   watch.source_session=candidate.source_session;
   watch.reason=reason;
   if(context.watch_count<SMART_MAX_WATCHES)
     {
      context.watches[context.watch_count++]=watch;
      return;
     }
   for(int i=1;i<SMART_MAX_WATCHES;i++)
      context.watches[i-1]=context.watches[i];
   context.watches[SMART_MAX_WATCHES-1]=watch;
  }

//+------------------------------------------------------------------+
bool HasSessionProjection(const SMART_CONTEXT &context,const int day_key,
                          const string source_session,const int sweep_side)
  {
   for(int i=context.setup_count-1;i>=0;i--)
     {
      if(context.setups[i].day_key<day_key)
         break;
      if(context.setups[i].day_key==day_key &&
         context.setups[i].sweep_side==sweep_side &&
         context.setups[i].source_session==source_session)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
bool BuildProjection(const string symbol,const SMART_CANDIDATE &candidate,
                     const int score,const datetime confirmed_time,
                     const double confirmed_price,const int confirmed_index,
                     const string components,SMART_SETUP &setup,
                     string &rejection_reason)
  {
   rejection_reason="EXECUTION GEOMETRY REJECTED";
   double atr=candidate.atr_at_sweep;
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   if(atr<=0.0 || point<=0.0)
      return false;

   double entry=confirmed_price;
   double invalidation=candidate.extreme;
   double stop=(candidate.direction>0
                ? invalidation-InpStopBufferATR*atr
                : invalidation+InpStopBufferATR*atr);
   double risk=MathAbs(entry-stop);
   double minimum_risk=InpMinimumRiskATR*atr;
   if(risk<minimum_risk)
     {
      stop=(candidate.direction>0 ? entry-minimum_risk
                                  : entry+minimum_risk);
      risk=minimum_risk;
     }
   if(risk<=point)
      return false;
   if(risk>InpMaximumRiskATR*atr)
     {
      rejection_reason="STRUCTURAL RISK TOO LARGE";
      return false;
     }

   double opposite=(candidate.direction>0 ? candidate.range_high
                                          : candidate.range_low);
   double liquidity_distance=(candidate.direction>0 ? opposite-entry
                                                    : entry-opposite);
   if(liquidity_distance<=0.0)
     {
      rejection_reason="OPPOSING LIQUIDITY ON WRONG SIDE";
      return false;
     }
   double target_distance=MathMin(InpTP2RiskMultiple*risk,
                                  liquidity_distance);
   double rr=target_distance/risk;
   if(rr<InpMinimumProjectionRR)
     {
      rejection_reason="TARGET ROOM BELOW MINIMUM R:R";
     return false;
     }
   double tp1_distance=InpTP1RiskMultiple*risk;
   if(tp1_distance>=target_distance)
     {
      rejection_reason="TP1 AND TP2 GEOMETRY INVALID";
      return false;
     }
   double tp1=(candidate.direction>0 ? entry+tp1_distance
                                     : entry-tp1_distance);
   double tp2=(candidate.direction>0 ? entry+target_distance
                                     : entry-target_distance);

   setup.id=StringFormat("%s_%I64d_%d",symbol,(long)candidate.sweep_time,
                         candidate.direction);
   setup.sweep_side=candidate.sweep_side;
   setup.direction=candidate.direction;
   setup.score=score;
   setup.sweep_time=candidate.sweep_time;
   setup.extreme_time=candidate.extreme_time;
   setup.mss_time=candidate.mss_time;
   setup.fvg_time=candidate.fvg_time;
   setup.confirmed_time=confirmed_time;
   setup.confirmed_index=confirmed_index;
   setup.day_key=candidate.day_key;
   setup.sweep_extreme=candidate.extreme;
   setup.structure_level=candidate.structure_level;
   setup.fvg_low=candidate.fvg_low;
   setup.fvg_high=candidate.fvg_high;
   setup.entry=entry;
   setup.stop=stop;
   setup.tp1=tp1;
   setup.tp2=tp2;
   setup.rr=rr;
   setup.source_session=candidate.source_session;
   setup.components=components;
   return true;
  }

//+------------------------------------------------------------------+
bool StartCandidate(SMART_CANDIDATE &candidate,const MqlRates &rates[],
                    const int sweep_side,const int index,const int day_key,
                    const MqlRates &bar,const double level,
                    const double range_low,const double range_high,
                    const double atr,const string source_session)
  {
   ResetCandidate(candidate);
   candidate.direction=-sweep_side;
   candidate.phase=SMART_PHASE_SWEEP;
   candidate.sweep_side=sweep_side;
   candidate.start_index=index;
   candidate.extreme_index=index;
   candidate.day_key=day_key;
   candidate.sweep_time=bar.time;
   candidate.extreme_time=bar.time;
   candidate.level=level;
   candidate.extreme=(sweep_side>0 ? bar.high : bar.low);
   candidate.range_low=range_low;
   candidate.range_high=range_high;
   candidate.atr_at_sweep=atr;
   candidate.source_session=source_session;
   candidate.best_score=20;
   if(!FindStructureLevel(rates,index,candidate.direction,
                          candidate.structure_level))
      return false;
   candidate.active=true;
   return true;
  }

//+------------------------------------------------------------------+
bool SelectReferenceRange(const SMART_DAY &day,const int minute,
                          double &range_low,double &range_high,
                          string &source_session)
  {
   int london_start=InpLondonStartHour*60+InpLondonStartMinute;
   int london_sweep_end=InpLondonSweepEndHour*60+InpLondonSweepEndMinute;
   int ny_start=InpNewYorkStartHour*60+InpNewYorkStartMinute;
   int ny_end=InpNewYorkEndHour*60+InpNewYorkEndMinute;

   if(InMinuteWindow(minute,london_start,london_sweep_end) && day.asia_valid)
     {
      range_low=day.asia_low;
      range_high=day.asia_high;
      source_session="ASIA -> LONDON";
      return true;
     }
   if(InMinuteWindow(minute,ny_start,ny_end) && day.london_valid)
     {
      range_low=day.london_low;
      range_high=day.london_high;
      source_session="LONDON -> NEW YORK";
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
void SetCandidateContext(SMART_CONTEXT &context,
                         const SMART_CANDIDATE &candidate,
                         const int score,const string status,
                         const string note)
  {
   context.score=score;
   context.direction=candidate.direction;
   context.phase=candidate.phase;
   context.status=status;
   context.note=note;
   context.session_name=candidate.source_session;
   context.rr=0.0;
  }

//+------------------------------------------------------------------+
void FinishAsWatch(SMART_CONTEXT &context,SMART_CANDIDATE &candidate,
                   const string reason)
  {
   AddWatch(context,candidate,reason);
   SetCandidateContext(context,candidate,candidate.best_score,
                       "WATCH",reason);
   candidate.active=false;
  }

//+------------------------------------------------------------------+
void UpdateSweepExtreme(SMART_CANDIDATE &candidate,
                        const MqlRates &bar,const int index)
  {
   if(candidate.sweep_side>0 && bar.high>candidate.extreme)
     {
      candidate.extreme=bar.high;
      candidate.extreme_index=index;
      candidate.extreme_time=bar.time;
     }
   else if(candidate.sweep_side<0 && bar.low<candidate.extreme)
     {
      candidate.extreme=bar.low;
      candidate.extreme_index=index;
      candidate.extreme_time=bar.time;
     }
  }

//+------------------------------------------------------------------+
void FinalizeICTSetup(SMART_CONTEXT &context,SMART_CANDIDATE &candidate,
                      const MqlRates &rates[],const double &atr[],
                      const int index)
  {
   string components="";
   int score=CalculateQualityScore(rates,atr,index,candidate,components);
   candidate.best_score=score;
   if(score<InpViableThreshold)
     {
      FinishAsWatch(context,candidate,"QUALITY SCORE BELOW VIABLE");
      return;
     }
   SMART_SETUP setup;
   string projection_rejection="";
   if(BuildProjection(context.symbol,candidate,score,rates[index].time,
                      rates[index].close,index,components,setup,
                      projection_rejection))
     {
      AddSetup(context,setup);
      SetCandidateContext(context,candidate,score,ScoreState(score),
                          "ICT MODEL PROJECTION VALIDATED");
      context.rr=setup.rr;
      candidate.active=false;
      return;
     }
   FinishAsWatch(context,candidate,projection_rejection);
  }

//+------------------------------------------------------------------+
void ProcessCandidate(SMART_CONTEXT &context,SMART_CANDIDATE &candidate,
                      const MqlRates &rates[],const double &atr[],const int index)
  {
   if(!candidate.active)
      return;

   if(candidate.phase==SMART_PHASE_SWEEP)
     {
      UpdateSweepExtreme(candidate,rates[index],index);
      int event_age=index-candidate.start_index;
      if(index>candidate.start_index &&
         IsMarketStructureShift(rates[index],atr[index],candidate))
        {
         candidate.mss_index=index;
         candidate.mss_time=rates[index].time;
         candidate.best_score=45;
         if(FindDirectionalFVG(rates,atr,index,candidate.direction,
                               candidate.fvg_low,candidate.fvg_high))
           {
            candidate.fvg_index=index;
            candidate.fvg_time=rates[index].time;
            candidate.phase=SMART_PHASE_RETEST;
            candidate.best_score=60;
            SetCandidateContext(context,candidate,60,"TRACKING",
                                "MSS AND FVG CONFIRMED, WAITING FOR RETEST");
            return;
           }
         candidate.phase=SMART_PHASE_WAIT_FVG;
         SetCandidateContext(context,candidate,45,"TRACKING",
                             "MSS CONFIRMED, WAITING FOR FVG");
         return;
        }
      if(event_age>=InpMSSBars)
        {
         FinishAsWatch(context,candidate,"SWEEP WITHOUT CONFIRMED MSS");
         return;
        }
      SetCandidateContext(context,candidate,20,"TRACKING",
                          "LIQUIDITY SWEPT, WAITING FOR MSS");
      return;
     }

   bool invalidated=(candidate.direction>0
                     ? rates[index].low<candidate.extreme
                     : rates[index].high>candidate.extreme);
   if(invalidated)
     {
      FinishAsWatch(context,candidate,"ICT SETUP INVALIDATED AFTER MSS");
      return;
     }

   if(candidate.phase==SMART_PHASE_WAIT_FVG)
     {
      int fvg_age=index-candidate.mss_index;
      if(FindDirectionalFVG(rates,atr,index,candidate.direction,
                            candidate.fvg_low,candidate.fvg_high))
        {
         candidate.fvg_index=index;
         candidate.fvg_time=rates[index].time;
         candidate.phase=SMART_PHASE_RETEST;
         candidate.best_score=60;
         SetCandidateContext(context,candidate,60,"TRACKING",
                             "POST-MSS FVG CONFIRMED, WAITING FOR RETEST");
         return;
        }
      if(fvg_age>=InpFVGFormationBars)
        {
         FinishAsWatch(context,candidate,"MSS WITHOUT DIRECTIONAL FVG");
         return;
        }
      SetCandidateContext(context,candidate,45,"TRACKING",
                          "MSS CONFIRMED, WAITING FOR FVG");
      return;
     }

   int retest_age=index-candidate.fvg_index;
   if(index>candidate.fvg_index &&
      IsFVGRetest(rates[index],atr[index],candidate))
     {
      FinalizeICTSetup(context,candidate,rates,atr,index);
      return;
     }
   if(retest_age>=InpRetestBars)
     {
      FinishAsWatch(context,candidate,
                    "FVG WITHOUT VALID RETEST");
      return;
     }
   SetCandidateContext(context,candidate,60,"TRACKING",
                       "FVG CONFIRMED, WAITING FOR RETEST");
  }

//+------------------------------------------------------------------+
bool PossibleSweep(const MqlRates &bar,const MqlRates &previous_bar,
                   const double atr,
                   const double range_low,const double range_high,
                   int &sweep_side,double &level)
  {
   if(atr<=0.0)
      return false;
   double high_penetration=bar.high-range_high;
   double low_penetration=range_low-bar.low;
   bool high_sweep=(previous_bar.close<=range_high &&
                    high_penetration>=InpMinimumSweepATR*atr);
   bool low_sweep=(previous_bar.close>=range_low &&
                   low_penetration>=InpMinimumSweepATR*atr);
   if(!high_sweep && !low_sweep)
      return false;

   if(high_sweep && (!low_sweep || high_penetration>=low_penetration))
     {
      sweep_side=1;
      level=range_high;
     }
   else
     {
      sweep_side=-1;
      level=range_low;
     }
   return true;
  }

//+------------------------------------------------------------------+
void EvaluateHistoricalSetups(SMART_CONTEXT &context,const MqlRates &rates[])
  {
   context.testable_count=0;
   context.tp1_hit_count=0;
   context.tp2_hit_count=0;
   int bars=ArraySize(rates);
   for(int i=0;i<context.setup_count;i++)
     {
      int first=context.setups[i].confirmed_index+1;
      if(first>=bars)
         continue;
      context.testable_count++;
      bool tp1_hit=false;
      int last=MathMin(bars-1,context.setups[i].confirmed_index+
                              InpProjectionBars);
      for(int j=first;j<=last;j++)
        {
         bool stop_hit=(context.setups[i].direction>0
                        ? rates[j].low<=context.setups[i].stop
                        : rates[j].high>=context.setups[i].stop);
         bool tp2_hit=(context.setups[i].direction>0
                       ? rates[j].high>=context.setups[i].tp2
                       : rates[j].low<=context.setups[i].tp2);
         bool first_target=(context.setups[i].direction>0
                            ? rates[j].high>=context.setups[i].tp1
                            : rates[j].low<=context.setups[i].tp1);
         if(stop_hit)
           {
            break;
           }
         if(first_target)
            tp1_hit=true;
         if(tp2_hit)
           {
            context.tp2_hit_count++;
            break;
           }
        }
      if(tp1_hit)
         context.tp1_hit_count++;
     }
  }

//+------------------------------------------------------------------+
void AnalyzeSymbol(SMART_CONTEXT &context,const MqlRates &rates[],
                   const double &atr[])
  {
   ResetAnalysisState(context);
   SMART_CANDIDATE candidate;
   ResetCandidate(candidate);
   int count=ArraySize(rates);
   int warmup=MathMax(InpATRPeriod+2,InpVolumeLookback+2);

   for(int i=0;i<count;i++)
     {
      int day_key=DayKeyUTC(rates[i].time);
      int day_index=FindOrCreateDay(context,day_key);
      UpdateDayRanges(context.days[day_index],rates[i]);

      if(i<warmup || atr[i]<=0.0)
         continue;

      bool had_candidate=candidate.active;
      ProcessCandidate(context,candidate,rates,atr,i);
      if(had_candidate || candidate.active)
         continue;

      int minute=MinuteOfDayUTC(rates[i].time);
      double range_low=0.0;
      double range_high=0.0;
      string source_session="";
      if(!SelectReferenceRange(context.days[day_index],minute,
                               range_low,range_high,source_session))
         continue;

      int sweep_side=0;
      double level=0.0;
      if(!PossibleSweep(rates[i],rates[i-1],atr[i],range_low,range_high,
                        sweep_side,level))
         continue;
      if(HasSessionProjection(context,day_key,source_session,sweep_side))
         continue;

      if(!StartCandidate(candidate,rates,sweep_side,i,day_key,rates[i],level,
                         range_low,range_high,atr[i],source_session))
        {
         AddWatch(context,candidate,"SWEEP WITHOUT CONFIRMED SWING LEVEL");
         continue;
        }
      context.score=20;
      context.direction=candidate.direction;
      context.phase=SMART_PHASE_SWEEP;
      context.status="TRACKING";
      context.note="SESSION LIQUIDITY SWEPT";
      context.session_name=source_session;
      ProcessCandidate(context,candidate,rates,atr,i);
     }

   EvaluateHistoricalSetups(context,rates);

   if(candidate.active)
      return;

   if(context.setup_count>0)
     {
      SMART_SETUP latest=context.setups[context.setup_count-1];
      int setup_age=(count-1)-latest.confirmed_index;
      if(setup_age>=0 && setup_age<=InpDashboardSetupAgeBars)
        {
         context.score=latest.score;
         context.direction=latest.direction;
         context.phase=SMART_PHASE_RETEST;
         context.status=ScoreState(latest.score);
         context.note="ICT PROJECTION ACTIVE";
         context.session_name=latest.source_session;
         context.rr=latest.rr;
         return;
        }
     }

   context.status="IDLE";
   context.note="WAITING FOR CURRENT SESSION EVENT";
   int current_minute=MinuteOfDayUTC(rates[count-1].time);
   int asia_start=InpAsiaStartHour*60+InpAsiaStartMinute;
   int asia_end=InpAsiaEndHour*60+InpAsiaEndMinute;
   int london_start=InpLondonStartHour*60+InpLondonStartMinute;
   int london_end=InpLondonRangeEndHour*60+InpLondonRangeEndMinute;
   int ny_start=InpNewYorkStartHour*60+InpNewYorkStartMinute;
   int ny_end=InpNewYorkEndHour*60+InpNewYorkEndMinute;
   if(InMinuteWindow(current_minute,asia_start,asia_end))
      context.session_name="ASIA BUILD";
   else if(InMinuteWindow(current_minute,london_start,london_end))
      context.session_name="LONDON SCAN";
   else if(InMinuteWindow(current_minute,ny_start,ny_end))
      context.session_name="NEW YORK SCAN";
   else
      context.session_name="OFF HOURS";
   context.score=0;
   context.direction=0;
   context.phase=SMART_PHASE_NONE;
   context.rr=0.0;
  }

//+------------------------------------------------------------------+
bool LoadClosedRates(const string symbol,MqlRates &rates[])
  {
   int requested=ClampInt(InpHistoryBars,250,50000);
   ArraySetAsSeries(rates,false);
   int copied=CopyRates(symbol,InpAnalysisTimeframe,1,requested,rates);
   if(copied<MathMax(100,InpATRPeriod+InpVolumeLookback+20))
      return false;
   if(copied<ArraySize(rates))
      ArrayResize(rates,copied);
   return true;
  }

//+------------------------------------------------------------------+
string LatestSetupId(const SMART_CONTEXT &context)
  {
   if(context.setup_count<=0)
      return "";
   return context.setups[context.setup_count-1].id;
  }

//+------------------------------------------------------------------+
string NewsImportanceText(const int importance)
  {
   if(importance>=3) return "HIGH";
   if(importance==2) return "MODERATE";
   if(importance==1) return "LOW";
   return "NONE";
  }

//+------------------------------------------------------------------+
void UpdateEconomicContext(SMART_CONTEXT &context,const bool force)
  {
   if(!InpUseEconomicCalendar)
     {
      context.news_state="OFF";
      context.news_name="";
      context.news_detail="Economic calendar disabled by input";
      return;
     }
   if((bool)MQLInfoInteger(MQL_TESTER))
     {
      context.news_state="TESTER";
      context.news_name="";
      context.news_detail="Native calendar is live-terminal context only";
      return;
     }

   datetime now=TimeTradeServer();
   if(now<=0)
     {
      context.news_state="N/A";
      context.news_detail="Trade server time unavailable";
      return;
     }
   if(!force && context.last_news_refresh>0 &&
      now-context.last_news_refresh<60)
      return;
   context.last_news_refresh=now;
   context.news_state="CLEAR";
   context.news_name="";
   context.news_time=0;
   context.news_importance=0;
   context.news_detail="No matching event inside the configured window";

   string currencies[2];
   currencies[0]=SymbolInfoString(context.symbol,SYMBOL_CURRENCY_BASE);
   currencies[1]=SymbolInfoString(context.symbol,SYMBOL_CURRENCY_PROFIT);
   datetime from_time=now-InpNewsMinutesAfter*60;
   datetime to_time=now+InpNewsMinutesBefore*60;
   long best_distance=LONG_MAX;
   bool query_succeeded=false;
   MqlCalendarValue selected_value={};
   MqlCalendarEvent selected_event={};
   string selected_currency="";

   for(int currency_index=0;currency_index<2;currency_index++)
     {
      string currency=currencies[currency_index];
      if(currency=="" ||
         (currency_index==1 && currency==currencies[0]))
         continue;
      MqlCalendarValue values[];
      ResetLastError();
      int count=CalendarValueHistory(values,from_time,to_time,"",currency);
      if(count<0)
         continue;
      query_succeeded=true;
      for(int value_index=0;value_index<count;value_index++)
        {
         MqlCalendarEvent event;
         if(!CalendarEventById(values[value_index].event_id,event))
            continue;
         int importance=(int)event.importance;
         if(importance<InpMinimumNewsImportance)
            continue;
         long distance=(long)MathAbs((double)(values[value_index].time-now));
         if(distance>=best_distance)
            continue;
         best_distance=distance;
         selected_value=values[value_index];
         selected_event=event;
         selected_currency=currency;
        }
     }

   if(best_distance==LONG_MAX)
     {
      if(!query_succeeded)
        {
         context.news_state="N/A";
         context.news_detail="Economic calendar data unavailable";
        }
      return;
     }

   context.news_time=selected_value.time;
   context.news_importance=(int)selected_event.importance;
   context.news_name=selected_currency+" "+selected_event.name;
   int seconds=(int)(selected_value.time-now);
   if(seconds>0)
     {
      int minutes=(int)MathCeil(seconds/60.0);
      context.news_state="IN "+IntegerToString(minutes)+"M";
     }
   else
      context.news_state="LIVE";
   context.news_detail=context.news_name+" | "+
                       NewsImportanceText(context.news_importance)+" | "+
                       TimeToString(context.news_time,TIME_DATE|TIME_MINUTES);
   if(selected_value.HasActualValue())
      context.news_detail+=" | ACT "+
                           DoubleToString(selected_value.GetActualValue(),2);
   if(selected_value.HasForecastValue())
      context.news_detail+=" | FCST "+
                           DoubleToString(selected_value.GetForecastValue(),2);
  }

//+------------------------------------------------------------------+
void SendSMARTAlert(const SMART_CONTEXT &context,const SMART_SETUP &setup)
  {
   string message=StringFormat("S.M.A.R.T. %s %d | %s ICT %s | R:R %.2f",
                               context.symbol,setup.score,
                               setup.source_session,
                               DirectionText(setup.direction),setup.rr);
   if(InpTerminalAlerts) Alert(message);
   if(InpPushAlerts) SendNotification(message);
   if(InpEmailAlerts) SendMail("S.M.A.R.T. ICT/SMC setup confirmed",message);
  }

//+------------------------------------------------------------------+
void ProcessSymbol(const int context_index,const bool force)
  {
   if(context_index<0 || context_index>=SMART_SYMBOLS)
      return;
   if(!g_contexts[context_index].available)
      return;

   UpdateEconomicContext(g_contexts[context_index],force);

   datetime probe=iTime(g_contexts[context_index].symbol,
                        InpAnalysisTimeframe,1);
   if(!force && probe>0 &&
      probe==g_contexts[context_index].last_closed_bar)
      return;

   MqlRates rates[];
   if(!LoadClosedRates(g_contexts[context_index].symbol,rates))
     {
      g_contexts[context_index].status="DATA WAIT";
      g_contexts[context_index].note="HISTORY NOT READY";
      g_contexts[context_index].session_name="-";
      g_contexts[context_index].score=0;
      g_contexts[context_index].direction=0;
      g_contexts[context_index].phase=SMART_PHASE_NONE;
      g_contexts[context_index].rr=0.0;
      g_contexts[context_index].setup_count=0;
      g_contexts[context_index].testable_count=0;
      g_contexts[context_index].tp1_hit_count=0;
      g_contexts[context_index].tp2_hit_count=0;
      g_contexts[context_index].news_state=(InpUseEconomicCalendar ? "N/A" : "OFF");
      g_contexts[context_index].watch_count=0;
      return;
     }
   datetime latest=rates[ArraySize(rates)-1].time;
   if(!force && latest==g_contexts[context_index].last_closed_bar)
      return;

   string previous_alert=g_contexts[context_index].last_alerted_id;
   bool was_initialized=g_contexts[context_index].initialized;
   double atr[];
   BuildATR(rates,atr);
   AnalyzeSymbol(g_contexts[context_index],rates,atr);
   g_contexts[context_index].last_closed_bar=latest;

   string newest_id=LatestSetupId(g_contexts[context_index]);
   if(newest_id!="" && newest_id!=previous_alert)
     {
      g_contexts[context_index].last_alerted_id=newest_id;
      if(was_initialized || InpAlertOnInitialization)
         SendSMARTAlert(g_contexts[context_index],
                        g_contexts[context_index].setups[
                           g_contexts[context_index].setup_count-1]);
     }
   g_contexts[context_index].initialized=true;
  }

//+------------------------------------------------------------------+
void DeleteObjectsByPrefix(const string prefix)
  {
   ObjectsDeleteAll(0,prefix);
  }

//+------------------------------------------------------------------+
void SetCommonObjectProperties(const string name)
  {
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

//+------------------------------------------------------------------+
void CreateRangeRectangle(const string name,const datetime start_time,
                          const datetime end_time,const double high,
                          const double low,const color box_color)
  {
   if(start_time<=0 || end_time<=0 || high<=low)
      return;
   datetime extended_end=end_time+PeriodSeconds(InpAnalysisTimeframe);
   if(!ObjectCreate(0,name,OBJ_RECTANGLE,0,start_time,high,extended_end,low))
      return;
   ObjectSetInteger(0,name,OBJPROP_COLOR,box_color);
   ObjectSetInteger(0,name,OBJPROP_FILL,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
   SetCommonObjectProperties(name);
  }

//+------------------------------------------------------------------+
void CreateChartText(const string name,const datetime when,const double price,
                     const string text_value,const color text_color,
                     const ENUM_ANCHOR_POINT anchor)
  {
   if(!ObjectCreate(0,name,OBJ_TEXT,0,when,price))
      return;
   ObjectSetString(0,name,OBJPROP_TEXT,text_value);
   ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,name,OBJPROP_COLOR,text_color);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchor);
   SetCommonObjectProperties(name);
  }

//+------------------------------------------------------------------+
void CreatePurgeMarker(const string name,const datetime when,const double price,
                       const int direction,const color marker_color,
                       const string tooltip)
  {
   if(!ObjectCreate(0,name,OBJ_ARROW,0,when,price))
      return;
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,(direction>0 ? 233 : 234));
   ObjectSetInteger(0,name,OBJPROP_COLOR,marker_color);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tooltip);
   SetCommonObjectProperties(name);
  }

//+------------------------------------------------------------------+
void CreateWatchMarker(const string name,const datetime when,const double price,
                       const string tooltip)
  {
   if(!ObjectCreate(0,name,OBJ_ARROW,0,when,price))
      return;
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,159);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrGold);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tooltip);
   SetCommonObjectProperties(name);
  }

//+------------------------------------------------------------------+
void CreateProjectionLine(const string name,const datetime start_time,
                          const datetime end_time,const double price,
                          const color line_color,const ENUM_LINE_STYLE style)
  {
   if(!ObjectCreate(0,name,OBJ_TREND,0,start_time,price,end_time,price))
      return;
   ObjectSetInteger(0,name,OBJPROP_COLOR,line_color);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   SetCommonObjectProperties(name);
  }

//+------------------------------------------------------------------+
void CreateTradeRectangle(const string name,const datetime start_time,
                          const datetime end_time,const double price1,
                          const double price2,const color fill_color)
  {
   double high=MathMax(price1,price2);
   double low=MathMin(price1,price2);
   if(high<=low || !ObjectCreate(0,name,OBJ_RECTANGLE,0,
                                 start_time,high,end_time,low))
      return;
   ObjectSetInteger(0,name,OBJPROP_COLOR,fill_color);
   ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_SOLID);
   SetCommonObjectProperties(name);
  }

//+------------------------------------------------------------------+
void RenderSessionBoxes(const SMART_CONTEXT &context)
  {
   if(!InpShowSessionBoxes)
      return;
   int drawn=0;
   for(int i=context.day_count-1;i>=0 && drawn<3;i--)
     {
      string key=IntegerToString(context.days[i].key);
      if(context.days[i].newyork_valid && drawn<3)
        {
         CreateRangeRectangle(g_object_prefix+"CHART_NY_"+key,
                              context.days[i].newyork_start,context.days[i].newyork_end,
                              context.days[i].newyork_high,context.days[i].newyork_low,
                              InpNewYorkColor);
         drawn++;
        }
      if(context.days[i].london_valid && drawn<3)
        {
         CreateRangeRectangle(g_object_prefix+"CHART_LONDON_"+key,
                              context.days[i].london_start,context.days[i].london_end,
                              context.days[i].london_high,context.days[i].london_low,
                              InpLondonColor);
         drawn++;
        }
      if(context.days[i].asia_valid && drawn<3)
        {
         CreateRangeRectangle(g_object_prefix+"CHART_ASIA_"+key,
                              context.days[i].asia_start,context.days[i].asia_end,
                              context.days[i].asia_high,context.days[i].asia_low,
                              InpAsiaColor);
         drawn++;
        }
     }
  }

//+------------------------------------------------------------------+
void RenderSetup(const SMART_CONTEXT &context,const SMART_SETUP &setup,
                 const int ordinal)
  {
   color direction_color=(setup.direction>0 ? InpBullishColor : InpBearishColor);
   string base=g_object_prefix+"CHART_SETUP_"+IntegerToString(ordinal)+"_"+
               IntegerToString((int)setup.sweep_time);
   string marker=StringFormat("ICT/SMC Liquidity Sweep | SMART %d | %s | %s",
                              setup.score,
                              DirectionText(setup.direction),setup.components);
   CreatePurgeMarker(base+"_PURGE",setup.extreme_time,setup.sweep_extreme,
                     setup.direction,direction_color,marker);

   if(!InpShowTradeProjections)
      return;
   int analysis_span=PeriodSeconds(InpAnalysisTimeframe)*InpProjectionBars;
   int chart_span=PeriodSeconds(_Period)*InpMinimumChartProjectionBars;
   int projection_span=(int)MathMax(analysis_span,chart_span);
   datetime end_time=setup.confirmed_time+projection_span;
   CreateTradeRectangle(base+"_FVG",setup.fvg_time,end_time,
                        setup.fvg_low,setup.fvg_high,InpFVGColor);
   ObjectSetString(0,base+"_FVG",OBJPROP_TOOLTIP,
                   "ICT FAIR VALUE GAP | "+
                   PriceText(context.symbol,setup.fvg_low)+" - "+
                   PriceText(context.symbol,setup.fvg_high));
   CreateProjectionLine(base+"_MSS",setup.mss_time,setup.confirmed_time,
                        setup.structure_level,C'90,150,205',STYLE_DOT);
   ObjectSetString(0,base+"_MSS",OBJPROP_TOOLTIP,
                   "MARKET STRUCTURE SHIFT | "+
                   PriceText(context.symbol,setup.structure_level));
   CreateTradeRectangle(base+"_REWARD",setup.confirmed_time,end_time,
                        setup.entry,setup.tp2,InpRewardZoneColor);
   CreateTradeRectangle(base+"_RISK",setup.confirmed_time,end_time,
                        setup.entry,setup.stop,InpRiskZoneColor);
   ObjectSetString(0,base+"_REWARD",OBJPROP_TOOLTIP,
                   "ENTRY "+PriceText(context.symbol,setup.entry)+
                   " | TP1 "+PriceText(context.symbol,setup.tp1)+
                   " | TP2 "+PriceText(context.symbol,setup.tp2));
   ObjectSetString(0,base+"_RISK",OBJPROP_TOOLTIP,
                   "ENTRY "+PriceText(context.symbol,setup.entry)+
                   " | SL "+PriceText(context.symbol,setup.stop));
   CreateProjectionLine(base+"_ENTRY",setup.confirmed_time,end_time,
                        setup.entry,direction_color,STYLE_SOLID);
   CreateProjectionLine(base+"_TP1",setup.confirmed_time,end_time,
                        setup.tp1,clrGold,STYLE_DOT);
   string summary=StringFormat("ICT S%d %s | %.2fR",
                               setup.score,
                               DirectionText(setup.direction),setup.rr);
   CreateChartText(base+"_SUMMARY",end_time,setup.entry,summary,
                   direction_color,ANCHOR_LEFT);
  }

//+------------------------------------------------------------------+
void RenderWatch(const SMART_WATCH &watch,const int ordinal)
  {
   string base=g_object_prefix+"CHART_WATCH_"+IntegerToString(ordinal)+"_"+
               IntegerToString((int)watch.sweep_time);
   string tooltip=StringFormat("ICT WATCH | %s | %s | %s",
                               DirectionText(watch.direction),
                               watch.source_session,watch.reason);
   CreateWatchMarker(base,watch.extreme_time,watch.sweep_extreme,tooltip);
  }

//+------------------------------------------------------------------+
int ChartContextIndex()
  {
   string chart_upper=UpperCopy(_Symbol);
   for(int i=0;i<SMART_SYMBOLS;i++)
      if(UpperCopy(g_contexts[i].symbol)==chart_upper)
         return i;
   return -1;
  }

//+------------------------------------------------------------------+
void RenderChartAnalysis()
  {
   DeleteObjectsByPrefix(g_object_prefix+"CHART_");
   int context_index=ChartContextIndex();
   if(context_index<0 || !g_contexts[context_index].available)
      return;
   RenderSessionBoxes(g_contexts[context_index]);
   if(InpShowWatchMarkers)
     {
      int watch_display=ClampInt(InpMaximumDisplayedWatches,1,12);
      int watch_first=(int)MathMax(0,g_contexts[context_index].watch_count-
                                     watch_display);
      int watch_ordinal=0;
      for(int i=watch_first;i<g_contexts[context_index].watch_count;i++)
         RenderWatch(g_contexts[context_index].watches[i],watch_ordinal++);
     }
   int display_count=ClampInt(InpMaximumDisplayedSetups,1,5);
   int first=(int)MathMax(0,g_contexts[context_index].setup_count-display_count);
   int ordinal=0;
   for(int i=first;i<g_contexts[context_index].setup_count;i++)
      RenderSetup(g_contexts[context_index],
                  g_contexts[context_index].setups[i],ordinal++);
  }

//+------------------------------------------------------------------+
void CreatePanelRectangle(const string name,const int x,const int y,
                          const int width,const int height)
  {
   if(!ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,InpPanelColor);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,C'42,55,72');
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   SetCommonObjectProperties(name);
  }

//+------------------------------------------------------------------+
void CreatePanelLabel(const string name,const int x,const int y,
                      const string text_value,const color text_color,
                      const int font_size)
  {
   if(!ObjectCreate(0,name,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,font_size);
   ObjectSetInteger(0,name,OBJPROP_COLOR,text_color);
   ObjectSetString(0,name,OBJPROP_TEXT,text_value);
   SetCommonObjectProperties(name);
  }

//+------------------------------------------------------------------+
string CompactState(const SMART_CONTEXT &context)
  {
   if(!context.available || context.status=="DATA WAIT")
      return "DATA WAIT";
   if(context.status=="IDLE") return "SCAN";
   if(context.status=="SNIPER" || context.status=="VIABLE") return "READY";
   if(context.status=="WATCH") return "WATCH";
   return PhaseText(context.phase);
  }

//+------------------------------------------------------------------+
string AuditTooltip(const SMART_CONTEXT &context)
  {
   if(context.testable_count<=0)
      return "No retained ICT setup is testable";
   int t1=(int)MathRound(100.0*context.tp1_hit_count/context.testable_count);
   int t2=(int)MathRound(100.0*context.tp2_hit_count/context.testable_count);
   return StringFormat("ICT model | TP1 %d%% | TP2 %d%% | Sample %d | Stop-first audit",
                       t1,t2,context.testable_count);
  }

//+------------------------------------------------------------------+
color ContextStateColor(const SMART_CONTEXT &context)
  {
   if(!context.available || context.status=="DATA WAIT") return clrGray;
   if(context.status=="SNIPER") return clrLimeGreen;
   if(context.status=="VIABLE") return clrGold;
   return InpNeutralColor;
  }

//+------------------------------------------------------------------+
color NewsStateColor(const string state)
  {
   if(state=="LIVE") return clrTomato;
   if(StringFind(state,"IN ")==0) return clrGold;
   if(state=="CLEAR") return clrLimeGreen;
   return clrGray;
  }

//+------------------------------------------------------------------+
string CompactSession(const string session_name)
  {
   if(session_name=="ASIA BUILD") return "ASIA";
   if(session_name=="LONDON SCAN") return "LONDON";
   if(session_name=="NEW YORK SCAN") return "NEW YORK";
   if(session_name=="OFF HOURS") return "OFF";
   if(StringFind(session_name,"ASIA")>=0) return "ASIA>LON";
   if(StringFind(session_name,"LONDON")>=0) return "LON>NY";
   return "-";
  }

//+------------------------------------------------------------------+
color DirectionColor(const int direction)
  {
   if(direction>0) return InpBullishColor;
   if(direction<0) return InpBearishColor;
   return InpNeutralColor;
  }

//+------------------------------------------------------------------+
void RenderDashboard()
  {
   DeleteObjectsByPrefix(g_object_prefix+"DASH_");
   if(!InpShowDashboard)
      return;
   int x=InpDashboardX;
   int y=InpDashboardY;
   int panel_width=(int)MathMax(760,InpDashboardWidth);
   CreatePanelRectangle(g_object_prefix+"DASH_BG",x,y,panel_width,174);
   CreatePanelLabel(g_object_prefix+"DASH_TITLE",x+14,y+11,
                    "S.M.A.R.T.  |  IRONHAWK CAPITAL",clrWhite,11);
   CreatePanelLabel(g_object_prefix+"DASH_SUB",x+14,y+31,
                    "ICT / SMC SESSION LIQUIDITY EXECUTION MODEL",
                    C'120,145,170',8);
   CreatePanelLabel(g_object_prefix+"DASH_H_SYMBOL",x+14,y+54,
                    "SYMBOL",C'95,110,125',7);
   CreatePanelLabel(g_object_prefix+"DASH_H_SCORE",x+105,y+54,
                    "SCORE",C'95,110,125',7);
   CreatePanelLabel(g_object_prefix+"DASH_H_STATE",x+165,y+54,
                    "PHASE",C'95,110,125',7);
   CreatePanelLabel(g_object_prefix+"DASH_H_BIAS",x+245,y+54,
                    "BIAS",C'95,110,125',7);
   CreatePanelLabel(g_object_prefix+"DASH_H_SESSION",x+325,y+54,
                    "SESSION",C'95,110,125',7);
   CreatePanelLabel(g_object_prefix+"DASH_H_NEWS",x+430,y+54,
                    "MACRO",C'95,110,125',7);
   CreatePanelLabel(g_object_prefix+"DASH_H_RR",x+550,y+54,
                    "R:R",C'95,110,125',7);
   CreatePanelLabel(g_object_prefix+"DASH_H_HIT",x+610,y+54,
                    "T1/T2/N",C'95,110,125',7);
   for(int i=0;i<SMART_SYMBOLS;i++)
     {
      int row_y=y+72+i*24;
      string suffix=IntegerToString(i);
      color score_color=ContextStateColor(g_contexts[i]);
      string symbol=(g_contexts[i].available ? g_contexts[i].symbol : "N/A");
      bool graded=(g_contexts[i].status=="VIABLE" ||
                   g_contexts[i].status=="SNIPER");
      string score=(g_contexts[i].available && graded
                    ? IntegerToString(g_contexts[i].score) : "--");
      string direction=(g_contexts[i].direction==0
                        ? "WAIT" : DirectionText(g_contexts[i].direction));
      string rr=(!g_contexts[i].available ||
                 g_contexts[i].status=="DATA WAIT" ? "--" :
                 g_contexts[i].rr>0.0
                 ? DoubleToString(g_contexts[i].rr,2)
                 : "-");
      string hit_rate="-";
      if(g_contexts[i].available && g_contexts[i].testable_count>0)
        {
         int tp1_rate=(int)MathRound(100.0*g_contexts[i].tp1_hit_count/
                                    g_contexts[i].testable_count);
         int tp2_rate=(int)MathRound(100.0*g_contexts[i].tp2_hit_count/
                                    g_contexts[i].testable_count);
         hit_rate=IntegerToString(tp1_rate)+"/"+
                  IntegerToString(tp2_rate)+"/"+
                  IntegerToString(g_contexts[i].testable_count);
        }
      CreatePanelLabel(g_object_prefix+"DASH_SYMBOL_"+suffix,
                       x+14,row_y,symbol,clrWhite,9);
      CreatePanelLabel(g_object_prefix+"DASH_SCORE_"+suffix,
                       x+105,row_y,score,score_color,9);
      CreatePanelLabel(g_object_prefix+"DASH_STATE_"+suffix,
                       x+165,row_y,CompactState(g_contexts[i]),score_color,9);
      CreatePanelLabel(g_object_prefix+"DASH_BIAS_"+suffix,
                       x+245,row_y,direction,
                       DirectionColor(g_contexts[i].direction),9);
      CreatePanelLabel(g_object_prefix+"DASH_SESSION_"+suffix,
                       x+325,row_y,CompactSession(g_contexts[i].session_name),
                       C'145,160,175',8);
      CreatePanelLabel(g_object_prefix+"DASH_NEWS_"+suffix,
                       x+430,row_y,g_contexts[i].news_state,
                       NewsStateColor(g_contexts[i].news_state),8);
      ObjectSetString(0,g_object_prefix+"DASH_NEWS_"+suffix,OBJPROP_TOOLTIP,
                      g_contexts[i].news_detail);
      CreatePanelLabel(g_object_prefix+"DASH_RR_"+suffix,
                       x+550,row_y,rr,clrWhite,9);
      CreatePanelLabel(g_object_prefix+"DASH_HIT_"+suffix,
                       x+610,row_y,hit_rate,C'145,160,175',8);
      ObjectSetString(0,g_object_prefix+"DASH_HIT_"+suffix,OBJPROP_TOOLTIP,
                      AuditTooltip(g_contexts[i]));
     }
   string footer=StringFormat("%s | %d BARS | CLOSED | ICT/SMC | NEWS %s | SCORE IS NOT PROBABILITY",
                              AnalysisTimeframeText(),
                              ClampInt(InpHistoryBars,250,50000),
                              (InpUseEconomicCalendar ? "ON" : "OFF"));
   CreatePanelLabel(g_object_prefix+"DASH_FOOT",x+14,y+151,footer,
                    C'95,110,125',7);
  }

//+------------------------------------------------------------------+
bool ValidateInputs()
  {
   if(!ValidForwardWindow(InpAsiaStartHour,InpAsiaStartMinute,
                          InpAsiaEndHour,InpAsiaEndMinute))
      return false;
   if(!ValidForwardWindow(InpLondonStartHour,InpLondonStartMinute,
                          InpLondonRangeEndHour,InpLondonRangeEndMinute))
      return false;
   if(!ValidForwardWindow(InpLondonStartHour,InpLondonStartMinute,
                          InpLondonSweepEndHour,InpLondonSweepEndMinute))
      return false;
   int london_range_end=InpLondonRangeEndHour*60+InpLondonRangeEndMinute;
   int london_sweep_end=InpLondonSweepEndHour*60+InpLondonSweepEndMinute;
   if(london_sweep_end>london_range_end)
      return false;
   if(!ValidForwardWindow(InpNewYorkStartHour,InpNewYorkStartMinute,
                          InpNewYorkEndHour,InpNewYorkEndMinute))
      return false;
   if(InpATRPeriod<2 || InpVolumeLookback<5)
      return false;
   if(InpSwingStrength<1 || InpSwingStrength>5 ||
      InpSwingLookback<2*InpSwingStrength+3 || InpSwingLookback>200 ||
      InpMSSBars<1 || InpMSSBars>20 ||
      InpFVGFormationBars<0 || InpFVGFormationBars>10 ||
      InpRetestBars<1 || InpRetestBars>50)
      return false;
   if(InpMinimumSweepATR<=0.0 || InpMinimumDisplacementATR<=0.0 ||
      InpMinimumFVGATR<=0.0 || InpRetestToleranceATR<0.0 ||
      InpStopBufferATR<=0.0 ||
      InpMinimumRiskATR<=0.0 || InpMaximumRiskATR<=InpMinimumRiskATR)
      return false;
   if(InpTP1RiskMultiple<=0.0 || InpTP2RiskMultiple<=0.0 ||
      InpTP1RiskMultiple>=InpTP2RiskMultiple ||
      InpMinimumProjectionRR<=InpTP1RiskMultiple ||
      InpTP2RiskMultiple<InpMinimumProjectionRR)
      return false;
   if(InpDashboardSetupAgeBars<1 || InpDashboardSetupAgeBars>5000)
      return false;
   if(InpProjectionBars<1 || InpProjectionBars>1000 ||
      InpMinimumChartProjectionBars<1 || InpMinimumChartProjectionBars>100)
      return false;
   if(InpMaximumDisplayedWatches<1 || InpMaximumDisplayedWatches>12)
      return false;
   if(InpMaximumDisplayedSetups<1 || InpMaximumDisplayedSetups>5)
      return false;
   if(InpViableThreshold<70 || InpViableThreshold>=InpSniperThreshold)
      return false;
   if(InpSniperThreshold>100 || InpMinimumProjectionRR<=0.0)
      return false;
   if(InpTimerSeconds<1 || InpHistoryBars<250 || InpHistoryBars>50000)
      return false;
   if(InpMinimumNewsImportance<1 || InpMinimumNewsImportance>3 ||
      InpNewsMinutesBefore<0 || InpNewsMinutesBefore>1440 ||
      InpNewsMinutesAfter<0 || InpNewsMinutesAfter>1440)
      return false;
   if(InpServerUTCOffsetMinutes!=9999 &&
      MathAbs(InpServerUTCOffsetMinutes)>1440)
      return false;
   return true;
  }

//+------------------------------------------------------------------+
void ConfigureContext(const int index,const string requested)
  {
   g_contexts[index].requested_symbol=requested;
   g_contexts[index].symbol=ResolveSymbol(requested);
   g_contexts[index].available=(g_contexts[index].symbol!="");
   g_contexts[index].initialized=false;
   g_contexts[index].last_closed_bar=0;
   g_contexts[index].last_alerted_id="";
   ResetAnalysisState(g_contexts[index]);
   g_contexts[index].news_state=(InpUseEconomicCalendar ? "LOADING" : "OFF");
   g_contexts[index].news_name="";
   g_contexts[index].news_time=0;
   g_contexts[index].news_importance=0;
   g_contexts[index].news_detail=(InpUseEconomicCalendar
                                  ? "Waiting for native calendar"
                                  : "Economic calendar disabled by input");
   g_contexts[index].last_news_refresh=0;
   for(int i=0;i<index;i++)
     {
      if(g_contexts[index].symbol!="" &&
         UpperCopy(g_contexts[index].symbol)==UpperCopy(g_contexts[i].symbol))
        {
         g_contexts[index].available=false;
         g_contexts[index].status="DATA WAIT";
         g_contexts[index].note="DUPLICATE SYMBOL INPUT";
         return;
        }
     }
   if(!g_contexts[index].available)
     {
      g_contexts[index].status="DATA WAIT";
      g_contexts[index].note="SYMBOL NOT FOUND";
     }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!ValidateInputs())
     {
      Print("S.M.A.R.T.: invalid input configuration");
      return INIT_PARAMETERS_INCORRECT;
     }
   IndicatorSetString(INDICATOR_SHORTNAME,"S.M.A.R.T. ICT/SMC V3");
   ConfigureContext(0,InpSymbol1);
   ConfigureContext(1,InpSymbol2);
   ConfigureContext(2,InpSymbol3);

   for(int i=0;i<SMART_SYMBOLS;i++)
      ProcessSymbol(i,true);
   RenderChartAnalysis();
   RenderDashboard();
   ChartRedraw(0);
   EventSetTimer(InpTimerSeconds);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   DeleteObjectsByPrefix(g_object_prefix);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   ProcessSymbol(g_next_symbol,false);
   g_next_symbol=(g_next_symbol+1)%SMART_SYMBOLS;
   RenderChartAnalysis();
   RenderDashboard();
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],
                const double &high[],const double &low[],
                const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
  {
   return rates_total;
  }
