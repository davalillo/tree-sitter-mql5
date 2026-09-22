//+------------------------------------------------------------------+
//|                                     Trade_Journal_CSV_Export.mq4 |
//|                                     Forexobroker - Dominic Walsh |
//|                                     https://www.forexobroker.com |
//+------------------------------------------------------------------+
#property copyright "Forexobroker - Dominic Walsh"
#property link      "https://www.forexobroker.com"
#property version   "1.00"
#property strict
#property show_inputs
#property description "Exports complete trade history to CSV with performance statistics."
#property description "Includes win rate, profit factor, max drawdown, and more."
#property description ""
#property description "For professional trading tools, visit MQL5 Market"
#property description "and search for products by Dominic Walsh."

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input int      InpMagicNumber     = 0;              // Magic Number Filter (0 = All)
input datetime InpDateFrom        = D'2020.01.01';  // Date From Filter
input datetime InpDateTo          = D'2030.12.31';  // Date To Filter
input string   InpSymbolFilter    = "";             // Symbol Filter ("" = All Symbols)
input bool     InpIncludePending  = false;          // Include Pending Orders
input string   InpFileName        = "TradeJournal"; // Output File Name (without .csv)
input string   InpSeparator       = ",";            // CSV Separator Character

//+------------------------------------------------------------------+
//| Trade record structure                                            |
//+------------------------------------------------------------------+
struct TradeRecord
{
   int      ticket;
   string   symbol;
   int      type;
   datetime openTime;
   datetime closeTime;
   double   openPrice;
   double   closePrice;
   double   lots;
   double   stopLoss;
   double   takeProfit;
   double   grossProfit;
   double   commission;
   double   swap;
   double   netProfit;
   double   pips;
   string   comment;
   int      magicNumber;
   int      symbolDigits;
};

//+------------------------------------------------------------------+
//| Script program start function                                     |
//+------------------------------------------------------------------+
void OnStart()
{
   //--- Collect matching trades from history
   TradeRecord trades[];
   int tradeCount = CollectTrades(trades);

   if(tradeCount == 0)
   {
      Alert("Trade Journal Export: No trades found matching the specified filters.");
      return;
   }

   //--- Build the full file name with timestamp
   string timestamp = TimeToString(TimeCurrent(), TIME_DATE);
   StringReplace(timestamp, ".", "");
   string fullFileName = InpFileName + "_" + timestamp + ".csv";

   //--- Open CSV file for writing
   int fileHandle = FileOpen(fullFileName, FILE_WRITE | FILE_CSV | FILE_ANSI, '\t');

   if(fileHandle == INVALID_HANDLE)
   {
      Alert("Trade Journal Export: Failed to open file. Error: ", GetLastError());
      return;
   }

   //--- Write header row
   WriteHeader(fileHandle);

   //--- Write each trade row
   for(int i = 0; i < tradeCount; i++)
   {
      WriteTradeRow(fileHandle, trades[i]);
   }

   //--- Write blank separator rows
   FileWrite(fileHandle, "");
   FileWrite(fileHandle, "");

   //--- Calculate and write summary statistics
   WriteSummaryStatistics(fileHandle, trades, tradeCount);

   //--- Close the file
   FileClose(fileHandle);

   //--- Build quick summary for alert
   double netProfit    = CalculateNetProfit(trades, tradeCount);
   double winRate      = CalculateWinRate(trades, tradeCount);
   double profitFactor = CalculateProfitFactor(trades, tradeCount);

   string alertMsg = StringFormat(
      "Trade Journal Export Complete!\n\n"
      "File: %s\n"
      "Trades: %d\n"
      "Net Profit: %.2f %s\n"
      "Win Rate: %.1f%%\n"
      "Profit Factor: %.2f\n\n"
      "File saved in MQL4/Files/ folder.",
      fullFileName,
      tradeCount,
      netProfit,
      AccountCurrency(),
      winRate,
      profitFactor
   );

   Print("Trade Journal CSV exported successfully: ", fullFileName);
   Print("Total trades exported: ", tradeCount);
   Alert(alertMsg);
}

//+------------------------------------------------------------------+
//| Collect all matching trades from account history                  |
//+------------------------------------------------------------------+
int CollectTrades(TradeRecord &trades[])
{
   int total = OrdersHistoryTotal();
   int count = 0;

   //--- First pass: count matching trades to size the array
   for(int i = 0; i < total; i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;

      if(IsTradeMatch())
         count++;
   }

   if(count == 0)
      return 0;

   ArrayResize(trades, count);

   //--- Second pass: populate trade records
   int idx = 0;
   for(int i = 0; i < total; i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;

      if(!IsTradeMatch())
         continue;

      trades[idx].ticket      = OrderTicket();
      trades[idx].symbol      = OrderSymbol();
      trades[idx].type        = OrderType();
      trades[idx].openTime    = OrderOpenTime();
      trades[idx].closeTime   = OrderCloseTime();
      trades[idx].openPrice   = OrderOpenPrice();
      trades[idx].closePrice  = OrderClosePrice();
      trades[idx].lots        = OrderLots();
      trades[idx].stopLoss    = OrderStopLoss();
      trades[idx].takeProfit  = OrderTakeProfit();
      trades[idx].commission  = OrderCommission();
      trades[idx].swap        = OrderSwap();
      trades[idx].grossProfit = OrderProfit();
      trades[idx].netProfit   = OrderProfit() + OrderCommission() + OrderSwap();
      trades[idx].comment     = OrderComment();
      trades[idx].magicNumber = OrderMagicNumber();
      trades[idx].symbolDigits = (int)MarketInfo(OrderSymbol(), MODE_DIGITS);

      //--- Calculate pips gained/lost
      trades[idx].pips = CalculatePips(
         trades[idx].type,
         trades[idx].openPrice,
         trades[idx].closePrice,
         trades[idx].symbol
      );

      idx++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| Check if current selected order matches all filters               |
//+------------------------------------------------------------------+
bool IsTradeMatch()
{
   int orderType = OrderType();

   //--- Filter: only closed market orders (and optionally pending)
   if(!InpIncludePending)
   {
      if(orderType != OP_BUY && orderType != OP_SELL)
         return false;
   }
   else
   {
      //--- Include pending that were deleted/expired (types 2-5)
      if(orderType > OP_SELLSTOP)
         return false;
   }

   //--- Filter: magic number
   if(InpMagicNumber != 0 && OrderMagicNumber() != InpMagicNumber)
      return false;

   //--- Filter: date range (use close time for completed trades)
   datetime closeTime = OrderCloseTime();
   if(closeTime < InpDateFrom || closeTime > InpDateTo)
      return false;

   //--- Filter: symbol
   if(InpSymbolFilter != "" && OrderSymbol() != InpSymbolFilter)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Calculate pips for a trade (handles 3/5 digit brokers)            |
//+------------------------------------------------------------------+
double CalculatePips(int orderType, double openPrice, double closePrice, string symbol)
{
   int digits = (int)MarketInfo(symbol, MODE_DIGITS);
   double point = MarketInfo(symbol, MODE_POINT);

   if(point == 0)
      return 0;

   //--- Determine pip multiplier for 3/5 digit brokers
   double pipMultiplier = 1.0;
   if(digits == 3 || digits == 5)
      pipMultiplier = 10.0;

   double priceDiff = 0;

   if(orderType == OP_BUY)
      priceDiff = closePrice - openPrice;
   else if(orderType == OP_SELL)
      priceDiff = openPrice - closePrice;
   else
      return 0; // Pending orders have no pip result

   double pips = priceDiff / (point * pipMultiplier);

   return NormalizeDouble(pips, 1);
}

//+------------------------------------------------------------------+
//| Write CSV header row                                              |
//+------------------------------------------------------------------+
void WriteHeader(int fileHandle)
{
   string header =
      "Ticket"       + InpSeparator +
      "Symbol"       + InpSeparator +
      "Type"         + InpSeparator +
      "Open Time"    + InpSeparator +
      "Close Time"   + InpSeparator +
      "Duration"     + InpSeparator +
      "Open Price"   + InpSeparator +
      "Close Price"  + InpSeparator +
      "Lot Size"     + InpSeparator +
      "Stop Loss"    + InpSeparator +
      "Take Profit"  + InpSeparator +
      "Gross Profit" + InpSeparator +
      "Commission"   + InpSeparator +
      "Swap"         + InpSeparator +
      "Net Profit"   + InpSeparator +
      "Pips"         + InpSeparator +
      "Comment"      + InpSeparator +
      "Magic Number";

   FileWrite(fileHandle, header);
}

//+------------------------------------------------------------------+
//| Write a single trade row to the CSV                               |
//+------------------------------------------------------------------+
void WriteTradeRow(int fileHandle, const TradeRecord &trade)
{
   //--- Format order type as readable string
   string typeStr = OrderTypeToString(trade.type);

   //--- Format duration
   string duration = FormatDuration(trade.openTime, trade.closeTime);

   //--- Format datetimes
   string openTimeStr  = TimeToString(trade.openTime, TIME_DATE | TIME_SECONDS);
   string closeTimeStr = TimeToString(trade.closeTime, TIME_DATE | TIME_SECONDS);

   //--- Determine price format digits
   int digits = trade.symbolDigits;

   //--- Build the CSV row
   string row =
      IntegerToString(trade.ticket)                         + InpSeparator +
      trade.symbol                                          + InpSeparator +
      typeStr                                               + InpSeparator +
      openTimeStr                                           + InpSeparator +
      closeTimeStr                                          + InpSeparator +
      duration                                              + InpSeparator +
      DoubleToString(trade.openPrice, digits)               + InpSeparator +
      DoubleToString(trade.closePrice, digits)              + InpSeparator +
      DoubleToString(trade.lots, 2)                         + InpSeparator +
      DoubleToString(trade.stopLoss, digits)                + InpSeparator +
      DoubleToString(trade.takeProfit, digits)              + InpSeparator +
      DoubleToString(trade.grossProfit, 2)                  + InpSeparator +
      DoubleToString(trade.commission, 2)                   + InpSeparator +
      DoubleToString(trade.swap, 2)                         + InpSeparator +
      DoubleToString(trade.netProfit, 2)                    + InpSeparator +
      DoubleToString(trade.pips, 1)                         + InpSeparator +
      trade.comment                                         + InpSeparator +
      IntegerToString(trade.magicNumber);

   FileWrite(fileHandle, row);
}

//+------------------------------------------------------------------+
//| Convert order type to readable string                             |
//+------------------------------------------------------------------+
string OrderTypeToString(int type)
{
   switch(type)
   {
      case OP_BUY:       return "Buy";
      case OP_SELL:      return "Sell";
      case OP_BUYLIMIT:  return "Buy Limit";
      case OP_SELLLIMIT: return "Sell Limit";
      case OP_BUYSTOP:   return "Buy Stop";
      case OP_SELLSTOP:  return "Sell Stop";
      default:           return "Unknown";
   }
}

//+------------------------------------------------------------------+
//| Format trade duration as "Xd Xh Xm"                              |
//+------------------------------------------------------------------+
string FormatDuration(datetime openTime, datetime closeTime)
{
   int totalSeconds = (int)(closeTime - openTime);

   if(totalSeconds < 0)
      return "N/A";

   int days    = totalSeconds / 86400;
   int hours   = (totalSeconds % 86400) / 3600;
   int minutes = (totalSeconds % 3600) / 60;

   string result = "";

   if(days > 0)
      result += IntegerToString(days) + "d ";

   if(hours > 0 || days > 0)
      result += IntegerToString(hours) + "h ";

   result += IntegerToString(minutes) + "m";

   return result;
}

//+------------------------------------------------------------------+
//| Calculate and write all summary statistics                        |
//+------------------------------------------------------------------+
void WriteSummaryStatistics(int fileHandle, const TradeRecord &trades[], int tradeCount)
{
   //--- Basic counters
   int    winners      = 0;
   int    losers       = 0;
   int    breakeven    = 0;
   double grossProfit  = 0;
   double grossLoss    = 0;
   double totalNet     = 0;
   double totalWin     = 0;
   double totalLoss    = 0;
   double largestWin   = 0;
   double largestLoss  = 0;

   //--- Duration tracking
   long totalDuration  = 0;

   //--- Consecutive streaks
   int currentWinStreak   = 0;
   int currentLossStreak  = 0;
   int maxWinStreak       = 0;
   int maxLossStreak      = 0;

   //--- Drawdown tracking
   double runningBalance  = 0;
   double peakBalance     = 0;
   double maxDrawdown     = 0;
   double maxDrawdownPct  = 0;

   //--- For Sharpe ratio: collect net profit per trade
   double profitArray[];
   ArrayResize(profitArray, tradeCount);

   //--- Process each trade
   for(int i = 0; i < tradeCount; i++)
   {
      double net = trades[i].netProfit;
      profitArray[i] = net;
      totalNet += net;

      //--- Duration
      totalDuration += (long)(trades[i].closeTime - trades[i].openTime);

      //--- Win/Loss classification
      if(net > 0)
      {
         winners++;
         grossProfit += net;
         totalWin    += net;
         if(net > largestWin)
            largestWin = net;

         //--- Streak tracking
         currentWinStreak++;
         currentLossStreak = 0;
         if(currentWinStreak > maxWinStreak)
            maxWinStreak = currentWinStreak;
      }
      else if(net < 0)
      {
         losers++;
         grossLoss += MathAbs(net);
         totalLoss += MathAbs(net);
         if(MathAbs(net) > MathAbs(largestLoss))
            largestLoss = net;

         //--- Streak tracking
         currentLossStreak++;
         currentWinStreak = 0;
         if(currentLossStreak > maxLossStreak)
            maxLossStreak = currentLossStreak;
      }
      else
      {
         breakeven++;
         currentWinStreak  = 0;
         currentLossStreak = 0;
      }

      //--- Drawdown calculation (equity curve simulation)
      runningBalance += net;
      if(runningBalance > peakBalance)
         peakBalance = runningBalance;

      double currentDrawdown = peakBalance - runningBalance;
      if(currentDrawdown > maxDrawdown)
      {
         maxDrawdown = currentDrawdown;
         if(peakBalance > 0)
            maxDrawdownPct = (currentDrawdown / peakBalance) * 100.0;
      }
   }

   //--- Derived statistics
   double winRate       = (tradeCount > 0) ? ((double)winners / tradeCount) * 100.0 : 0;
   double profitFactor  = (grossLoss > 0)  ? grossProfit / grossLoss : 0;
   double avgWin        = (winners > 0)    ? totalWin / winners : 0;
   double avgLoss       = (losers > 0)     ? totalLoss / losers : 0;
   double avgRR         = (avgLoss > 0)    ? avgWin / avgLoss : 0;
   double expectancy    = (tradeCount > 0) ? totalNet / tradeCount : 0;

   //--- Average duration
   long avgDurationSec  = (tradeCount > 0) ? totalDuration / tradeCount : 0;
   string avgDuration   = FormatDurationFromSeconds((int)avgDurationSec);

   //--- Sharpe ratio approximation (annualized, assuming ~252 trading days)
   double sharpeRatio = CalculateSharpeRatio(profitArray, tradeCount);

   //--- Currency string for display
   string curr = AccountCurrency();

   //--- Write summary section header
   WriteSummaryLine(fileHandle, "=== TRADE JOURNAL SUMMARY ===", "");
   WriteSummaryLine(fileHandle, "", "");
   WriteSummaryLine(fileHandle, "--- FILTERS APPLIED ---", "");

   if(InpMagicNumber != 0)
      WriteSummaryLine(fileHandle, "Magic Number Filter", IntegerToString(InpMagicNumber));
   else
      WriteSummaryLine(fileHandle, "Magic Number Filter", "All");

   if(InpSymbolFilter != "")
      WriteSummaryLine(fileHandle, "Symbol Filter", InpSymbolFilter);
   else
      WriteSummaryLine(fileHandle, "Symbol Filter", "All Symbols");

   WriteSummaryLine(fileHandle, "Date From", TimeToString(InpDateFrom, TIME_DATE));
   WriteSummaryLine(fileHandle, "Date To", TimeToString(InpDateTo, TIME_DATE));
   WriteSummaryLine(fileHandle, "Include Pending", (InpIncludePending ? "Yes" : "No"));

   WriteSummaryLine(fileHandle, "", "");
   WriteSummaryLine(fileHandle, "--- TRADE COUNTS ---", "");
   WriteSummaryLine(fileHandle, "Total Trades",  IntegerToString(tradeCount));
   WriteSummaryLine(fileHandle, "Winners",        IntegerToString(winners));
   WriteSummaryLine(fileHandle, "Losers",         IntegerToString(losers));
   WriteSummaryLine(fileHandle, "Breakeven",      IntegerToString(breakeven));
   WriteSummaryLine(fileHandle, "Win Rate",       DoubleToString(winRate, 1) + "%");

   WriteSummaryLine(fileHandle, "", "");
   WriteSummaryLine(fileHandle, "--- PROFIT & LOSS ---", "");
   WriteSummaryLine(fileHandle, "Gross Profit",       DoubleToString(grossProfit, 2) + " " + curr);
   WriteSummaryLine(fileHandle, "Gross Loss",         DoubleToString(-grossLoss, 2) + " " + curr);
   WriteSummaryLine(fileHandle, "Net Profit",         DoubleToString(totalNet, 2) + " " + curr);
   WriteSummaryLine(fileHandle, "Profit Factor",      DoubleToString(profitFactor, 2));

   WriteSummaryLine(fileHandle, "", "");
   WriteSummaryLine(fileHandle, "--- AVERAGES ---", "");
   WriteSummaryLine(fileHandle, "Average Win",        DoubleToString(avgWin, 2) + " " + curr);
   WriteSummaryLine(fileHandle, "Average Loss",       DoubleToString(-avgLoss, 2) + " " + curr);
   WriteSummaryLine(fileHandle, "Average R:R",        DoubleToString(avgRR, 2));
   WriteSummaryLine(fileHandle, "Expectancy/Trade",   DoubleToString(expectancy, 2) + " " + curr);

   WriteSummaryLine(fileHandle, "", "");
   WriteSummaryLine(fileHandle, "--- EXTREMES ---", "");
   WriteSummaryLine(fileHandle, "Largest Win",        DoubleToString(largestWin, 2) + " " + curr);
   WriteSummaryLine(fileHandle, "Largest Loss",       DoubleToString(largestLoss, 2) + " " + curr);

   WriteSummaryLine(fileHandle, "", "");
   WriteSummaryLine(fileHandle, "--- STREAKS ---", "");
   WriteSummaryLine(fileHandle, "Max Consecutive Wins",   IntegerToString(maxWinStreak));
   WriteSummaryLine(fileHandle, "Max Consecutive Losses",  IntegerToString(maxLossStreak));

   WriteSummaryLine(fileHandle, "", "");
   WriteSummaryLine(fileHandle, "--- DRAWDOWN ---", "");
   WriteSummaryLine(fileHandle, "Max Drawdown",       DoubleToString(maxDrawdown, 2) + " " + curr);
   WriteSummaryLine(fileHandle, "Max Drawdown %",     DoubleToString(maxDrawdownPct, 1) + "%");

   WriteSummaryLine(fileHandle, "", "");
   WriteSummaryLine(fileHandle, "--- DURATION ---", "");
   WriteSummaryLine(fileHandle, "Avg Trade Duration", avgDuration);

   WriteSummaryLine(fileHandle, "", "");
   WriteSummaryLine(fileHandle, "--- RISK METRICS ---", "");
   WriteSummaryLine(fileHandle, "Sharpe Ratio (approx)", DoubleToString(sharpeRatio, 2));

   WriteSummaryLine(fileHandle, "", "");
   WriteSummaryLine(fileHandle, "Report Generated", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   WriteSummaryLine(fileHandle, "Account", IntegerToString(AccountNumber()));
   WriteSummaryLine(fileHandle, "Broker", AccountCompany());
}

//+------------------------------------------------------------------+
//| Write a single summary line (label + value)                       |
//+------------------------------------------------------------------+
void WriteSummaryLine(int fileHandle, string label, string value)
{
   if(value == "")
      FileWrite(fileHandle, label);
   else
      FileWrite(fileHandle, label + InpSeparator + value);
}

//+------------------------------------------------------------------+
//| Format duration from total seconds                                |
//+------------------------------------------------------------------+
string FormatDurationFromSeconds(int totalSeconds)
{
   if(totalSeconds <= 0)
      return "0m";

   int days    = totalSeconds / 86400;
   int hours   = (totalSeconds % 86400) / 3600;
   int minutes = (totalSeconds % 3600) / 60;

   string result = "";

   if(days > 0)
      result += IntegerToString(days) + "d ";

   if(hours > 0 || days > 0)
      result += IntegerToString(hours) + "h ";

   result += IntegerToString(minutes) + "m";

   return result;
}

//+------------------------------------------------------------------+
//| Calculate Sharpe Ratio approximation                              |
//| Annualized assuming ~252 trading days                             |
//+------------------------------------------------------------------+
double CalculateSharpeRatio(const double &profits[], int count)
{
   if(count < 2)
      return 0;

   //--- Calculate mean return
   double sum = 0;
   for(int i = 0; i < count; i++)
      sum += profits[i];

   double mean = sum / count;

   //--- Calculate standard deviation
   double sumSqDev = 0;
   for(int i = 0; i < count; i++)
   {
      double dev = profits[i] - mean;
      sumSqDev += dev * dev;
   }

   double stdDev = MathSqrt(sumSqDev / (count - 1));

   if(stdDev == 0)
      return 0;

   //--- Sharpe = (mean / stdDev) * sqrt(252)
   double sharpe = (mean / stdDev) * MathSqrt(252.0);

   return sharpe;
}

//+------------------------------------------------------------------+
//| Helper: Calculate net profit from trades array                    |
//+------------------------------------------------------------------+
double CalculateNetProfit(const TradeRecord &trades[], int count)
{
   double total = 0;
   for(int i = 0; i < count; i++)
      total += trades[i].netProfit;
   return total;
}

//+------------------------------------------------------------------+
//| Helper: Calculate win rate from trades array                      |
//+------------------------------------------------------------------+
double CalculateWinRate(const TradeRecord &trades[], int count)
{
   if(count == 0) return 0;

   int winners = 0;
   for(int i = 0; i < count; i++)
   {
      if(trades[i].netProfit > 0)
         winners++;
   }

   return ((double)winners / count) * 100.0;
}

//+------------------------------------------------------------------+
//| Helper: Calculate profit factor from trades array                 |
//+------------------------------------------------------------------+
double CalculateProfitFactor(const TradeRecord &trades[], int count)
{
   double gross = 0;
   double loss  = 0;

   for(int i = 0; i < count; i++)
   {
      if(trades[i].netProfit > 0)
         gross += trades[i].netProfit;
      else
         loss += MathAbs(trades[i].netProfit);
   }

   if(loss == 0)
      return 0;

   return gross / loss;
}

//+------------------------------------------------------------------+
