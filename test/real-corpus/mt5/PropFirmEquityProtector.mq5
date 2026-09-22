//+------------------------------------------------------------------+
//|                                      PropFirmEquityProtector.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                            https://forge.mql5.io |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, By NoeRCz."
#property link        "https://forge.mql5.io"
#property version     "1.00"
#property description "Utility EA with Object-Oriented Architecture for Prop Firm Risk Management"
#property strict

#include <Trade\Trade.mqh>

//--- Input parameters with description comments on the right
input double   InpMaxDailyLossPercent   = 4.5;   // Hard Stop: Max Daily Drawdown (%)
input bool     InpAutoCloseOnLimit      = true;  // Hard Stop: Enable Auto-Close All
input bool     InpRemoveEAOnLimit       = false; // Hard Stop: Remove EA after Hit
input double   InpMitigationLossPercent = 3.5;  // Soft Limit: Mitigation Drawdown (%)
input bool     InpEnableMitigation      = true;  // Enable Staged Mitigation
input double   InpPartialClosePercent   = 50.0;  // Volume % to close on worst position
input ulong    InpSlippagePoints        = 50;    // Slippage Tolerance (Points)
input bool     InpSendPushNotification  = true;  // Send Mobile Push Alerts
input int      InpMaxRetries            = 5;     // Max Retries on Server Error

//+------------------------------------------------------------------+
//| Prop Firm Risk Manager class                                     |
//+------------------------------------------------------------------+
class CPropFirmProtector
  {
private:
   CTrade            m_trade;
   double            m_max_daily_loss;
   bool              m_auto_close;
   bool              m_remove_ea;
   double            m_mitigation_loss;
   bool              m_enable_mitigation;
   double            m_partial_close_pct;
   ulong             m_slippage;
   bool              m_send_push;
   int               m_max_retries;
   double            m_daily_start_balance;
   bool              m_limit_reached;
   datetime          m_last_mitigation_time;

   double            CalculateDailyStartBalance();
   void              CreateDashboardLabel(string name, int x, int y, string text, color clr, int size = 10, bool bold = false);
   void              InitDashboard();
   void              UpdateDashboard(double start_bal, double equity, double dd_percent);
   void              ClearDashboard();
   void              MitigateWorstPosition();
   void              CloseAllPositionsAndOrders();

public:
                     CPropFirmProtector();
                    ~CPropFirmProtector();

   bool              Init(double max_daily_loss, bool auto_close, bool remove_ea,
                          double mitigation_loss, bool enable_mitigation, double partial_pct,
                          ulong slippage, bool send_push, int max_retries);
   void              Deinit();
   void              OnTimerProcess();
  };

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CPropFirmProtector::CPropFirmProtector() : m_max_daily_loss(4.5),
                                           m_auto_close(true),
                                           m_remove_ea(false),
                                           m_mitigation_loss(3.5),
                                           m_enable_mitigation(true),
                                           m_partial_close_pct(50.0),
                                           m_slippage(50),
                                           m_send_push(true),
                                           m_max_retries(5),
                                           m_daily_start_balance(0.0),
                                           m_limit_reached(false),
                                           m_last_mitigation_time(0)
  {
  }

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CPropFirmProtector::~CPropFirmProtector()
  {
  }

//+------------------------------------------------------------------+
//| Initialization and checking for input parameters                 |
//+------------------------------------------------------------------+
bool CPropFirmProtector::Init(double max_daily_loss, bool auto_close, bool remove_ea,
                              double mitigation_loss, bool enable_mitigation, double partial_pct,
                              ulong slippage, bool send_push, int max_retries)
  {
//--- assign parameters to class members
   m_max_daily_loss     = max_daily_loss;
   m_auto_close         = auto_close;
   m_remove_ea          = remove_ea;
   m_mitigation_loss    = mitigation_loss;
   m_enable_mitigation  = enable_mitigation;
   m_partial_close_pct  = partial_pct;
   m_slippage           = slippage;
   m_send_push          = send_push;
   m_max_retries        = max_retries;

//--- setup trading parameters
   m_trade.SetExpertMagicNumber(999999);
   m_trade.SetDeviationInPoints(m_slippage);

//--- initialize visual interface
   InitDashboard();

//--- calculate initial reference balance
   m_daily_start_balance = CalculateDailyStartBalance();

   return(true);
  }

//+------------------------------------------------------------------+
//| Deinitialization and resource cleanup                            |
//+------------------------------------------------------------------+
void CPropFirmProtector::Deinit()
  {
//--- remove graphical elements
   ClearDashboard();
  }

//+------------------------------------------------------------------+
//| Periodic processing of equity and risk rules                     |
//+------------------------------------------------------------------+
void CPropFirmProtector::OnTimerProcess()
  {
//--- calculate current financial metrics
   double current_equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   m_daily_start_balance  = CalculateDailyStartBalance();

   double daily_dd_percent = 0.0;
   if(m_daily_start_balance > 0.0)
      daily_dd_percent = ((m_daily_start_balance - current_equity) / m_daily_start_balance) * 100.0;

//--- refresh visual dashboard
   UpdateDashboard(m_daily_start_balance, current_equity, daily_dd_percent);

   if(m_limit_reached)
      return;

//--- evaluate hard stop breach
   if(daily_dd_percent >= m_max_daily_loss)
     {
      string alert_msg = "CRITICAL: Hard Drawdown limit reached! Closing all operations.";
      Print(alert_msg);

      if(m_send_push)
         SendNotification(alert_msg);

      m_limit_reached = true;

      if(m_auto_close)
         CloseAllPositionsAndOrders();

      if(m_remove_ea)
         ExpertRemove();

      return;
     }

//--- evaluate soft limit for staged mitigation
   if(m_enable_mitigation && daily_dd_percent >= m_mitigation_loss && daily_dd_percent < m_max_daily_loss)
     {
      if(TimeCurrent() - m_last_mitigation_time > 5)
        {
         MitigateWorstPosition();
         m_last_mitigation_time = TimeCurrent();
        }
     }
  }

//+------------------------------------------------------------------+
//| Calculate reference balance at the start of current server day   |
//+------------------------------------------------------------------+
double CPropFirmProtector::CalculateDailyStartBalance()
  {
   datetime current_time = TimeCurrent();
   datetime start_of_day = current_time - (current_time % 86400);
   double current_bal    = AccountInfoDouble(ACCOUNT_BALANCE);
   double daily_profit   = 0.0;

//--- request deal history for current day
   if(HistorySelect(start_of_day, current_time))
     {
      int total_deals = HistoryDealsTotal();
      for(int i = 0; i < total_deals; i++)
        {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket > 0)
           {
            long deal_entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            if(deal_entry == DEAL_ENTRY_OUT || deal_entry == DEAL_ENTRY_INOUT)
              {
               daily_profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
               daily_profit += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
               daily_profit += HistoryDealGetDouble(ticket, DEAL_SWAP);
              }
           }
        }
     }
   return(current_bal - daily_profit);
  }

//+------------------------------------------------------------------+
//| Create graphical text label                                      |
//+------------------------------------------------------------------+
void CPropFirmProtector::CreateDashboardLabel(string name, int x, int y, string text, color clr, int size = 10, bool bold = false)
  {
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 100);
  }

//+------------------------------------------------------------------+
//| Initialize dashboard graphical elements                          |
//+------------------------------------------------------------------+
void CPropFirmProtector::InitDashboard()
  {
   int anchor_x = 320;

//--- create background rectangle
   string bg_name = "PEP_Background";
   ObjectCreate(0, bg_name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg_name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, bg_name, OBJPROP_XDISTANCE, anchor_x + 10);
   ObjectSetInteger(0, bg_name, OBJPROP_YDISTANCE, 10);
   ObjectSetInteger(0, bg_name, OBJPROP_XSIZE, 330);
   ObjectSetInteger(0, bg_name, OBJPROP_YSIZE, 120);
   ObjectSetInteger(0, bg_name, OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, bg_name, OBJPROP_COLOR, clrDimGray);
   ObjectSetInteger(0, bg_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg_name, OBJPROP_BACK, true);
   ObjectSetInteger(0, bg_name, OBJPROP_ZORDER, 1);
   ObjectSetInteger(0, bg_name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, bg_name, OBJPROP_SELECTABLE, false);

//--- create dashboard labels
   CreateDashboardLabel("PEP_Title", anchor_x, 20, "🛡️ PROP FIRM EQUITY PROTECTOR", clrWhite, 11, true);
   CreateDashboardLabel("PEP_Bal", anchor_x, 45, "Daily Start Balance: Calculating...", clrLightGray);
   CreateDashboardLabel("PEP_Eq", anchor_x, 65, "Current Equity: Calculating...", clrLightGray);
   CreateDashboardLabel("PEP_DD", anchor_x, 85, "Daily Drawdown: 0.00%", clrLightGray);
   CreateDashboardLabel("PEP_Status", anchor_x, 105, "Status: INITIATING", clrYellow, 10, true);
  }

//+------------------------------------------------------------------+
//| Refresh dashboard data and handle self-healing                   |
//+------------------------------------------------------------------+
void CPropFirmProtector::UpdateDashboard(double start_bal, double equity, double dd_percent)
  {
//--- restore interface if deleted
   if(ObjectFind(0, "PEP_Title") < 0)
      InitDashboard();

   ObjectSetString(0, "PEP_Bal", OBJPROP_TEXT, "Daily Start Balance: $" + DoubleToString(start_bal, 2));
   ObjectSetString(0, "PEP_Eq", OBJPROP_TEXT, "Current Equity: $" + DoubleToString(equity, 2));
   ObjectSetString(0, "PEP_DD", OBJPROP_TEXT, "Daily Drawdown: " + DoubleToString(dd_percent, 2) + "% / Limit: " + DoubleToString(m_max_daily_loss, 2) + "%");

   color status_clr = clrLime;
   string status_txt = "Status: ACTIVE & MONITORING";

   if(m_limit_reached)
     {
      status_clr = clrRed;
      status_txt = "Status: BLOCKED - DAILY LIMIT HIT!";
     }
   else if(dd_percent >= m_max_daily_loss)
     {
      status_clr = clrRed;
      status_txt = "Status: HARD LIMIT HIT - MITIGATING!";
     }
   else if(m_enable_mitigation && dd_percent >= m_mitigation_loss)
     {
      status_clr = clrOrange;
      status_txt = "Status: WARNING - SOFT LIMIT HIT";
     }

   ObjectSetString(0, "PEP_Status", OBJPROP_TEXT, status_txt);
   ObjectSetInteger(0, "PEP_Status", OBJPROP_COLOR, status_clr);

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Delete all dashboard graphical objects                           |
//+------------------------------------------------------------------+
void CPropFirmProtector::ClearDashboard()
  {
   ObjectsDeleteAll(0, "PEP_");
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Partially close position with the highest floating loss          |
//+------------------------------------------------------------------+
void CPropFirmProtector::MitigateWorstPosition()
  {
   ulong  worst_ticket = 0;
   double max_loss     = 0.0;

//--- identify worst open position
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(profit < max_loss)
           {
            max_loss     = profit;
            worst_ticket = ticket;
           }
        }
     }

//--- execute partial close on worst ticket
   if(worst_ticket > 0)
     {
      if(PositionSelectByTicket(worst_ticket))
        {
         string symbol         = PositionGetString(POSITION_SYMBOL);
         double current_volume = PositionGetDouble(POSITION_VOLUME);
         double step           = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
         double min_vol        = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

         double volume_to_close = current_volume * (m_partial_close_pct / 100.0);
         volume_to_close        = MathFloor(volume_to_close / step) * step;

         if(volume_to_close < min_vol)
            volume_to_close = current_volume;

         int retries = 0;
         while(retries < m_max_retries)
           {
            if(m_trade.PositionClosePartial(worst_ticket, volume_to_close))
               break;
            else
              {
               Sleep(100);
               retries++;
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Aggressively close all positions and delete pending orders       |
//+------------------------------------------------------------------+
void CPropFirmProtector::CloseAllPositionsAndOrders()
  {
//--- close all open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         int retries = 0;
         while(retries < m_max_retries)
           {
            if(m_trade.PositionClose(ticket))
               break;
            else
              {
               Sleep(100);
               retries++;
              }
           }
        }
     }

//--- delete all pending orders
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
        {
         int retries = 0;
         while(retries < m_max_retries)
           {
            if(m_trade.OrderDelete(ticket))
               break;
            else
              {
               Sleep(100);
               retries++;
              }
           }
        }
     }
  }

//--- Global instance of the risk management class
CPropFirmProtector ExtProtector;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- start timer at 1 second intervals
   EventSetTimer(1);

//--- initialize protector instance
   if(!ExtProtector.Init(InpMaxDailyLossPercent, InpAutoCloseOnLimit, InpRemoveEAOnLimit,
                         InpMitigationLossPercent, InpEnableMitigation, InpPartialClosePercent,
                         InpSlippagePoints, InpSendPushNotification, InpMaxRetries))
     {
      Print("Error initializing CPropFirmProtector");
      return(INIT_FAILED);
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- stop timer and clean up
   EventKillTimer();
   ExtProtector.Deinit();
  }

//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer()
  {
//--- process equity risk management
   ExtProtector.OnTimerProcess();
  }
//+------------------------------------------------------------------+