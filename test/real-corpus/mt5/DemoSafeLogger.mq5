//+------------------------------------------------------------------+
//|                                             DemoSafeLogger.mq5   |
//|  Proves the defect and proves the fix, in your own terminal.     |
//|                                                                  |
//|  How to reproduce the loss of lines for real:                    |
//|                                                                  |
//|   1. Compile this script.                                        |
//|   2. Open FOUR charts.                                           |
//|   3. Drag the script onto all four, as fast as you can, with     |
//|      InpSafeMode OFF.                                            |
//|   4. Open MQL5\Files\demo_log.csv and count the lines.           |
//|                                                                  |
//|  Each run writes InpLines lines. Four runs should give           |
//|  4 x InpLines. With InpSafeMode off you will find FEWER — and no |
//|  error in the log, which is what makes this defect so hard to    |
//|  find.                                                           |
//|                                                                  |
//|  Repeat with InpSafeMode ON: the count closes.                   |
//|                                                                  |
//|  (Running on a single chart reproduces nothing: the defect needs |
//|  two simultaneous writers. And that is the point — it does not   |
//|  show up in isolated testing, only in production.)               |
//+------------------------------------------------------------------+
#property copyright "Joao Prata Silva Yglesias"
#property link      "https://www.mql5.com/en/users/jotayglesias"
#property version   "1.00"
#property script_show_inputs

#include "SafeLogger.mqh"

input string InpFile     = "demo_log.csv";  // Output file
input int    InpLines    = 200;             // Lines to write
input bool   InpSafeMode = true;            // true = exclusive | false = the wrong way

//+------------------------------------------------------------------+
//| THE WRONG WAY, reproduced on purpose for comparison.             |
//| FILE_SHARE_WRITE lets several open together; all of them get the |
//| same SEEK_END; the last one to close erases the others.          |
//+------------------------------------------------------------------+
bool UnsafeWrite(const string file, const string fields)
  {
   string line = StringFormat("%s;%s;%s",
                              TimeToString(TimeLocal(), TIME_DATE|TIME_SECONDS),
                              _Symbol, fields);
   int h = FileOpen(file, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|
                          FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return(false);        // almost never happens — that is the problem
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, line);
   FileClose(h);
   return(true);
  }

//+------------------------------------------------------------------+
int CountLines(const string file)
  {
   int h = FileOpen(file, FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return(-1);
   int n = 0;
   while(!FileIsEnding(h)) { FileReadString(h); n++; }
   FileClose(h);
   return(n);
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   SafeLogHeader(InpFile, "time;symbol;source;sequence");

   int before = CountLines(InpFile);
   int ok = 0, failed = 0;
   ulong t0 = GetMicrosecondCount();

   for(int i = 0; i < InpLines; i++)
     {
      string fields = StringFormat("%s;%d", ChartID() == 0 ? "?" : IntegerToString(ChartID()), i);
      bool r = InpSafeMode ? SafeLogWrite(InpFile, fields)
                           : UnsafeWrite(InpFile, fields);
      if(r) ok++; else failed++;
     }

   double ms = (GetMicrosecondCount() - t0) / 1000.0;
   int after = CountLines(InpFile);

   Print("================================================");
   PrintFormat("mode: %s", InpSafeMode ? "SAFE (exclusive append)"
                                       : "UNSAFE (FILE_SHARE_WRITE)");
   PrintFormat("calls that returned success: %d   declared failures: %d", ok, failed);
   PrintFormat("lines in the file: %d -> %d   (gain of %d)", before, after, after - before);
   PrintFormat("time: %.0f ms", ms);

   if(after - before < ok)
      PrintFormat(">>> %d LINE(S) LOST with a successful FileOpen. "
                  "That is the defect.", ok - (after - before));
   else
      Print(">>> no line lost in this run.");

   if(!InpSafeMode)
      Print("To see the loss, run on 4 charts at the same time. On a single one "
            "there is no contention and the defect does not show up.");
   Print("================================================");
  }
//+------------------------------------------------------------------+
