//+------------------------------------------------------------------+
//|                                              PropRuleVerdict.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Data record plus the rule-id, severity and         |
//|               directive enumerations describing the single       |
//|               outcome one rule reports for one evaluation pass.  |
//|               A verdict is a report, not an action: it says what |
//|               a rule measured and what it would like done, and   |
//|               nothing in this file executes anything.            |
//| Failure mode: C2 -- separating "what each rule found" from "what |
//|               the guard does about it" is what allows            |
//|               CRuleCoordinator to run a strict evaluate-all-then-|
//|               resolve pass and emit at most one directive, so    |
//|               eight breaching rules can never produce eight      |
//|               protective actions.                                |
//| Dependencies: none                                               |
//| Part of:      PropFirm Guard class package                    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Identity of every rule the guard can register.                   |
//+------------------------------------------------------------------+
enum ENUM_PROP_RULE
{
   PROP_RULE_NONE             = 0,   // (no rule)
   PROP_RULE_STATIC_DD        = 1,   // Static maximum drawdown
   PROP_RULE_TRAILING_DD      = 2,   // Trailing maximum drawdown
   PROP_RULE_DAILY_LOSS       = 3,   // Daily loss limit
   PROP_RULE_PROFIT_TARGET    = 4,   // Profit target
   PROP_RULE_CONSISTENCY      = 5,   // Payout consistency
   PROP_RULE_MIN_TRADING_DAYS = 6,   // Minimum trading days
   PROP_RULE_NEWS_WINDOW      = 7,   // High-impact news blackout
   PROP_RULE_WEEKEND_FLAT     = 8    // Pre-weekend flat cutoff
};

//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

//| How serious the finding is. Severity never selects an action --   |
//| the directive does. A rule never has to reach for BREACH just     |
//| because something is wrong -- the consistency rule can still warn |
//| early, inside its safety buffer, but never emits BREACH at all,   |
//| since violating it blocks a payout instead of putting the         |
//| account at risk.                                                  |
//+------------------------------------------------------------------+
enum ENUM_PROP_SEVERITY
{
   PROP_SEV_OK       = 0,   // within limits
   PROP_SEV_INFO     = 1,   // informational progress report
   PROP_SEV_WARNING  = 2,   // inside the safety buffer, not breached
   PROP_SEV_ADVISORY = 3,   // a payout-blocking condition, account is safe
   PROP_SEV_BREACH   = 4    // the firm's limit itself is violated
};

//+------------------------------------------------------------------+
//| What a rule asks the guard to do. Ordered by escalation so that   |
//| PropDirectiveRank() can pick a single winner per pass.            |
//+------------------------------------------------------------------+
enum ENUM_PROP_DIRECTIVE
{
   PROP_DIRECTIVE_NONE              = 0,   // nothing to do
   PROP_DIRECTIVE_ADVISORY          = 1,   // log/notify only, never touches the account
   PROP_DIRECTIVE_BLOCK_NEW_ENTRIES = 2,   // CanOpen() must return false
   PROP_DIRECTIVE_FLATTEN           = 3,   // close relevant exposure, keep trading enabled
   PROP_DIRECTIVE_LOCKDOWN          = 4    // close exposure AND disable Algo Trading
};

//+------------------------------------------------------------------+
//| Escalation rank of a directive. Higher wins when the coordinator |
//| resolves a pass into one terminal directive.                     |
//+------------------------------------------------------------------+
int PropDirectiveRank(const ENUM_PROP_DIRECTIVE directive)
{
   return (int)directive;
}

//+------------------------------------------------------------------+
//| Human-readable names, used by StatusReport() and journal output. |
//+------------------------------------------------------------------+
string PropRuleName(const ENUM_PROP_RULE rule)
{
   switch(rule)
   {
      case PROP_RULE_STATIC_DD:        return "StaticDD";
      case PROP_RULE_TRAILING_DD:      return "TrailingDD";
      case PROP_RULE_DAILY_LOSS:       return "DailyLoss";
      case PROP_RULE_PROFIT_TARGET:    return "ProfitTarget";
      case PROP_RULE_CONSISTENCY:      return "Consistency";
      case PROP_RULE_MIN_TRADING_DAYS: return "MinTradingDays";
      case PROP_RULE_NEWS_WINDOW:      return "NewsWindow";
      case PROP_RULE_WEEKEND_FLAT:     return "WeekendFlat";
      default:                         return "None";
   }
}

string PropSeverityName(const ENUM_PROP_SEVERITY severity)
{
   switch(severity)
   {
      case PROP_SEV_INFO:     return "INFO";
      case PROP_SEV_WARNING:  return "WARN";
      case PROP_SEV_ADVISORY: return "ADVISORY";
      case PROP_SEV_BREACH:   return "BREACH";
      default:                return "OK";
   }
}

string PropDirectiveName(const ENUM_PROP_DIRECTIVE directive)
{
   switch(directive)
   {
      case PROP_DIRECTIVE_ADVISORY:          return "ADVISORY";
      case PROP_DIRECTIVE_BLOCK_NEW_ENTRIES: return "BLOCK_NEW_ENTRIES";
      case PROP_DIRECTIVE_FLATTEN:           return "FLATTEN";
      case PROP_DIRECTIVE_LOCKDOWN:          return "LOCKDOWN";
      default:                               return "NONE";
   }
}

//+------------------------------------------------------------------+
//| One rule's report for one pass.                                  |
//|                                                                  |
//| measured / threshold / headroom are expressed in whatever unit    |
//| the rule works in (account currency for the drawdown rules, a     |
//| 0..1 share for consistency, days for minimum trading days,        |
//| minutes for the news and weekend rules) -- the unit string says   |
//| which, so a panel or the journal can format it without knowing    |
//| the rule.                                                         |
//+------------------------------------------------------------------+
struct PropRuleVerdict
{
   ENUM_PROP_RULE      rule;
   bool                evaluated;   // false when the rule is not registered at all
   bool                abstained;   // rule registered but had no usable input this pass
   bool                latched;     // rule is holding a breach latch from an earlier pass
   ENUM_PROP_SEVERITY  severity;
   ENUM_PROP_DIRECTIVE directive;
   double              measured;    // what the rule observed
   double              threshold;   // the limit it was compared against
   double              headroom;    // distance still available before breach
   double              projected;   // forward-looking figure, rule specific (see CConsistencyRule)
   string              unit;        // "ccy", "share", "days", "minutes"
   string              message;
   datetime            stamp;

   PropRuleVerdict() { Clear(); }

   void Clear()
   {
      rule      = PROP_RULE_NONE;
      evaluated = false;
      abstained = false;
      latched   = false;
      severity  = PROP_SEV_OK;
      directive = PROP_DIRECTIVE_NONE;
      measured  = 0.0;
      threshold = 0.0;
      headroom  = 0.0;
      projected = 0.0;
      unit      = "ccy";
      message   = "";
      stamp     = 0;
   }

   bool IsBreach() const { return severity == PROP_SEV_BREACH; }

   string ToString() const
   {
      if(!evaluated)
         return PropRuleName(rule) + "=off";
      if(abstained)
         return PropRuleName(rule) + "=abstain";
      return StringFormat("%s=%s[%s] m=%.2f/%.2f hr=%.2f%s",
                          PropRuleName(rule),
                          PropSeverityName(severity),
                          PropDirectiveName(directive),
                          measured, threshold, headroom,
                          (latched ? " LATCHED" : ""));
   }
};
//+------------------------------------------------------------------+
