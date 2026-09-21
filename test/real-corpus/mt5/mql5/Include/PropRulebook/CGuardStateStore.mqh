//+------------------------------------------------------------------+
//|                                             CGuardStateStore.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Persists and restores the guard's cross-restart     |
//|               key/value state through a checksummed, atomically   |
//|               replaced terminal file.                             |
//| Failure mode: A guard that keeps its state in RAM only: a VPS     |
//|               reboot, a terminal update or a simple chart reload  |
//|               refills the consumed drawdown budget. The guard     |
//|               comes back believing the account has lost nothing,  |
//|               re-anchors at the depleted balance and happily      |
//|               allows the whole allowance to be lost again. On a   |
//|               funded account that is the difference between one   |
//|               bad day and a failed challenge.                     |
//|                                                                   |
//|               Design choices, and why:                            |
//|                 - A FILE, not a GlobalVariable. Terminal global   |
//|                   variables are a flat, shared namespace with a   |
//|                   four-week expiry; two EAs on two accounts would |
//|                   collide, and a month of inactivity would erase  |
//|                   the anchor.                                     |
//|                 - One file per ACCOUNT LOGIN by default, so the   |
//|                   same terminal can guard several accounts        |
//|                   without their states overwriting each other.    |
//|                 - Written to a temporary name and then moved over |
//|                   the real one, so a crash mid-write leaves the   |
//|                   previous good state intact instead of a         |
//|                   truncated file.                                 |
//|                 - An FNV-1a checksum over the payload. A file     |
//|                   that fails the header, the version, the record  |
//|                   count or the checksum is REJECTED WHOLE:        |
//|                   Load() returns false and the caller falls back  |
//|                   to a fresh anchor. Half-loaded state is worse   |
//|                   than no state, because it looks valid.          |
//| Dependencies: none                                                |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"


#define PROP_STATE_MAGIC   "PFDSTATE"
#define PROP_STATE_VERSION 1

//+------------------------------------------------------------------+
//| Checksummed key/value persistence.                               |
//+------------------------------------------------------------------+
class CGuardStateStore
{
private:
   string m_keys[];
   string m_values[];
   string m_file_name;
   int    m_common_flag;     // FILE_COMMON or 0
   bool   m_ready;
   string m_last_error;

   int Find(const string key) const
   {
      for(int i = 0; i < ArraySize(m_keys); i++)
         if(m_keys[i] == key)
            return i;
      return -1;
   }

   //--- FNV-1a over the payload. Cheap, dependency-free, and enough to
   //--- catch the truncation and partial-write cases this guards against.
   uint Checksum(const string payload) const
   {
      uint hash = 0x811C9DC5;   // FNV-1a 32-bit offset basis
      int  len  = StringLen(payload);
      for(int i = 0; i < len; i++)
      {
         hash ^= (uint)StringGetCharacter(payload, i);
         hash *= 0x01000193;   // FNV-1a 32-bit prime
      }
      return hash;
   }

   string BuildPayload() const
   {
      string payload = "";
      for(int i = 0; i < ArraySize(m_keys); i++)
         payload += m_keys[i] + "=" + m_values[i] + "\n";
      return payload;
   }

public:
   CGuardStateStore()
      : m_file_name(""), m_common_flag(0), m_ready(false), m_last_error("") {}

   //+---------------------------------------------------------------+
   //| file_name "" resolves to PropRulebook_<login>.dat, which   |
   //| is what keeps two guarded accounts from sharing one state.     |
   //+---------------------------------------------------------------+
   bool Init(const string file_name, const bool common_folder)
   {
      long login = AccountInfoInteger(ACCOUNT_LOGIN);

      m_file_name = (StringLen(file_name) > 0)
                    ? file_name
                    : StringFormat("PropRulebook_%I64d.dat", login);

      m_common_flag = common_folder ? FILE_COMMON : 0;
      m_ready       = true;
      m_last_error  = "";
      return true;
   }

   bool   IsReady()   const { return m_ready; }
   string FileName()  const { return m_file_name; }
   string LastError() const { return m_last_error; }
   int    Count()     const { return ArraySize(m_keys); }

   void ClearAll()
   {
      ArrayFree(m_keys);
      ArrayFree(m_values);
   }

   //+---------------------------------------------------------------+
   //| Values must not contain '=' or a newline: the format is one    |
   //| record per line and the first '=' separates key from value.    |
   //| Every Serialize() in this package respects that.               |
   //+---------------------------------------------------------------+
   bool Set(const string key, const string value)
   {
      if(StringLen(key) == 0 || StringFind(key, "=") >= 0)
      {
         m_last_error = "invalid key: " + key;
         return false;
      }
      if(StringFind(value, "\n") >= 0 || StringFind(value, "\r") >= 0)
      {
         m_last_error = "value for '" + key + "' contains a line break";
         return false;
      }

      int pos = Find(key);
      if(pos >= 0)
      {
         m_values[pos] = value;
         return true;
      }

      int n = ArraySize(m_keys);
      if(ArrayResize(m_keys, n + 1) != n + 1 || ArrayResize(m_values, n + 1) != n + 1)
      {
         m_last_error = "could not grow the state table";
         return false;
      }
      m_keys[n]   = key;
      m_values[n] = value;
      return true;
   }

   bool SetDouble(const string key, const double value)
   {
      return Set(key, StringFormat("%.8f", value));
   }

   bool SetLong(const string key, const long value)
   {
      return Set(key, StringFormat("%I64d", value));
   }

   bool SetBool(const string key, const bool value)
   {
      return Set(key, (value ? "1" : "0"));
   }

   bool Has(const string key) const { return (Find(key) >= 0); }

   string Get(const string key, const string fallback) const
   {
      int pos = Find(key);
      return (pos >= 0) ? m_values[pos] : fallback;
   }

   double GetDouble(const string key, const double fallback) const
   {
      int pos = Find(key);
      return (pos >= 0) ? StringToDouble(m_values[pos]) : fallback;
   }

   long GetLong(const string key, const long fallback) const
   {
      int pos = Find(key);
      return (pos >= 0) ? StringToInteger(m_values[pos]) : fallback;
   }

   bool GetBool(const string key, const bool fallback) const
   {
      int pos = Find(key);
      return (pos >= 0) ? (m_values[pos] == "1") : fallback;
   }

   bool KeyAt(const int i, string &key, string &value) const
   {
      if(i < 0 || i >= ArraySize(m_keys))
         return false;
      key   = m_keys[i];
      value = m_values[i];
      return true;
   }

   //+---------------------------------------------------------------+
   //| Atomic-by-replacement save.                                    |
   //|                                                                |
   //| Header line: MAGIC|VERSION|RECORD_COUNT|CHECKSUM               |
   //| Then one key=value line per record.                            |
   //+---------------------------------------------------------------+
   bool Save()
   {
      if(!m_ready)
      {
         m_last_error = "store not initialised";
         return false;
      }

      string payload  = BuildPayload();
      uint   checksum = Checksum(payload);
      string tmp_name = m_file_name + ".tmp";

      int handle = FileOpen(tmp_name,
                            FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | m_common_flag);
      if(handle == INVALID_HANDLE)
      {
         m_last_error = StringFormat("FileOpen('%s') for write failed, error %d",
                                     tmp_name, GetLastError());
         Print("CGuardStateStore: " + m_last_error);
         return false;
      }

      FileWriteString(handle, StringFormat("%s|%d|%d|%u\n",
                                           PROP_STATE_MAGIC, PROP_STATE_VERSION,
                                           ArraySize(m_keys), checksum));
      FileWriteString(handle, payload);
      FileFlush(handle);
      FileClose(handle);

      //--- Replace the live file only once the temporary one is complete and
      //--- closed. FILE_REWRITE overwrites in one step, so the previous good
      //--- state is never deleted before its replacement exists.
      if(!FileMove(tmp_name, m_common_flag, m_file_name, FILE_REWRITE))
      {
         m_last_error = StringFormat("FileMove('%s' -> '%s') failed, error %d",
                                     tmp_name, m_file_name, GetLastError());
         Print("CGuardStateStore: " + m_last_error);
         return false;
      }

      return true;
   }

   //+---------------------------------------------------------------+
   //| Loads and validates. Returns false on ANY inconsistency, with  |
   //| the in-memory table emptied, so the caller can fall back to a  |
   //| fresh anchor instead of half-trusting a damaged file.          |
   //+---------------------------------------------------------------+
   bool Load()
   {
      ClearAll();

      if(!m_ready)
      {
         m_last_error = "store not initialised";
         return false;
      }

      if(!FileIsExist(m_file_name, m_common_flag))
      {
         m_last_error = "no state file yet";
         return false;
      }

      int handle = FileOpen(m_file_name,
                            FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | m_common_flag);
      if(handle == INVALID_HANDLE)
      {
         m_last_error = StringFormat("FileOpen('%s') for read failed, error %d",
                                     m_file_name, GetLastError());
         return false;
      }

      string header = FileReadString(handle);
      string head[];
      if(StringSplit(header, (ushort)'|', head) != 4)
      {
         FileClose(handle);
         m_last_error = "corrupt state file: bad header";
         return false;
      }

      if(head[0] != PROP_STATE_MAGIC)
      {
         FileClose(handle);
         m_last_error = "corrupt state file: wrong magic";
         return false;
      }
      if((int)StringToInteger(head[1]) != PROP_STATE_VERSION)
      {
         FileClose(handle);
         m_last_error = "state file written by a different version";
         return false;
      }

      int  expected_count    = (int)StringToInteger(head[2]);
      uint expected_checksum = (uint)StringToInteger(head[3]);

      string payload = "";
      int    read    = 0;

      while(!FileIsEnding(handle))
      {
         string line = FileReadString(handle);
         if(StringLen(line) == 0)
            continue;

         int sep = StringFind(line, "=");
         if(sep <= 0)
         {
            FileClose(handle);
            ClearAll();
            m_last_error = "corrupt state file: record without a separator";
            return false;
         }

         string key   = StringSubstr(line, 0, sep);
         string value = StringSubstr(line, sep + 1);

         int n = ArraySize(m_keys);
         if(ArrayResize(m_keys, n + 1) != n + 1 || ArrayResize(m_values, n + 1) != n + 1)
         {
            FileClose(handle);
            ClearAll();
            m_last_error = "out of memory while loading state";
            return false;
         }
         m_keys[n]   = key;
         m_values[n] = value;

         payload += line + "\n";
         read++;
      }

      FileClose(handle);

      if(read != expected_count)
      {
         ClearAll();
         m_last_error = StringFormat("corrupt state file: %d records, header says %d "
                                     "(truncated?)", read, expected_count);
         Print("CGuardStateStore: " + m_last_error);
         return false;
      }

      if(Checksum(payload) != expected_checksum)
      {
         ClearAll();
         m_last_error = "corrupt state file: checksum mismatch";
         Print("CGuardStateStore: " + m_last_error);
         return false;
      }

      return true;
   }

   //--- removes the persisted state entirely (used by ResetChallenge())
   bool Delete()
   {
      ClearAll();
      if(!m_ready)
         return false;
      if(!FileIsExist(m_file_name, m_common_flag))
         return true;
      return FileDelete(m_file_name, m_common_flag);
   }
};
//+------------------------------------------------------------------+
