//+------------------------------------------------------------------+
//|                                              ContractSizer.mqh   |
//|  Contract ladder by capital, with a floor and a breaker.         |
//|                                                                  |
//|  Three protections that do DIFFERENT things — and confusing them |
//|  is the reason behind so many wiped-out accounts:                |
//|                                                                  |
//|   1. LADDER    how many contracts the balance allows. ALWAYS A   |
//|                CAP, even with manual lot sizing. Nobody trades   |
//|                above what the capital supports, neither by       |
//|                mistake nor by choice.                            |
//|   2. FLOOR     below the minimum capital it does not trade; a new|
//|                deposit is required. Protects a small account well|
//|                and a large one badly, because it is absolute —   |
//|                hence the third one.                              |
//|   3. BREAKER   stops at X% below the PEAK, at any account size.  |
//|                The floor protects the minimum; this protects the |
//|                size.                                             |
//|                                                                  |
//|  WHAT THIS CLASS SOLVES AND ALMOST NO OTHER ONE DOES:            |
//|                                                                  |
//|  A DEPOSIT IS NOT PROFIT, AND A WITHDRAWAL IS NOT A LOSS.        |
//|                                                                  |
//|  The breaker measures the drop against the balance peak. Without |
//|  treatment, a deposit made DURING a drawdown lifts the balance,  |
//|  lifts the peak with it, and the breaker stops seeing the drop in|
//|  progress — the protection vanishes exactly when it would help.  |
//|  Here deposits and withdrawals shift the peak by the same amount,|
//|  and the drawdown keeps measuring only what trading did.         |
//|                                                                  |
//|  And the peak is PERSISTED TO A FILE: a breaker that forgets the |
//|  peak when the terminal restarts is not a breaker. One power cut |
//|  in the middle of a drawdown would be enough for it to believe it|
//|  is back at the top.                                             |
//|                                                                  |
//|  WARNING: position sizing does NOT create an edge — it only      |
//|  multiplies whatever edge exists. Plug it only into a strategy   |
//|  that has already passed out-of-sample validation.               |
//+------------------------------------------------------------------+
//| Joao Prata Silva Yglesias                                        |
//| https://www.mql5.com/en/users/jotayglesias                       |
//+------------------------------------------------------------------+
#ifndef CONTRACT_SIZER_MQH
#define CONTRACT_SIZER_MQH

class CContractSizer
  {
private:
   double m_factor;        // balance per contract (account currency)
   int    m_maxContracts;  // absolute cap on contracts
   int    m_minContracts;  // floor of contracts while there is minimum capital
   double m_minCapital;    // below this it does NOT trade — a new deposit is required
   double m_maxDD;         // fraction of the peak (0 = breaker off)
   double m_peak;          // highest balance ever seen, ADJUSTED for deposits and withdrawals
   double m_flows;         // sum of deposits and withdrawals already accounted for
   bool   m_tripped;       // breaker has tripped
   int    m_contractsToday;
   int    m_lastDay;
   string m_peakFile;

   void LoadPeak()
     {
      int h = FileOpen(m_peakFile, FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
      if(h == INVALID_HANDLE) return;
      double v = StringToDouble(FileReadString(h));
      if(!FileIsEnding(h)) m_flows = StringToDouble(FileReadString(h));
      FileClose(h);
      if(v > m_peak) m_peak = v;
     }

   void SavePeak()
     {
      int h = FileOpen(m_peakFile, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
      if(h == INVALID_HANDLE) return;
      FileWrite(h, DoubleToString(m_peak, 2));
      FileWrite(h, DoubleToString(m_flows, 2));
      FileClose(h);
     }

   // Sums the BALANCE deals (deposits and withdrawals) and shifts the peak by
   // whatever has not been accounted for yet. This is the heart of the class.
   void AdjustForFlows()
     {
      if(!HistorySelect(0, TimeCurrent() + 86400)) return;
      double sum = 0;
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
        {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if(HistoryDealGetInteger(t, DEAL_TYPE) == DEAL_TYPE_BALANCE)
            sum += HistoryDealGetDouble(t, DEAL_PROFIT);
        }
      double delta = sum - m_flows;
      if(MathAbs(delta) < 0.01) return;           // nothing new
      m_peak  += delta;                           // shift the peak along with the cash
      m_flows  = sum;
      PrintFormat("[ContractSizer] cash flow of %.2f — peak adjusted to %.2f. "
                  "The drawdown keeps measuring only trading.", delta, m_peak);
      SavePeak();
     }

public:
   CContractSizer(double factor = 3000.0, int maxContracts = 500, int minContracts = 1,
                  double minCapital = 1500.0, double maxDD = 0.0,
                  string peakFile = "contract_sizer_peak.txt")
     {
      m_factor = factor; m_maxContracts = maxContracts; m_minContracts = minContracts;
      m_minCapital = minCapital; m_maxDD = maxDD;
      m_peak = 0; m_flows = 0; m_tripped = false;
      m_contractsToday = 0; m_lastDay = -1; m_peakFile = peakFile;
     }

   double Peak()    const { return m_peak; }
   bool   Tripped() const { return m_tripped; }
   void   Rearm()         { m_tripped = false; }   // a human decision, by hand

   //--- CAP BY BALANCE. Holds even with manual lot sizing: always call it.
   int CapByBalance()
     {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance < m_minCapital) return 0;         // floor: no trading
      int contracts = (int)MathFloor(balance / m_factor);
      if(contracts > m_maxContracts) contracts = m_maxContracts;
      if(contracts < m_minContracts) contracts = m_minContracts;
      return contracts;
     }

   //--- Contracts for the day. Recomputed only at the day change, from the
   //--- BALANCE — "yesterday's balance". An account that starts with 30,000
   //--- opens with 10 contracts right away: the ladder looks at the capital,
   //--- not at seniority.
   int ContractsToday(datetime now)
     {
      MqlDateTime dt; TimeToStruct(now, dt);
      int key = dt.year * 10000 + dt.mon * 100 + dt.day;
      if(key == m_lastDay) return m_contractsToday;
      m_lastDay = key;

      if(m_peak <= 0) LoadPeak();
      AdjustForFlows();
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance > m_peak) { m_peak = balance; SavePeak(); }

      // BREAKER. Once tripped it does NOT rearm by itself.
      if(m_maxDD > 0 && m_peak > 0)
        {
         double drawdown = (m_peak - balance) / m_peak;
         if(drawdown >= m_maxDD)
           {
            if(!m_tripped)
               PrintFormat("[ContractSizer] BREAKER: %.1f%% drop from the peak "
                           "(%.2f -> %.2f). STOPPED and will not rearm by itself.",
                           100.0 * drawdown, m_peak, balance);
            m_tripped = true;
            m_contractsToday = 0;
            return 0;
           }
        }

      m_contractsToday = CapByBalance();
      return m_contractsToday;
     }
  };

#endif // CONTRACT_SIZER_MQH
//+------------------------------------------------------------------+
