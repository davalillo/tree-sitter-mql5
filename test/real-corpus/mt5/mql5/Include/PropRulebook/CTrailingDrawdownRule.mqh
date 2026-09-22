//+------------------------------------------------------------------+
//|                                        CTrailingDrawdownRule.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      Evaluates equity (or closed balance, per the        |
//|               profile's trailing mode) against a floor that       |
//|               ratchets UP with the account's peak and freezes     |
//|               permanently once the lock level is reached -- the   |
//|               ratcheting-floor mechanic.                          |
//| Failure mode: Trailing drawdown: a rule family many hand-rolled   |
//|               guards skip entirely, treating "maximum drawdown"   |
//|               as one thing -- which guards an account under a     |
//|               trailing programme with the wrong maths entirely.   |
//|                                                                   |
//|               Two invariants make this rule safe, and both are    |
//|               enforced structurally rather than by convention:    |
//|                                                                   |
//|               1. MONOTONIC FLOOR. RaiseFloor() is the only writer |
//|                  that runs during normal evaluation, and it takes |
//|                  the maximum of the old and new value. Configure()|
//|                  Reset() and Deserialize() also set m_floor, but  |
//|                  only to establish it fresh at challenge start or |
//|                  state restore -- never mid-challenge, never      |
//|                  downward, so a losing streak can never buy back  |
//|                  drawdown budget.                                 |
//|               2. ONE-WAY LOCK. Once balance reaches               |
//|                  initial_balance + trailing_amount, the floor is  |
//|                  pinned at (lock level - trailing amount) and     |
//|                  m_locked is never cleared except by Reset(). A   |
//|                  locked floor behaves exactly like a static one.  |
//|                                                                   |
//|               C5 -- ResetIntraday() exists here for the           |
//|               end-of-day trailing variant (that is where its peak |
//|               is allowed to advance) and it still cannot clear    |
//|               the breach latch or the lock.                       |
//| Dependencies: IPropRule.mqh                                       |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

#include "IPropRule.mqh"

//+------------------------------------------------------------------+
//| Trailing maximum drawdown with the lock mechanic.                |
//+------------------------------------------------------------------+
class CTrailingDrawdownRule : public IPropRule
{
private:
   double               m_anchor;        // challenge starting balance
   double               m_trail_amount;  // distance the floor keeps below the peak
   double               m_lock_level;    // balance level at which the floor freezes
   double               m_lock_level_override; // raw profile.trailing_lock_level (0.0 = no
                                                // explicit override -- resolve from the
                                                // anchor instead). Kept so Reset() can
                                                // re-resolve the SAME way Configure() did
                                                // instead of silently discarding an
                                                // explicit lock level on every full reset.
   bool                 m_lock_enabled;
   ENUM_PROP_TRAIL_MODE m_mode;

   double               m_peak;          // running high water mark the floor follows
   double               m_floor;         // monotonically non-decreasing
   bool                 m_locked;
   bool                 m_latched;

   //--- the ONLY writer of m_floor. Never lowers it.
   void RaiseFloor(const double candidate)
   {
      if(candidate > m_floor)
         m_floor = candidate;
   }

   //--- value the breach test compares against the floor
   double EvalValue(const PropAccountSnapshot &snap) const
   {
      return (m_mode == PROP_TRAIL_END_OF_DAY) ? snap.balance : snap.equity;
   }

public:
   CTrailingDrawdownRule()
      : IPropRule(PROP_RULE_TRAILING_DD),
        m_anchor(0.0), m_trail_amount(0.0), m_lock_level(0.0), m_lock_level_override(0.0),
        m_lock_enabled(true),
        m_mode(PROP_TRAIL_INTRADAY), m_peak(0.0), m_floor(0.0),
        m_locked(false), m_latched(false) {}

   double FloorLevel() const { return m_floor; }
   double Peak()       const { return m_peak; }
   double LockLevel()  const { return m_lock_level; }
   bool   IsLocked()   const { return m_locked; }
   bool   IsLatched()  const { return m_latched; }

   virtual bool Configure(const PropFirmProfile &profile, string &err)
   {
      m_configured = false;

      if(!profile.use_trailing_dd)
      {
         err = "trailing drawdown is disabled";
         return false;
      }
      if(profile.trailing_dd_amount <= 0.0)
      {
         err = "trailing_dd_amount is enabled but unset (0.0)";
         return false;
      }
      if(profile.initial_balance <= 0.0)
      {
         err = "trailing drawdown needs a positive initial_balance anchor";
         return false;
      }

      m_anchor              = profile.initial_balance;
      m_trail_amount        = profile.trailing_dd_amount;
      m_mode                = profile.trailing_mode;
      m_lock_enabled        = profile.trailing_lock_enabled;
      m_lock_level_override = profile.trailing_lock_level;   // 0.0 = none, kept raw
      m_lock_level          = profile.EffectiveLockLevel();
      m_buffer_ratio        = profile.safety_buffer_ratio;

      if(m_lock_enabled && m_lock_level <= m_anchor)
      {
         err = "trailing lock level must sit above the initial balance";
         return false;
      }

      m_peak       = m_anchor;
      m_floor      = m_anchor - m_trail_amount;
      m_locked     = false;
      m_latched    = false;
      m_configured = true;
      return true;
   }

   virtual void Evaluate(const PropAccountSnapshot &snap, PropRuleVerdict &out)
   {
      //--- 1. lock check first: reaching the lock level ends trailing for good
      if(m_lock_enabled && !m_locked && snap.balance >= m_lock_level)
      {
         m_locked = true;
         RaiseFloor(m_lock_level - m_trail_amount);
         PrintFormat("%s: floor locked at %.2f (balance %.2f reached the lock level %.2f) "
                     "-- it behaves as a static floor from here on.",
                     Name(), m_floor, snap.balance, m_lock_level);
      }

      //--- 2. ratchet, but only while unlocked
      if(!m_locked)
      {
         if(m_mode == PROP_TRAIL_END_OF_DAY)
         {
            //--- the closed-balance variant only advances at the rollover,
            //--- which ResetIntraday() drives; nothing to do intra-day
         }
         else
         {
            //--- intraday variant: floating profit counts toward the peak
            double candidate = MathMax(snap.balance, snap.equity);
            if(candidate > m_peak)
               m_peak = candidate;
            RaiseFloor(m_peak - m_trail_amount);
         }
      }

      //--- 3. breach test against the (never lowered) floor
      double value    = EvalValue(snap);
      double headroom = value - m_floor;
      double consumed = m_peak - value;

      if(m_latched || value <= m_floor)
      {
         bool first = !m_latched;
         m_latched  = true;

         Report(out, snap, PROP_SEV_BREACH, PROP_DIRECTIVE_LOCKDOWN,
                value, m_floor, headroom, "ccy",
                StringFormat("%s: %.2f at or below the trailing floor %.2f "
                             "(peak %.2f, trail %.2f, %s)%s",
                             Name(), value, m_floor, m_peak, m_trail_amount,
                             (m_locked ? "locked" : "trailing"),
                             (first ? "" : " [latched]")),
                true);
         return;
      }

      ENUM_PROP_SEVERITY severity = BufferSeverity(consumed, m_trail_amount);

      Report(out, snap, severity, PROP_DIRECTIVE_NONE,
             value, m_floor, headroom, "ccy",
             StringFormat("%s: floor %.2f (%s), peak %.2f, %.2f left",
                          Name(), m_floor, (m_locked ? "locked" : "trailing"),
                          m_peak, headroom));
   }

   //--- full challenge reset: re-anchor, unlock, unlatch
   virtual void Reset(const PropAccountSnapshot &snap)
   {
      if(snap.initial_balance > 0.0)
      {
         m_anchor = snap.initial_balance;
         if(!m_lock_enabled)
            m_lock_level = 0.0;
         else
         {
            //--- resolve the SAME way Configure()/profile.EffectiveLockLevel() does:
            //--- an explicit override survives a reset unchanged; only the default
            //--- (anchor + trail_amount) re-derives from the new anchor. Recomputing
            //--- unconditionally here used to silently drop an explicit lock level
            //--- and re-derive a looser one from the fresh anchor instead.
            double resolved = (m_lock_level_override > 0.0)
                               ? m_lock_level_override
                               : m_anchor + m_trail_amount;
            if(m_lock_level_override > 0.0 && resolved != m_lock_level)
               PrintFormat("%s: Reset() keeping the explicit lock level %.2f "
                           "(not re-derived from the new anchor %.2f)",
                           Name(), resolved, m_anchor);
            m_lock_level = resolved;
         }
      }
      m_peak    = m_anchor;
      m_floor   = m_anchor - m_trail_amount;
      m_locked  = false;
      m_latched = false;
   }

   //+---------------------------------------------------------------+
   //| Prop-day rollover. For the end-of-day trailing variant this is |
   //| the moment the peak is allowed to advance, using the CLOSED    |
   //| balance of the day that just ended. The floor still only moves |
   //| through RaiseFloor(), the lock is never undone and the breach  |
   //| latch is never cleared here (C5).                              |
   //+---------------------------------------------------------------+
   virtual void ResetIntraday(const PropAccountSnapshot &snap)
   {
      if(m_locked)
         return;
      if(m_mode != PROP_TRAIL_END_OF_DAY)
         return;

      if(snap.balance > m_peak)
         m_peak = snap.balance;
      RaiseFloor(m_peak - m_trail_amount);
   }

   virtual string Serialize() const
   {
      return StringFormat("%.2f,%.2f,%.2f,%.2f,%d,%d",
                          m_anchor, m_peak, m_floor, m_lock_level,
                          (m_locked ? 1 : 0), (m_latched ? 1 : 0));
   }

   virtual bool Deserialize(const string state)
   {
      string f[];
      if(StringSplit(state, (ushort)',', f) != 6)
         return false;

      double anchor = StringToDouble(f[0]);
      double peak   = StringToDouble(f[1]);
      double flr    = StringToDouble(f[2]);
      if(anchor <= 0.0 || peak <= 0.0)
         return false;

      double lock = StringToDouble(f[3]);

      //--- a lock level at or below the anchor would make the very first
      //--- comparison "balance >= lock" true and freeze the floor instantly:
      //--- exactly the zero-default instant-fire shape this package exists to
      //--- eliminate, so a file carrying one is rejected outright
      if(m_lock_enabled && lock <= anchor)
         return false;

      m_anchor     = anchor;
      m_peak       = peak;
      //--- restoring must never LOWER the floor either: take the higher of
      //--- the configured starting floor and the persisted one
      m_floor      = MathMax(m_floor, flr);
      if(m_lock_enabled)
         m_lock_level = lock;
      m_locked     = ((int)StringToInteger(f[4]) == 1);
      m_latched    = ((int)StringToInteger(f[5]) == 1);
      return true;
   }
};
//+------------------------------------------------------------------+
