//+------------------------------------------------------------------+
//|                                              BrokerDiagnostics.mq5|
//|                  EA diagnostica: estrae tutte le info broker/MT5 |
//+------------------------------------------------------------------+
#property copyright "Diagnostica Broker"
#property version   "1.08"
#property strict

input string   FileName       = "BrokerReport.csv";   // file di report
input bool     PrintToLog     = true;                  // stampa nel log Experts
input bool     ShowPanel      = true;                  // mostra pannello sul grafico
input bool     SaveFile       = true;                  // salva report su file MQL5/Files

//--- globale
string   g_lines[];
int      g_spreadSum = 0;
int      g_spreadCount = 0;
int      g_minSpread = INT_MAX;
int      g_maxSpread = 0;
datetime g_lastPanelUpdate = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   CollectAll();
   if(ShowPanel) UpdatePanel();
   EventSetTimer(2);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(ShowPanel) ObjectsDeleteAll(0, "BD_");
   Comment("");
}

void OnTimer()
{
   if(ShowPanel) UpdatePanel();
}

void OnTick()
{
   int sp = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   g_spreadSum += sp;
   g_spreadCount++;
   if(sp < g_minSpread) g_minSpread = sp;
   if(sp > g_maxSpread) g_maxSpread = sp;

   if(ShowPanel && TimeCurrent() - g_lastPanelUpdate >= 2)
   {
      UpdatePanel();
      g_lastPanelUpdate = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
void CollectAll()
{
   ArrayResize(g_lines, 0);
   string out = "";

   Add("============== CONTO / BROKER ==============");
   Add("Nome broker (company)        : " + (string)AccountInfoString(ACCOUNT_COMPANY));
   Add("Server di trading            : " + (string)AccountInfoString(ACCOUNT_SERVER));
   Add("Nome conto                   : " + (string)AccountInfoString(ACCOUNT_NAME));
   Add("Numero conto (login)         : " + (string)AccountInfoInteger(ACCOUNT_LOGIN));
   Add("Valuta conto                 : " + (string)AccountInfoString(ACCOUNT_CURRENCY));
   Add("Leva                         : 1:" + (string)AccountInfoInteger(ACCOUNT_LEVERAGE));
   Add("Equity                       : " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
   Add("Balance                      : " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
   Add("Lingua                       : " + (string)TerminalInfoString(TERMINAL_LANGUAGE));
   Add("Build MT5                    : " + (string)TerminalInfoInteger(TERMINAL_BUILD));

   Add("");
   Add("============== SIMBOLO / ASSET =============");
   Add("Symbol                       : " + _Symbol);
   Add("Descrizione                  : " + (string)SymbolInfoString(_Symbol, SYMBOL_DESCRIPTION));
   Add("Path categoria               : " + (string)SymbolInfoString(_Symbol, SYMBOL_PATH));
   Add("Currency base                : " + (string)SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE));
   Add("Currency profit              : " + (string)SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT));
   Add("Currency margin              : " + (string)SymbolInfoString(_Symbol, SYMBOL_CURRENCY_MARGIN));
   Add("Digits                       : " + (string)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   Add("Point                        : " + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_POINT), _Digits));
   Add("Tick size                    : " + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), _Digits));
   Add("Tick value                   : " + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), 5));
   Add("Contract size                : " + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE), 2));
   Add("Volume min                   : " + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), 4));
   Add("Volume max                   : " + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), 4));
   Add("Volume step                  : " + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), 4));
   Add("Stops level (pt)             : " + (string)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL));
   Add("Freeze level (pt)            : " + (string)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL));
   Add("Bid                          : " + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits));
   Add("Ask                          : " + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits));
   Add("Spread (corrente, pt)        : " + (string)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
   Add("Spread floating?             : " + ((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD_FLOAT)!=0?"SI":"NO"));

   Add("");
   Add("============ COMMISSIONI / SWAP ============");
   Add("Tipo calcolo swap            : " + SwapTypeToStr((long)SymbolInfoInteger(_Symbol, SYMBOL_SWAP_MODE)));
   Add("Swap long                    : " + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_SWAP_LONG), 5));
   Add("Swap short                   : " + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_SWAP_SHORT), 5));
   
   double swapLongVal = CalcSwapInCurrency(true, 1.0);
   double swapShortVal = CalcSwapInCurrency(false, 1.0);
   Add("Swap long (valuta/lotto)     : " + DoubleToString(swapLongVal, 2) + " " + (string)AccountInfoString(ACCOUNT_CURRENCY));
   Add("Swap short (valuta/lotto)    : " + DoubleToString(swapShortVal, 2) + " " + (string)AccountInfoString(ACCOUNT_CURRENCY));

   Add("");
   Add("=========== ESECUZIONE / FILLING ===========");
   long fillMode = (long)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   Add("Filling mode (FOK)           : " + ((fillMode & 1)!=0?"SI":"NO"));
   Add("Filling mode (IOC)           : " + ((fillMode & 2)!=0?"SI":"NO"));
   Add("Margin hedging               : " + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_HEDGED), 2));
   Add("Calcolo margin               : " + MarginCalcToStr((long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_CALC_MODE)));

   Add("");
   Add("=========== TEMPO / FUSO ORARIO ===========");
   MqlDateTime srv;
   TimeToStruct(TimeCurrent(), srv);
   long serverEpoch = (long)TimeCurrent();
   long localEpoch  = (long)TimeLocal();
   long diffSec     = localEpoch - serverEpoch;
   long diffMin     = diffSec / 60;
   Add("Server time (ora corrente)   : " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   Add("Local time (ora PC)          : " + TimeToString(TimeLocal(), TIME_DATE|TIME_SECONDS));
   Add("Differenza local-server(ore) : " + DoubleToString((double)diffMin/60.0, 2));
   datetime utcNow = TimeGMT();
   long srvUtcDiff = (long)TimeCurrent() - (long)utcNow;
   Add("UTC corrente (GMT)           : " + TimeToString(utcNow, TIME_DATE|TIME_SECONDS));
   Add("Server - UTC (ore)           : " + DoubleToString((double)srvUtcDiff/3600.0, 2) + "  <-- CRITICO");

   Add("");
   Add("=========== LATENZA / CONNETTIVITA" + "' ========");
   int ping = (int)TerminalInfoInteger(TERMINAL_PING_LAST);
   Add("Ping last (ms)               : " + (string)ping);
   Add("Connessione                  : " + ((int)TerminalInfoInteger(TERMINAL_CONNECTED)!=0?"ATTIVA":"DISCONNESSA"));
   Add("Trade allowed                : " + ((int)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)!=0?"SI":"NO"));

   Add("");
   Add("=========== STATISTICHE (parziali) =========");
   if(g_spreadCount > 0)
      Add("Spread medio campionato      : " + DoubleToString((double)g_spreadSum/g_spreadCount, 1) + " pt (su " + (string)g_spreadCount + " tick)");
   else
      Add("Spread medio campionato      : n/a (lascia l'EA acceso qualche minuto)");

   for(int i=0; i<ArraySize(g_lines); i++)
   {
      if(PrintToLog) Print(g_lines[i]);
      out += g_lines[i] + "\n";
   }
   Comment(out);

   if(SaveFile)
   {
      int fh = FileOpen(FileName, FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(fh != INVALID_HANDLE)
      {
         FileWriteString(fh, "REPORT BROKER - " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\n");
         for(int i=0; i<ArraySize(g_lines); i++) FileWriteString(fh, g_lines[i] + "\n");
         FileClose(fh);
      }
   }
}

double CalcSwapInCurrency(bool isLong, double volume)
{
   long mode = (long)SymbolInfoInteger(_Symbol, SYMBOL_SWAP_MODE);
   double swap = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_SWAP_LONG) : SymbolInfoDouble(_Symbol, SYMBOL_SWAP_SHORT);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double price     = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double contract  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);

   if(mode == 0) return 0.0;
   if(mode == 1) return swap * point / tickSize * tickValue * volume;
   if(mode == 2) return swap * volume;
   if(mode == 3) return swap * volume;
   if(mode == 4) return swap * volume;
   if(mode == 5) return (swap * price * contract * volume) / 100.0 / 365.0;
   if(mode == 6) return (swap * price * contract * volume) / 100.0 / 365.0;
   return 0.0;
}

string AccountTypeToStr(long t)
{
   if(t == 0) return "DEMO";
   if(t == 1) return "CONTEST";
   if(t == 2) return "REALE";
   return "UNKNOWN";
}

string SwapTypeToStr(long t)
{
   if(t == 0) return "DISABILITATO";
   if(t == 1) return "PUNTI";
   if(t == 2) return "VALUTA SIMBOLO";
   if(t == 3) return "VALUTA MARGINE";
   if(t == 4) return "VALUTA DEPOSITO";
   if(t == 5) return "INTERESSE (prezzo corr.)";
   if(t == 6) return "INTERESSE (prezzo apert.)";
   return "UNKNOWN";
}

string MarginCalcToStr(long t)
{
   if(t == 0) return "FOREX";
   if(t == 1) return "FUTURES";
   if(t == 2) return "CFD";
   if(t == 3) return "CFDINDEX";
   if(t == 4) return "CFDLEVERAGE";
   return "UNKNOWN";
}

void Add(string s)
{
   int n = ArraySize(g_lines);
   ArrayResize(g_lines, n+1);
   g_lines[n] = s;
}

void UpdatePanel()
{
   ObjectsDeleteAll(0, "BD_");
   int x = 200, y = 20, dy = 14;
   CreateLabel("BD_title", "BROKER DIAGNOSTICS", x, y, clrGold, 10); y += dy+6;
   CreateLabel("BD_sym", "Simbolo: " + _Symbol, x, y, clrWhite, 9); y += dy;
   CreateLabel("BD_acc", "Conto: " + (string)AccountInfoInteger(ACCOUNT_LOGIN), x, y, clrWhite, 9); y += dy;
   CreateLabel("BD_lev", "Leva: 1:" + (string)AccountInfoInteger(ACCOUNT_LEVERAGE), x, y, clrWhite, 9); y += dy;

   int sp = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   CreateLabel("BD_spread", "Spread: " + (string)sp + " pt", x, y, clrYellow, 9); y += dy;

   int ping = (int)TerminalInfoInteger(TERMINAL_PING_LAST);
   CreateLabel("BD_ping", "Ping: " + (string)ping + " ms", x, y, (ping<100?clrLime:(ping<300?clrYellow:clrRed)), 9); y += dy;

   long srvUtcDiff = (long)TimeCurrent() - (long)TimeGMT();
   CreateLabel("BD_tz", "Server-UTC: " + DoubleToString((double)srvUtcDiff/3600.0, 1) + "h", x, y, clrOrange, 9);
}

void CreateLabel(string name, string text, int x, int y, color clr, int fontSize=9)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}
//+------------------------------------------------------------------+