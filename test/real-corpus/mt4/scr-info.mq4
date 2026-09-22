//+------------------------------------------------------------------+
//|                                                     scr-info.mq4 |
//|                                                        F.soltani |
//|                                            https://forge.mql5.io |
//+------------------------------------------------------------------+
#property copyright "F.soltani"
#property link      "https://forge.mql5.io"
#property version   "1.00"
#property strict
//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
  {
//--- Information
   string company=AccountInfoString(ACCOUNT_COMPANY);
   string server=AccountInfoString(ACCOUNT_SERVER);
//---
   ENUM_ACCOUNT_TRADE_MODE account_type=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   string trade_mode;
   switch(account_type)
     {
      case  ACCOUNT_TRADE_MODE_DEMO   :trade_mode="Demo";break;
      case  ACCOUNT_TRADE_MODE_CONTEST:trade_mode="Contest";break;
      default:trade_mode="Real";break;
     }
//---
   string account_name=AccountInfoString(ACCOUNT_NAME);
   int login=(int)AccountInfoInteger(ACCOUNT_LOGIN);
   bool thisAccountTradeAllowed=AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
   bool EATradeAllowed=AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
   long leverage=AccountInfoInteger(ACCOUNT_LEVERAGE);
   double deposit=AccountInfoDouble(ACCOUNT_CREDIT);
   double balance=AccountBalance();
   string currency=AccountInfoString(ACCOUNT_CURRENCY);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double magin=AccountInfoDouble(ACCOUNT_MARGIN);
   double free_margin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double profit=AccountInfoDouble(ACCOUNT_PROFIT);
   double margin_level=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   double min_lot=MODE_MINLOT;
   double max_lot=MODE_MAXLOT;
   double lot_step=MODE_LOTSTEP;
   double FREEZELEVEL=MODE_FREEZELEVEL;
   double Spread=MODE_SPREAD;
   double point=Point;
   double TICKSIZE=MODE_TICKSIZE;
   double TICKVALUE=MODE_TICKVALUE;
   double MARGINHEDGED=MODE_MARGINHEDGED;
   double MARGINREQUIRED=MODE_MARGINREQUIRED;
   double lot_standard=SymbolInfoDouble(NULL,SYMBOL_TRADE_CONTRACT_SIZE);
//---
   ENUM_ACCOUNT_STOPOUT_MODE stop_out_mode=(ENUM_ACCOUNT_STOPOUT_MODE)AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE);
   double margin_call=AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL);
   double stop_out=AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);
//---
   printf("Broker Name= %s",company);
   printf("Server Name= %s",server);
   printf("Type Account= %s",trade_mode);
   printf("Accoun Name= %s",account_name);
   printf("User Account= %#%d#",login);
   if(thisAccountTradeAllowed) printf("Trade Account= Enable");
   else                        printf("Trade Account= Disable!");
   if(EATradeAllowed) Print("Trade With Expert= Enable");
   else                        Print("Trade With Expert= Disable");
   printf("Deposit= %G",deposit);
   printf("Contract Size= %G",lot_standard);
   printf("Leverage= 1:%I64d",leverage);
   printf("Balance= %.2f %s",balance,currency);
   printf("Account Equity= %.2f %s",equity,currency);
   printf("Account Margin= %.2f %s",magin,currency);
   printf("Account Free Margin= %.2f %s",free_margin,currency);
   printf("Profit= %.2f %s",profit,currency);
//---
   printf("MarginCall and StopOut levels are set in %s",(stop_out_mode==ACCOUNT_STOPOUT_MODE_PERCENT)?"Percentage":" money");
   printf("MarginLevel=%G , MarginCall=%G , StopOut=%G",margin_level,margin_call,stop_out);
   printf("MIN LOT=%G , MAX LOT=%G , Lot Step=%G",min_lot,max_lot,lot_step);
   printf("FREEZE LEVEL=%G , Point=%f , Spread=%G",FREEZELEVEL,DoubleToStr(point,Digits),Spread);
   printf("TICK SIZE=%G , TICK VALUE=%G , MARGIN HEDGED=%G , MARGIN REQUIRED=%G",DoubleToStr(TICKSIZE,Digits),DoubleToStr(TICKVALUE,Digits),MARGINHEDGED,MARGINREQUIRED);
//---
  }
//+------------------------------------------------------------------+
