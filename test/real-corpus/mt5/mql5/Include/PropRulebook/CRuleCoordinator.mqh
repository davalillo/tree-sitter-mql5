//+------------------------------------------------------------------+
//|                                             CRuleCoordinator.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Resolves the independently produced verdicts of one |
//|               pass into AT MOST ONE terminal directive, without   |
//|               letting any rule's outcome mutate another rule's    |
//|               state mid-pass, and drives the two reset operations |
//|               across the whole rule table outside the evaluation  |
//|               phase.                                              |
//| Failure mode: The pass is strictly two-phase. Phase one calls     |
//|               Evaluate() on every registered rule against the     |
//|               same frozen snapshot and stores the verdicts;       |
//|               nothing acts during phase one. Phase two reads only |
//|               those stored verdicts and picks one winner. Because |
//|               no protective action can run while rules are still  |
//|               being evaluated, the classic cascade failure -- a   |
//|               close-all fired in the middle of the trigger loop,  |
//|               clearing flags of triggers not yet checked and      |
//|               cascading into a dozen firings -- has nowhere to    |
//|               happen. One directive per pass also means a single  |
//|               pass can never request "disable trading" and        |
//|               "enable trading" at the same time, which is exactly |
//|               how a naive cascade can end up toggling the Algo    |
//|               Trading button off and straight back on in the same |
//|               tick. DriveIntradayReset() and DriveFullReset() are |
//|               separate operations and both run OUTSIDE the        |
//|               evaluation phase. The daily one is called by the    |
//|               facade at a prop-day rollover; the full one only    |
//|               from ResetChallenge(). A profit-target FLATTEN is   |
//|               vetoed here when the consistency verdict's          |
//|               projected share says banking that profit today      |
//|               would break the payout ceiling: a naive             |
//|               Close_Positions_On_Profit=true behaviour does the   |
//|               opposite, creating the violation it should prevent. |
//| Dependencies: CRuleRegistry.mqh, PropAccountSnapshot.mqh,         |
//|               PropRuleVerdict.mqh                                 |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

#include "CRuleRegistry.mqh"
#include "PropAccountSnapshot.mqh"
#include "PropRuleVerdict.mqh"

//+------------------------------------------------------------------+
//| Two-phase pass resolver.                                         |
//+------------------------------------------------------------------+
class CRuleCoordinator
{
private:
   ENUM_PROP_DIRECTIVE m_directive;
   ENUM_PROP_RULE      m_source;
   string              m_reason;
   bool                m_downgraded;
   string              m_downgrade_reason;
   int                 m_breach_count;

   //+---------------------------------------------------------------+
   //| P5 veto. Looks for the consistency verdict of THIS pass and    |
   //| asks whether realizing today's open profit would push the      |
   //| best-day share past the ceiling. Returns true when the flatten |
   //| must be downgraded.                                            |
   //+---------------------------------------------------------------+
   bool ConsistencyVetoesFlatten(const PropRuleVerdict &verdicts[], string &why)
   {
      int n = ArraySize(verdicts);
      for(int i = 0; i < n; i++)
      {
         if(verdicts[i].rule != PROP_RULE_CONSISTENCY)
            continue;
         if(!verdicts[i].evaluated)
            return false;
         if(verdicts[i].threshold <= 0.0)
            return false;

         if(verdicts[i].projected > verdicts[i].threshold)
         {
            why = StringFormat("banking the open profit now would make the best day "
                               "%.1f%% of total profit, above the %.1f%% consistency "
                               "ceiling (currently %.1f%%)",
                               verdicts[i].projected * 100.0,
                               verdicts[i].threshold * 100.0,
                               verdicts[i].measured * 100.0);
            return true;
         }
         return false;
      }
      return false;
   }

public:
   CRuleCoordinator()
      : m_directive(PROP_DIRECTIVE_NONE), m_source(PROP_RULE_NONE), m_reason(""),
        m_downgraded(false), m_downgrade_reason(""), m_breach_count(0) {}

   ENUM_PROP_DIRECTIVE Directive()       const { return m_directive; }
   ENUM_PROP_RULE      SourceRule()      const { return m_source; }
   string              Reason()          const { return m_reason; }
   bool                WasDowngraded()   const { return m_downgraded; }
   string              DowngradeReason() const { return m_downgrade_reason; }
   int                 BreachCount()     const { return m_breach_count; }

   //+---------------------------------------------------------------+
   //| One complete pass.                                             |
   //|                                                                |
   //| verdicts[] is resized to the rule count and filled in registry |
   //| order, so the caller can log or display every rule's finding   |
   //| even though only one directive survives.                       |
   //+---------------------------------------------------------------+
   ENUM_PROP_DIRECTIVE RunPass(CRuleRegistry *registry,
                               const PropAccountSnapshot &snap,
                               PropRuleVerdict &verdicts[],
                               string &reason)
   {
      m_directive        = PROP_DIRECTIVE_NONE;
      m_source           = PROP_RULE_NONE;
      m_reason           = "";
      m_downgraded       = false;
      m_downgrade_reason = "";
      m_breach_count     = 0;
      reason             = "";

      if(registry == NULL)
         return PROP_DIRECTIVE_NONE;

      int n = registry.Count();
      ArrayResize(verdicts, n);
      if(n == 0)
         return PROP_DIRECTIVE_NONE;

      //--- PHASE 1: evaluate everything, act on nothing ---------------
      for(int i = 0; i < n; i++)
      {
         IPropRule *rule = registry.At(i);
         verdicts[i].Clear();
         if(rule == NULL)
            continue;
         rule.Evaluate(snap, verdicts[i]);
         if(verdicts[i].IsBreach())
            m_breach_count++;
      }

      //--- PHASE 2: resolve one winner from the stored verdicts -------
      //--- No rule object is touched again from here on, so nothing in
      //--- this phase can alter what another rule already reported.
      string veto_why = "";
      bool   veto     = ConsistencyVetoesFlatten(verdicts, veto_why);

      for(int i = 0; i < n; i++)
      {
         if(!verdicts[i].evaluated || verdicts[i].abstained)
            continue;

         ENUM_PROP_DIRECTIVE effective = verdicts[i].directive;

         //--- P5: the only directive that can be downgraded, and only
         //--- when it comes from the profit target and only on the
         //--- consistency rule's own projection
         if(veto &&
            verdicts[i].rule == PROP_RULE_PROFIT_TARGET &&
            effective == PROP_DIRECTIVE_FLATTEN)
         {
            effective          = PROP_DIRECTIVE_ADVISORY;
            m_downgraded       = true;
            m_downgrade_reason = veto_why;

            //--- the downgrade is written back so every consumer of the
            //--- verdict list (CanOpen(), StatusReport(), a panel) sees the
            //--- same decision the coordinator acted on
            verdicts[i].directive = effective;
            verdicts[i].message  += " | flatten downgraded to advisory (consistency)";
         }

         if(PropDirectiveRank(effective) > PropDirectiveRank(m_directive))
         {
            m_directive = effective;
            m_source    = verdicts[i].rule;
            m_reason    = verdicts[i].message;
         }
      }

      if(m_downgraded)
      {
         string note = StringFormat("profit-target flatten downgraded to advisory: %s",
                                    m_downgrade_reason);
         m_reason = (StringLen(m_reason) > 0) ? (m_reason + " | " + note) : note;
      }

      reason = m_reason;
      return m_directive;
   }

   //+---------------------------------------------------------------+
   //| C5. Prop-day boundary, driven across the whole table BEFORE    |
   //| the evaluation phase of the pass that detected the rollover.   |
   //| Each rule decides for itself what a new day means to it: the   |
   //| daily loss rule rearms, the end-of-day trailing rule advances  |
   //| its peak, the account-level rules do nothing at all.           |
   //+---------------------------------------------------------------+
   void DriveIntradayReset(CRuleRegistry *registry, const PropAccountSnapshot &snap)
   {
      if(registry == NULL)
         return;
      for(int i = 0; i < registry.Count(); i++)
      {
         IPropRule *rule = registry.At(i);
         if(rule != NULL)
            rule.ResetIntraday(snap);
      }
   }

   //+---------------------------------------------------------------+
   //| C4. Full challenge reset. Reachable from                       |
   //| CPropRulebook::ResetChallenge() and the restore-rollback   |
   //| branch inside Init() -- the only two operations allowed to     |
   //| clear an account-level breach latch or move an anchor.         |
   //+---------------------------------------------------------------+
   void DriveFullReset(CRuleRegistry *registry, const PropAccountSnapshot &snap)
   {
      if(registry == NULL)
         return;
      for(int i = 0; i < registry.Count(); i++)
      {
         IPropRule *rule = registry.At(i);
         if(rule != NULL)
            rule.Reset(snap);
      }
   }
};
//+------------------------------------------------------------------+
