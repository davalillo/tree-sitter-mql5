//+------------------------------------------------------------------+
//|                                    CProtectiveActionExecutor.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Closes open positions and removes pending orders    |
//|               with per-request retcode inspection, bounded        |
//|               retries on recoverable failures, and an explicit    |
//|               flat-state verification before reporting success.   |
//| Failure mode: A fire-and-forget CloseAll() that sends close       |
//|               requests and reports the account "protected"        |
//|               without looking at a single return value invites    |
//|               the most dangerous failure mode software like this  |
//|               can have: a false all-clear. A requote, an off-     |
//|               quotes reply, or a closed market can leave every    |
//|               position open while the journal announces           |
//|               protection. Three things fix it here, and all three |
//|               are required:                                       |
//|                                                                   |
//|                 1. every OrderSend() return AND the resulting     |
//|                    res.retcode are inspected (OrderSend()==true   |
//|                    only means the request was accepted for        |
//|                    processing, never that it filled);             |
//|                 2. recoverable retcodes (requote, price changed,  |
//|                    off quotes, rejection, connection) are retried |
//|                    with a refreshed price under a bounded budget, |
//|                    while a permanent one (market closed, trading  |
//|                    disabled) stops immediately instead of         |
//|                    spinning;                                      |
//|                 3. success is returned only after counting the    |
//|                    relevant positions again and finding zero.     |
//|                                                                   |
//|               When the account cannot be flattened, this class    |
//|               says so. CPropRulebook::IsProtectionSettled()   |
//|               then stays false, and the caller keeps being told   |
//|               the truth.                                          |
//| Dependencies: PropRuleVerdict.mqh                                 |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

#include "PropRuleVerdict.mqh"

//+------------------------------------------------------------------+
//| Retcode-checked flattener.                                       |
//+------------------------------------------------------------------+
class CProtectiveActionExecutor
{
private:
   ulong  m_magic;
   bool   m_restrict_to_magic;
   int    m_rounds;              // full sweeps per call
   int    m_retries_per_position;
   int    m_deviation;
   bool   m_ready;

   //--- outcome of the last FlattenAll() call
   bool   m_last_success;
   uint   m_last_retcode;
   int    m_last_closed;
   int    m_last_failed;
   int    m_last_remaining;
   string m_last_report;

   //+---------------------------------------------------------------+
   //| Retcodes worth trying again. Everything else is either final   |
   //| success or a permanent condition that retrying cannot fix.     |
   //+---------------------------------------------------------------+
   bool IsRetryable(const uint retcode) const
   {
      switch(retcode)
      {
         case TRADE_RETCODE_REQUOTE:
         case TRADE_RETCODE_PRICE_CHANGED:
         case TRADE_RETCODE_PRICE_OFF:
         case TRADE_RETCODE_REJECT:
         case TRADE_RETCODE_ERROR:
         case TRADE_RETCODE_TIMEOUT:
         case TRADE_RETCODE_CONNECTION:
         case TRADE_RETCODE_TOO_MANY_REQUESTS:
         case TRADE_RETCODE_ORDER_CHANGED:
         case TRADE_RETCODE_DONE_PARTIAL:
            return true;
         default:
            return false;
      }
   }

   bool IsSuccess(const uint retcode) const
   {
      return (retcode == TRADE_RETCODE_DONE ||
              retcode == TRADE_RETCODE_PLACED ||
              retcode == TRADE_RETCODE_DONE_PARTIAL);
   }

   //--- filling mode the symbol actually supports
   ENUM_ORDER_TYPE_FILLING PickFilling(const string symbol) const
   {
      long modes = 0;
      if(!SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE, modes))
         return ORDER_FILLING_IOC;

      if((modes & SYMBOL_FILLING_FOK) != 0)
         return ORDER_FILLING_FOK;
      if((modes & SYMBOL_FILLING_IOC) != 0)
         return ORDER_FILLING_IOC;
      return ORDER_FILLING_RETURN;
   }

   bool Owns(const ulong position_magic) const
   {
      if(!m_restrict_to_magic)
         return true;
      return (position_magic == m_magic);
   }

   //+---------------------------------------------------------------+
   //| Closes ONE position, retrying while the broker keeps replying  |
   //| with a recoverable retcode. Contains no Sleep(): the price is  |
   //| re-read from the symbol before every attempt, which is the     |
   //| part that actually matters after a requote.                    |
   //+---------------------------------------------------------------+
   bool ClosePositionWithRetry(const ulong ticket)
   {
      for(int attempt = 1; attempt <= m_retries_per_position; attempt++)
      {
         if(!PositionSelectByTicket(ticket))
            return true;              // gone already: that is the desired state

         string symbol = PositionGetString(POSITION_SYMBOL);
         double volume = PositionGetDouble(POSITION_VOLUME);
         long   type   = PositionGetInteger(POSITION_TYPE);

         MqlTradeRequest req;
         MqlTradeResult  res;
         ZeroMemory(req);
         ZeroMemory(res);

         req.action       = TRADE_ACTION_DEAL;
         req.position     = ticket;
         req.symbol       = symbol;
         req.volume       = volume;
         req.type         = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         req.price        = (req.type == ORDER_TYPE_SELL)
                            ? SymbolInfoDouble(symbol, SYMBOL_BID)
                            : SymbolInfoDouble(symbol, SYMBOL_ASK);
         req.deviation    = (ulong)m_deviation;
         req.magic        = m_magic;
         req.type_filling = PickFilling(symbol);
         req.comment      = "PFD protective close";

         bool sent      = OrderSend(req, res);
         m_last_retcode = res.retcode;

         //--- OrderSend() == true only means the request was accepted for
         //--- processing. The retcode is the part that says what happened.
         if(sent && IsSuccess(res.retcode))
         {
            if(res.retcode == TRADE_RETCODE_DONE_PARTIAL)
            {
               PrintFormat("CProtectiveActionExecutor: partial close on #%I64u "
                           "(%.2f of %.2f), continuing", ticket, res.volume, volume);
               continue;              // loop again for the remainder
            }
            return true;
         }

         if(!IsRetryable(res.retcode))
         {
            PrintFormat("CProtectiveActionExecutor: close of #%I64u failed permanently, "
                        "retcode %u (%s), last error %d",
                        ticket, res.retcode, res.comment, GetLastError());
            return false;
         }

         PrintFormat("CProtectiveActionExecutor: close of #%I64u returned retcode %u, "
                     "retry %d of %d", ticket, res.retcode, attempt, m_retries_per_position);
      }

      PrintFormat("CProtectiveActionExecutor: close of #%I64u gave up after %d retries "
                  "(last retcode %u)", ticket, m_retries_per_position, m_last_retcode);
      return false;
   }

   bool DeleteOrderWithRetry(const ulong ticket)
   {
      for(int attempt = 1; attempt <= m_retries_per_position; attempt++)
      {
         if(!OrderSelect(ticket))
            return true;

         MqlTradeRequest req;
         MqlTradeResult  res;
         ZeroMemory(req);
         ZeroMemory(res);

         req.action = TRADE_ACTION_REMOVE;
         req.order  = ticket;
         req.magic  = m_magic;

         bool sent      = OrderSend(req, res);
         m_last_retcode = res.retcode;

         if(sent && IsSuccess(res.retcode))
            return true;

         if(!IsRetryable(res.retcode))
         {
            PrintFormat("CProtectiveActionExecutor: delete of order #%I64u failed "
                        "permanently, retcode %u", ticket, res.retcode);
            return false;
         }
      }
      return false;
   }

public:
   CProtectiveActionExecutor()
      : m_magic(0), m_restrict_to_magic(false), m_rounds(3),
        m_retries_per_position(3), m_deviation(20), m_ready(false),
        m_last_success(true), m_last_retcode(0), m_last_closed(0),
        m_last_failed(0), m_last_remaining(0), m_last_report("") {}

   bool Init(const ulong magic, const bool restrict_to_magic,
             const int rounds, const int retries_per_position, const int deviation_points)
   {
      if(rounds <= 0 || retries_per_position <= 0)
      {
         Print("CProtectiveActionExecutor::Init failed: rounds and retries must be positive");
         return false;
      }
      if(deviation_points < 0)
      {
         Print("CProtectiveActionExecutor::Init failed: deviation cannot be negative");
         return false;
      }

      m_magic                = magic;
      m_restrict_to_magic    = restrict_to_magic;
      m_rounds               = rounds;
      m_retries_per_position = retries_per_position;
      m_deviation            = deviation_points;
      m_last_success         = true;
      m_ready                = true;
      return true;
   }

   bool   IsReady()       const { return m_ready; }
   bool   LastSuccess()   const { return m_last_success; }
   uint   LastRetcode()   const { return m_last_retcode; }
   int    LastClosed()    const { return m_last_closed; }
   int    LastFailed()    const { return m_last_failed; }
   int    LastRemaining() const { return m_last_remaining; }
   string LastReport()    const { return m_last_report; }

   //+---------------------------------------------------------------+
   //| Counts the positions this guard is responsible for. This is    |
   //| the ONLY definition of "flat" the class accepts.               |
   //+---------------------------------------------------------------+
   int CountRelevantPositions() const
   {
      int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(!PositionSelectByTicket(ticket))
            continue;
         if(!Owns((ulong)PositionGetInteger(POSITION_MAGIC)))
            continue;
         n++;
      }
      return n;
   }

   int CountRelevantOrders() const
   {
      int n = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0)
            continue;
         if(!Owns((ulong)OrderGetInteger(ORDER_MAGIC)))
            continue;
         n++;
      }
      return n;
   }

   bool IsFlat() const { return (CountRelevantPositions() == 0); }

   //+---------------------------------------------------------------+
   //| Closes everything relevant, then VERIFIES.                     |
   //|                                                                |
   //| Returns true only when the post-sweep count of relevant        |
   //| positions is zero. A false return with remaining > 0 is the    |
   //| honest answer a fire-and-forget close routine never gives.     |
   //+---------------------------------------------------------------+
   bool FlattenAll(const string reason)
   {
      m_last_closed  = 0;
      m_last_failed  = 0;
      m_last_retcode = 0;

      if(!m_ready)
      {
         m_last_success = false;
         m_last_report  = "executor not initialised";
         return false;
      }

      int before = CountRelevantPositions();
      if(before == 0)
      {
         m_last_success   = true;
         m_last_remaining = 0;
         m_last_report    = "already flat";
         return true;
      }

      PrintFormat("CProtectiveActionExecutor: flattening %d position(s) -- %s",
                  before, reason);

      for(int round = 1; round <= m_rounds; round++)
      {
         //--- snapshot the ticket list first: closing inside the enumeration
         //--- shifts the indices under our feet
         ulong tickets[];
         int   total = PositionsTotal();
         ArrayResize(tickets, 0);

         for(int i = total - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0)
               continue;
            if(!PositionSelectByTicket(ticket))
               continue;
            if(!Owns((ulong)PositionGetInteger(POSITION_MAGIC)))
               continue;

            int n = ArraySize(tickets);
            if(ArrayResize(tickets, n + 1) == n + 1)
               tickets[n] = ticket;
         }

         for(int i = 0; i < ArraySize(tickets); i++)
         {
            if(ClosePositionWithRetry(tickets[i]))
               m_last_closed++;
            else
               m_last_failed++;
         }

         //--- verification, every round
         if(CountRelevantPositions() == 0)
            break;
      }

      m_last_remaining = CountRelevantPositions();
      m_last_success   = (m_last_remaining == 0);

      if(m_last_success)
      {
         m_last_report = StringFormat("flat verified: %d closed, 0 remaining (%s)",
                                      m_last_closed, reason);
         Print("CProtectiveActionExecutor: " + m_last_report);
      }
      else
      {
         m_last_report = StringFormat("NOT PROTECTED: %d closed, %d failed, %d still open "
                                      "(last retcode %u) -- %s",
                                      m_last_closed, m_last_failed, m_last_remaining,
                                      m_last_retcode, reason);
         Print("CProtectiveActionExecutor: " + m_last_report);
      }

      return m_last_success;
   }

   //+---------------------------------------------------------------+
   //| Removes the relevant pending orders, same retcode discipline.  |
   //+---------------------------------------------------------------+
   bool DeletePendingOrders(const string reason)
   {
      if(!m_ready)
         return false;

      ulong tickets[];
      ArrayResize(tickets, 0);

      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0)
            continue;
         if(!Owns((ulong)OrderGetInteger(ORDER_MAGIC)))
            continue;

         int n = ArraySize(tickets);
         if(ArrayResize(tickets, n + 1) == n + 1)
            tickets[n] = ticket;
      }

      if(ArraySize(tickets) == 0)
         return true;

      PrintFormat("CProtectiveActionExecutor: removing %d pending order(s) -- %s",
                  ArraySize(tickets), reason);

      for(int i = 0; i < ArraySize(tickets); i++)
         DeleteOrderWithRetry(tickets[i]);

      return (CountRelevantOrders() == 0);
   }
};
//+------------------------------------------------------------------+
