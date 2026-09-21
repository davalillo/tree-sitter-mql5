//+------------------------------------------------------------------+
//|                                                CRuleRegistry.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Builds and owns the active rule table from a        |
//|               profile, refusing to register any rule whose        |
//|               parameters are absent, zero or otherwise            |
//|               unconfigured, and destroying every rule it created  |
//|               when it goes away.                                  |
//| Failure mode: The whole point of this class: a naive protection   |
//|               that is "on" whenever its threshold compares true,  |
//|               with every threshold defaulting to 0.0, means       |
//|               enabling it without typing a number leaves "equity  |
//|               >= 0" satisfied on the first tick and every tick    |
//|               afterwards -- the close-all routine runs            |
//|               continuously. Here there are exactly three possible |
//|               outcomes for a rule, and none of them is "fires by  |
//|               accident":                                          |
//|                                                                   |
//|                 flag off              -> never built, never in    |
//|                                          the table, produces no   |
//|                                          verdict at all           |
//|                 flag on, value unset  -> Build() FAILS and names  |
//|                                          the field, so Init()     |
//|                                          fails before the first   |
//|                                          tick                     |
//|                 flag on, value set    -> registered               |
//|                                                                   |
//|               A rule can therefore never exist in an              |
//|               unconfigured state, which is what makes the         |
//|               zero-threshold instant-fire mode unreachable.       |
//| Dependencies: IPropRule.mqh, PropFirmProfile.mqh,                 |
//|               CStaticDrawdownRule.mqh, CTrailingDrawdownRule.mqh, |
//|               CDailyLossRule.mqh, CProfitTargetRule.mqh,          |
//|               CConsistencyRule.mqh, CMinTradingDaysRule.mqh,      |
//|               CNewsWindowRule.mqh, CWeekendFlatRule.mqh           |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

#include "IPropRule.mqh"
#include "PropFirmProfile.mqh"
#include "CStaticDrawdownRule.mqh"
#include "CTrailingDrawdownRule.mqh"
#include "CDailyLossRule.mqh"
#include "CProfitTargetRule.mqh"
#include "CConsistencyRule.mqh"
#include "CMinTradingDaysRule.mqh"
#include "CNewsWindowRule.mqh"
#include "CWeekendFlatRule.mqh"

//+------------------------------------------------------------------+
//| Owns the active rule table.                                      |
//+------------------------------------------------------------------+
class CRuleRegistry
{
private:
   IPropRule *m_rules[];
   string     m_build_error;

   //--- Configure-or-destroy. The rule object only survives if it accepted
   //--- its parameters; a rejected rule is deleted here and now, so no
   //--- half-configured evaluator can ever reach the table.
   bool Register(IPropRule *rule, const PropFirmProfile &profile)
   {
      if(rule == NULL)
      {
         m_build_error = "out of memory while creating a rule";
         return false;
      }

      string err = "";
      if(!rule.Configure(profile, err))
      {
         m_build_error = rule.Name() + ": " + err;
         delete rule;
         return false;
      }

      int n = ArraySize(m_rules);
      if(ArrayResize(m_rules, n + 1) != n + 1)
      {
         m_build_error = "could not grow the rule table";
         delete rule;
         return false;
      }
      m_rules[n] = rule;
      return true;
   }

   //--- a rejected rule empties the whole table: a partially armed guard is
   //--- more dangerous than none, because it looks like it is protecting
   bool Fail(string &err)
   {
      err = m_build_error;
      Clear();
      return false;
   }

public:
   CRuleRegistry() : m_build_error("") {}
   ~CRuleRegistry() { Clear(); }

   void Clear()
   {
      for(int i = ArraySize(m_rules) - 1; i >= 0; i--)
      {
         if(m_rules[i] != NULL)
         {
            delete m_rules[i];
            m_rules[i] = NULL;
         }
      }
      ArrayFree(m_rules);
   }

   int        Count()      const { return ArraySize(m_rules); }
   string     BuildError() const { return m_build_error; }

   IPropRule *At(const int i) const
   {
      if(i < 0 || i >= ArraySize(m_rules))
         return NULL;
      return m_rules[i];
   }

   IPropRule *Find(const ENUM_PROP_RULE id) const
   {
      for(int i = 0; i < ArraySize(m_rules); i++)
         if(m_rules[i] != NULL && m_rules[i].Id() == id)
            return m_rules[i];
      return NULL;
   }

   bool IsRegistered(const ENUM_PROP_RULE id) const { return (Find(id) != NULL); }

   //+---------------------------------------------------------------+
   //| Builds the table. Returns false, with a named error in err,    |
   //| the moment any ENABLED rule refuses its parameters -- the      |
   //| table is left empty in that case rather than partially built,  |
   //| so a failed Init() cannot leave a half-armed guard behind.     |
   //+---------------------------------------------------------------+
   bool Build(const PropFirmProfile &profile, string &err)
   {
      Clear();
      m_build_error = "";
      err           = "";

      //--- account-level risk rules
      if(profile.use_static_dd && !Register(new CStaticDrawdownRule(), profile))
         return Fail(err);

      if(profile.use_trailing_dd && !Register(new CTrailingDrawdownRule(), profile))
         return Fail(err);

      //--- session-level risk rules
      if(profile.use_daily_loss && !Register(new CDailyLossRule(), profile))
         return Fail(err);

      //--- objective tracking
      if(profile.use_profit_target && !Register(new CProfitTargetRule(), profile))
         return Fail(err);

      //--- payout eligibility rules (advisory only, never account-killing)
      if(profile.use_consistency && !Register(new CConsistencyRule(), profile))
         return Fail(err);

      if(profile.use_min_trading_days && !Register(new CMinTradingDaysRule(), profile))
         return Fail(err);

      //--- conduct rules
      if(profile.use_news_window && !Register(new CNewsWindowRule(), profile))
         return Fail(err);

      if(profile.use_weekend_flat && !Register(new CWeekendFlatRule(), profile))
         return Fail(err);

      //--- an empty table is legal: a profile with every flag off guards
      //--- nothing, which is exactly what it asked for
      return true;
   }

   //--- one-line inventory, used by CPropRulebook::StatusReport()
   string Inventory() const
   {
      int n = ArraySize(m_rules);
      if(n == 0)
         return "no rules registered";

      string s = "";
      for(int i = 0; i < n; i++)
      {
         if(i > 0)
            s += ",";
         s += m_rules[i].Name();
      }
      return s;
   }
};
//+------------------------------------------------------------------+
