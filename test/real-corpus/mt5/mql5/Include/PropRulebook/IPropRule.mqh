//+------------------------------------------------------------------+
//|                                                    IPropRule.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Abstract base class defining the one contract every |
//|               rule evaluator implements: configure-or-refuse,     |
//|               evaluate a frozen snapshot into a verdict, and the  |
//|               mandatory separation between Reset() (a brand new   |
//|               challenge) and ResetIntraday() (a new prop day),    |
//|               plus per-rule state serialization for restart       |
//|               survival.                                           |
//| Failure mode: A rule may read the snapshot and write its own      |
//|               private state, and nothing else. It cannot see or   |
//|               touch another rule, and it cannot re-read live      |
//|               account state, so no rule can change the input      |
//|               another rule is about to be evaluated against.      |
//|               Reset() and ResetIntraday() are two different       |
//|               mandatory operations: collapsing them into a single |
//|               "reset monitoring state" routine means the daily    |
//|               rollover either clears everything (including        |
//|               account-level latches) or nothing (leaving intraday |
//|               protections permanently disarmed after one firing). |
//|               Here the rollover calls ResetIntraday() only, and   |
//|               ResetIntraday() is forbidden from clearing an       |
//|               account-level latch or moving an anchor. Every      |
//|               stateful rule serializes itself through this        |
//|               contract, so CGuardStateStore can restore the       |
//|               consumed drawdown budget after a VPS restart.       |
//| Dependencies: PropAccountSnapshot.mqh, PropRuleVerdict.mqh,       |
//|               PropFirmProfile.mqh                                 |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+
#include "PropAccountSnapshot.mqh"
#include "PropRuleVerdict.mqh"
#include "PropFirmProfile.mqh"

//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

//| The rule contract.                                                |
//|                                                                   |
//| Lifecycle, in the exact order the facade drives it:               |
//|   1. Configure(profile, err) -- once, at Init. Returning false    |
//|      means "my parameters are not usable"; CRuleRegistry then     |
//|      refuses to register this rule at all (C1).                   |
//|   2. Deserialize(state)      -- optional, once, if persisted      |
//|      state was restored.                                          |
//|   3. ResetIntraday(snapshot) -- at every prop-day rollover,       |
//|      driven by the coordinator BEFORE the evaluation phase.       |
//|   4. Evaluate(snapshot, out) -- once per pass, read-only against  |
//|      the snapshot, write-only against this rule's own fields.     |
//|   5. Reset(snapshot)         -- has exactly two legitimate         |
//|      callers: CPropRulebook::ResetChallenge(), and the        |
//|      restore-rollback branch inside Init().                       |
//+------------------------------------------------------------------+
class IPropRule
{
protected:
   ENUM_PROP_RULE   m_id;
   bool             m_configured;
   double           m_buffer_ratio;   // profile.safety_buffer_ratio, for WARNING severity
   PropRuleVerdict  m_last;

   //--- helper every concrete rule uses to fill its verdict, so the
   //--- unit/rule/stamp bookkeeping is written in exactly one place
   void Report(PropRuleVerdict &out,
               const PropAccountSnapshot &snap,
               const ENUM_PROP_SEVERITY severity,
               const ENUM_PROP_DIRECTIVE directive,
               const double measured,
               const double threshold,
               const double headroom,
               const string unit,
               const string message,
               const bool latched = false)
   {
      out.Clear();
      out.rule      = m_id;
      out.evaluated = true;
      out.abstained = false;
      out.latched   = latched;
      out.severity  = severity;
      out.directive = directive;
      out.measured  = measured;
      out.threshold = threshold;
      out.headroom  = headroom;
      out.unit      = unit;
      out.message   = message;
      out.stamp     = snap.server_time;
      m_last        = out;
   }

   //--- the rule is registered but this pass gave it nothing usable
   //--- (the calendar feed being unavailable is the canonical case)
   void Abstain(PropRuleVerdict &out,
                const PropAccountSnapshot &snap,
                const string message)
   {
      out.Clear();
      out.rule      = m_id;
      out.evaluated = true;
      out.abstained = true;
      out.severity  = PROP_SEV_OK;
      out.directive = PROP_DIRECTIVE_NONE;
      out.message   = message;
      out.stamp     = snap.server_time;
      m_last        = out;
   }

   //--- WARNING once the consumed share of a limit passes the buffer
   ENUM_PROP_SEVERITY BufferSeverity(const double consumed, const double limit) const
   {
      if(limit <= 0.0)
         return PROP_SEV_OK;
      if(consumed >= limit * m_buffer_ratio)
         return PROP_SEV_WARNING;
      return PROP_SEV_OK;
   }

public:
   IPropRule(const ENUM_PROP_RULE id)
      : m_id(id), m_configured(false), m_buffer_ratio(0.8) {}

   virtual ~IPropRule() {}

   ENUM_PROP_RULE Id()         const { return m_id; }
   string         Name()       const { return PropRuleName(m_id); }
   bool           IsConfigured() const { return m_configured; }

   //--- last verdict this rule produced (a copy: callers cannot edit it)
   PropRuleVerdict Last()      const { return m_last; }
   double          Headroom()  const { return m_last.headroom; }
   string          Unit()      const { return m_last.unit; }

   //+---------------------------------------------------------------+
   //| Reads the rule's own slice of the profile. MUST return false   |
   //| (with a human-readable err) when the rule is switched on but   |
   //| its threshold is unset -- never "fall back to a default", the  |
   //| silent-default habit is exactly what caused C1.                |
   //+---------------------------------------------------------------+
   virtual bool Configure(const PropFirmProfile &profile, string &err) = 0;

   //+---------------------------------------------------------------+
   //| One pass. Read snap, write out and this rule's own fields.     |
   //| Forbidden: calling any terminal state function, touching       |
   //| another rule, triggering any reset.                            |
   //+---------------------------------------------------------------+
   virtual void Evaluate(const PropAccountSnapshot &snap, PropRuleVerdict &out) = 0;

   //+---------------------------------------------------------------+
   //| Full challenge reset. Clears account-level latches and         |
   //| re-anchors whatever the rule anchors. Reachable only from      |
   //| CPropRulebook::ResetChallenge() and the restore-rollback   |
   //| branch inside Init() -- never from a routine trigger.          |
   //+---------------------------------------------------------------+
   virtual void Reset(const PropAccountSnapshot &snap) = 0;

   //+---------------------------------------------------------------+
   //| Prop-day boundary. Rearms intraday latches and rebases         |
   //| per-day baselines. MUST NOT clear an account-level latch and   |
   //| MUST NOT move a challenge anchor or a trailing lock (C4/C5).   |
   //+---------------------------------------------------------------+
   virtual void ResetIntraday(const PropAccountSnapshot &snap) = 0;

   //+---------------------------------------------------------------+
   //| Restart survival (C9). Serialize() returns a single line with  |
   //| no '=' and no newline; Deserialize() must reject anything it   |
   //| does not fully understand by returning false, so the store can |
   //| fall back to a fresh anchor instead of loading partial data.   |
   //+---------------------------------------------------------------+
   virtual string Serialize()  const              { return ""; }
   virtual bool   Deserialize(const string state) { return (StringLen(state) == 0); }
};
//+------------------------------------------------------------------+
