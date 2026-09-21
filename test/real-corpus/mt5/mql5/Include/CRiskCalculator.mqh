//+--------------------------------------------------------------------+
//|                          [Nome_Modulo].mq5                         |
//|                    Copyright 2026, Romeo Luvisotto                 |
//|               https://www.mql5.com/en/users/romeoluvisotto         |
//+---------------------------------------------------------------------+
#property copyright "Romeo Luvisotto"
#property link      "https://www.mql5.com/en/users/romeoluvisotto"
#property version   "2.12"

// --- NEED CUSTOM DEVELOPMENT OR MODIFICATIONS? ---
// If you need custom Expert Advisors, custom indicators, or integration
// of this module into your trading system, contact me on MQL5 Freelance:
// https://www.mql5.com/en/users/romeoluvisotto
//+------------------------------------------------------------------+

#ifndef RISK_CALCULATOR_MQH
#define RISK_CALCULATOR_MQH

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CRiskCalculator
  {
private:
   string            m_accountCurrency;

   //--- Helper methods for fallback conversion logic
   void              GetBaseQuote(const string symbol, string &base, string &quote) const;
   bool              TryGetConversionRate(const string fromCurr, const string toCurr, double &rate) const;
   double            NormalizeVolume(const string symbol, double volume) const;

public:
                     CRiskCalculator();
                    ~CRiskCalculator();

   //--- Core calculation methods
   double            GetPipValuePerLot(const string symbol) const;
   double            GetPipValue(const string symbol, const double volume) const;
   double            CalculateLotSize(const string symbol, const double riskAmount, const double slPips) const;
  };

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CRiskCalculator::CRiskCalculator()
  {
   m_accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);
  }

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CRiskCalculator::~CRiskCalculator()
  {
  }

//+------------------------------------------------------------------+
//| Extracts Base and Quote currencies from a symbol string          |
//+------------------------------------------------------------------+
void CRiskCalculator::GetBaseQuote(const string symbol, string &base, string &quote) const
  {
   if(StringLen(symbol) >= 6)
     {
      base  = StringSubstr(symbol, 0, 3);
      quote = StringSubstr(symbol, 3, 3);
     }
   else
     {
      base  = symbol;
      quote = "";
     }
  }

//+------------------------------------------------------------------+
//| Attempts to find the conversion rate between two currencies      |
//+------------------------------------------------------------------+
bool CRiskCalculator::TryGetConversionRate(const string fromCurr, const string toCurr, double &rate) const
  {
   string directSymbol  = fromCurr + toCurr;
   string inverseSymbol = toCurr + fromCurr;

// 1) Check inverse symbol (e.g., USD -> EUR checking EURUSD)
   double bidInverse = SymbolInfoDouble(inverseSymbol, SYMBOL_BID);
   if(bidInverse > 0.0)
     {
      rate = 1.0 / bidInverse;
      return true;
     }
   if(SymbolSelect(inverseSymbol, true))
     {
      bidInverse = SymbolInfoDouble(inverseSymbol, SYMBOL_BID);
      if(bidInverse > 0.0)
        {
         rate = 1.0 / bidInverse;
         return true;
        }
     }

// 2) Check direct symbol (e.g., EUR -> USD checking EURUSD)
   double bidDirect = SymbolInfoDouble(directSymbol, SYMBOL_BID);
   if(bidDirect > 0.0)
     {
      rate = bidDirect;
      return true;
     }
   if(SymbolSelect(directSymbol, true))
     {
      bidDirect = SymbolInfoDouble(directSymbol, SYMBOL_BID);
      if(bidDirect > 0.0)
        {
         rate = bidDirect;
         return true;
        }
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Normalizes requested volume to broker's allowed steps and limits |
//+------------------------------------------------------------------+
double CRiskCalculator::NormalizeVolume(const string symbol, double volume) const
  {
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double min  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   if(step <= 0.0)
      return 0.0;

// Align volume to the nearest step rounding down
   double normalizedVolume = MathFloor(volume / step) * step;

// Clamp to limits
   if(normalizedVolume < min)
      normalizedVolume = min;
   if(normalizedVolume > max)
      normalizedVolume = max;

// Determine precision to avoid floating point artifacts
   int decimals = 0;
   if(step == 0.1)
      decimals = 1;
   else
      if(step == 0.01)
         decimals = 2;
      else
         if(step == 0.001)
            decimals = 3;

   return NormalizeDouble(normalizedVolume, decimals);
  }

//+------------------------------------------------------------------+
//| Calculates the monetary value of 1 pip for 1 standard lot        |
//+------------------------------------------------------------------+
double CRiskCalculator::GetPipValuePerLot(const string symbol) const
  {
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return 0.0;

// Standard definition: 1 Pip = 10 Points
   double pipSize = point * 10.0;

   double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if(contractSize <= 0.0)
      contractSize = 100000.0; // Fallback to standard lot

//--- PRIMARY: Try using native API for Tick Value
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize > 0.0 && tickValue > 0.0)
     {
      return (pipSize / tickSize) * tickValue;
     }

//--- FALLBACK: Manual cross-currency calculation
   double valueInQuotePerLot = pipSize * contractSize;
   string base = "", quote = "";
   GetBaseQuote(symbol, base, quote);

   if(StringLen(quote) == 0)
      return 0.0;

   if(StringCompare(quote, m_accountCurrency) == 0)
     {
      return valueInQuotePerLot;
     }
   else
     {
      double convRate = 0.0;
      if(TryGetConversionRate(quote, m_accountCurrency, convRate) && convRate > 0.0)
        {
         return valueInQuotePerLot * convRate;
        }
     }

   return 0.0; // Conversion failed
  }

//+------------------------------------------------------------------+
//| Calculates the monetary value of 1 pip for a specific volume     |
//+------------------------------------------------------------------+
double CRiskCalculator::GetPipValue(const string symbol, const double volume) const
  {
   double pipValuePerLot = GetPipValuePerLot(symbol);
   return pipValuePerLot * volume;
  }

//+------------------------------------------------------------------+
//| Calculates normalized lot size based on Risk amount and SL pips  |
//+------------------------------------------------------------------+
double CRiskCalculator::CalculateLotSize(const string symbol, const double riskAmount, const double slPips) const
  {
   if(slPips <= 0.0 || riskAmount <= 0.0)
      return 0.0;

   double pipValuePerLot = GetPipValuePerLot(symbol);
   if(pipValuePerLot <= 0.0)
      return 0.0;

   double riskPerLot = pipValuePerLot * slPips;
   double rawVolume  = riskAmount / riskPerLot;

   return NormalizeVolume(symbol, rawVolume);
  }

#endif // RISK_CALCULATOR_MQH
//+------------------------------------------------------------------+
