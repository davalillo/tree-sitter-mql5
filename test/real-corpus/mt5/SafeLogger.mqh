//+------------------------------------------------------------------+
//|                                                 SafeLogger.mqh   |
//|  Append to a file shared by SEVERAL EAs, without losing a line.  |
//|                                                                  |
//|  THE PROBLEM, which took me days to see:                         |
//|                                                                  |
//|  Four EAs writing to the same file, all of them like this:       |
//|                                                                  |
//|      int h = FileOpen(file, FILE_READ|FILE_WRITE|FILE_TXT|       |
//|                             FILE_SHARE_READ|FILE_SHARE_WRITE);   |
//|      FileSeek(h, 0, SEEK_END);                                   |
//|      FileWrite(h, line);                                         |
//|      FileClose(h);                                               |
//|                                                                  |
//|  Looks correct. Every FileOpen returns success. Not one error in |
//|  the log. And the lines VANISH.                                  |
//|                                                                  |
//|  Reason: FILE_SHARE_WRITE lets all four open at the same time.   |
//|  All four call FileSeek(SEEK_END) and get THE SAME offset,       |
//|  because none has written yet. All four write at the same        |
//|  position. Whoever closes last wins. Three lines vanish silently.|
//|                                                                  |
//|  In my case: 12 events expected, 8 in the file. Without a single |
//|  error to investigate.                                           |
//|                                                                  |
//|  THE FIX: open EXCLUSIVELY (no FILE_SHARE_WRITE) and retry while |
//|  another EA holds the file. Whoever fails waits; nobody          |
//|  overwrites anybody.                                             |
//|                                                                  |
//|  And — just as important — SHOUT when the retries run out. A log |
//|  that fails silently is worse than no log at all, because you    |
//|  trust it. It was the shout that revealed the defect above: it   |
//|  proved the problem BY ABSENCE, when FileOpen succeeded and the  |
//|  line did not show up.                                           |
//|                                                                  |
//|  About the timestamp: use TimeLocal(), not TimeCurrent(). The    |
//|  server clock freezes at the last tick and can STEP BACKWARDS —  |
//|  a record stamped with it comes out of order. See the            |
//|  "ClockDiagnostic" script for the demonstration.                 |
//+------------------------------------------------------------------+
//| Joao Prata Silva Yglesias                                        |
//| https://www.mql5.com/en/users/jotayglesias                       |
//+------------------------------------------------------------------+
#ifndef SAFE_LOGGER_MQH
#define SAFE_LOGGER_MQH

#define SAFELOG_RETRIES  8      // 8 x 40ms = 320ms of patience
#define SAFELOG_WAIT_MS  40

//+------------------------------------------------------------------+
//| Appends one line to the file. Returns false if it could NOT —    |
//| and in that case it has already shouted in the log.              |
//|                                                                  |
//| `fields` comes in as ready-made text; the function prepends the  |
//| timestamp and the symbol.                                        |
//+------------------------------------------------------------------+
bool SafeLogWrite(const string file, const string fields)
  {
   string line = StringFormat("%s;%s;%s",
                              TimeToString(TimeLocal(), TIME_DATE|TIME_SECONDS),
                              _Symbol, fields);

   for(int attempt = 0; attempt < SAFELOG_RETRIES; attempt++)
     {
      // EXCLUSIVE: no FILE_SHARE_WRITE. If another EA is inside, this
      // FileOpen FAILS — which is exactly what we want.
      int h = FileOpen(file, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
      if(h != INVALID_HANDLE)
        {
         FileSeek(h, 0, SEEK_END);
         FileWrite(h, line);
         FileFlush(h);
         FileClose(h);
         return(true);
        }
      Sleep(SAFELOG_WAIT_MS);
     }

   // THE SHOUT. Without it the failure is invisible — and an invisible log is
   // the worst kind of defect, because you keep trusting the file.
   PrintFormat("[SafeLog] FAILED TO LOG after %d attempts (error %d). "
               "LINE LOST: %s", SAFELOG_RETRIES, GetLastError(), line);
   ResetLastError();
   return(false);
  }

//+------------------------------------------------------------------+
//| Writes the header once, if the file does not exist yet.          |
//+------------------------------------------------------------------+
bool SafeLogHeader(const string file, const string header)
  {
   if(FileIsExist(file)) return(true);
   int h = FileOpen(file, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(h == INVALID_HANDLE)
     {
      PrintFormat("[SafeLog] could not create %s (error %d)", file, GetLastError());
      ResetLastError();
      return(false);
     }
   FileWrite(h, header);
   FileClose(h);
   return(true);
  }

#endif // SAFE_LOGGER_MQH
//+------------------------------------------------------------------+
