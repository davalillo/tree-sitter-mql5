//+------------------------------------------------------------------+
//|                                          CTerminalAlgoSwitch.mqh |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+

#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

//| Purpose:      Drives the terminal's global Algo Trading button    |
//|               through a pending latch that verifies the requested |
//|               state on LATER passes and escalates when the        |
//|               request did not take effect.                        |
//| Failure mode: M1 -- there is no native MQL5 call that switches    |
//|               global Algo Trading on or off. TERMINAL_TRADE_      |
//|               ALLOWED and MQL_TRADE_ALLOWED are read-only         |
//|               properties, so the only available route is the      |
//|               WinAPI one: post the terminal's own menu command    |
//|               (WM_COMMAND, id 32851) to its main window. That     |
//|               command is a TOGGLE, not a setter, so the current   |
//|               state has to be read before anything is posted --   |
//|               posting blindly when the button is already in the   |
//|               wanted position turns it the wrong way. It also     |
//|               needs DLL imports, so this class owns the           |
//|               permission check too, and Init() refuses to         |
//|               initialise rather than becoming a silent no-op.     |
//| DLL caveat:   the #import below is resolved by the terminal at    |
//|               PROGRAM INITIALISATION, before OnInit()/OnStart()   |
//|               runs. Measured on build 6120: with "Allow DLL       |
//|               imports" OFF the terminal logs "DLL loading is not  |
//|               allowed" and "initializing of <program> failed with |
//|               code 0", and not one line of MQL5 executes. So the  |
//|               TERMINAL_DLLS_ALLOWED check in Init() is a belt-    |
//|               and-braces guard, NOT a graceful-degradation path:  |
//|               any program that includes this header inherits a    |
//|               hard dependency on the permission and simply will   |
//|               not start without it. That is the honest trade-off  |
//|               of the only route MQL5 leaves open -- there is no   |
//|               conditional or lazy DLL binding in the language.    |
//|               C7 -- PostMessage is asynchronous and fire-and-     |
//|               forget: a guard that reads TERMINAL_TRADE_ALLOWED   |
//|               immediately after posting always sees the old       |
//|               value, and concludes the action failed (or, on the  |
//|               profit path, that it never needed to reset),        |
//|               leaving its protection permanently disarmed. Here a |
//|               request only sets a latch; verification happens on  |
//|               a subsequent Update() call, against a deadline,     |
//|               with a bounded number of re-posts, and the final    |
//|               state is one of SETTLED or UNRECOVERABLE -- never   |
//|               an assumed success.                                 |
//|               C3 -- while a disable latch is outstanding or       |
//|               settled, an enable request is REFUSED outright and  |
//|               not queued, so no sequence of events can turn       |
//|               trading back on behind the trader's back. Only      |
//|               ClearLatch() lifts that refusal, and it has exactly |
//|               two legitimate callers: ResetChallenge(), and the   |
//|               restore-rollback branch inside Init() that falls    |
//|               back to a fresh challenge when persisted state      |
//|               can't be trusted.                                   |
//| Dependencies: none                                                |
//| Part of:      PropFirm Guard class package                     |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| WinAPI. The 64-bit terminal passes window handles as 8-byte       |
//| values, so HWND is imported as long, not int.                     |
//+------------------------------------------------------------------+
//| PROP_MARKET_BUILD: the MQL5 Market forbids EVERY DLL call, including    |
//| Windows system libraries (mql5.com/en/market/rules), and the automatic  |
//| validation rejects a product that imports one. Defining this macro      |
//| before including the package compiles the same class without the import |
//| at all: the switch reports itself unavailable and the guard keeps       |
//| blocking entries and flattening, neither of which ever needed the DLL.  |
#ifndef PROP_MARKET_BUILD
#import "user32.dll"
   int  PostMessageW(long hWnd, uint Msg, long wParam, long lParam);
   long GetAncestor(long hWnd, uint gaFlags);
#import
#endif

#define PROP_WM_COMMAND        0x0111   // standard Windows menu/command message
#define PROP_ALGO_COMMAND_ID   32851    // MetaTrader 5 "Algo Trading" menu command
#define PROP_GA_ROOT           2        // GetAncestor: walk up to the root window

//+------------------------------------------------------------------+
//| State of the pending latch.                                      |
//+------------------------------------------------------------------+
enum ENUM_ALGO_LATCH
{
   ALGO_LATCH_IDLE          = 0,  // no request outstanding
   ALGO_LATCH_PENDING       = 1,  // requested, not yet observed to have taken effect
   ALGO_LATCH_SETTLED       = 2,  // observed in the requested state
   ALGO_LATCH_UNRECOVERABLE = 3   // attempts exhausted, the terminal did not comply
};

//+------------------------------------------------------------------+
//| Pending-latch driver for the global Algo Trading button.         |
//+------------------------------------------------------------------+
class CTerminalAlgoSwitch
{
private:
   bool            m_required;        // the profile asks for this actuator at all
   bool            m_ready;
   bool            m_desired_state;   // the state we asked the terminal for
   ENUM_ALGO_LATCH m_latch;
   bool            m_disable_held;    // a disable was requested and must not be undone
   int             m_attempts;
   int             m_max_attempts;
   int             m_verify_seconds;
   datetime        m_request_time;
   datetime        m_last_post_time;
   bool            m_notify;
   long            m_main_window;

   //--- resolves the terminal's main window from the chart window
   long ResolveMainWindow()
   {
#ifdef PROP_MARKET_BUILD
      return 0;                       // no WinAPI in a Market build
#else
      long chart_hwnd = ChartGetInteger(0, CHART_WINDOW_HANDLE);
      if(chart_hwnd == 0)
         return 0;

      long root = GetAncestor(chart_hwnd, (uint)PROP_GA_ROOT);
      return (root != 0) ? root : chart_hwnd;
#endif
   }

   //+---------------------------------------------------------------+
   //| Posts the toggle ONCE, and only when the button is currently   |
   //| in the wrong position. Returns false when the message could    |
   //| not even be posted.                                            |
   //+---------------------------------------------------------------+
   bool PostToggle()
   {
      bool actual = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
      if(actual == m_desired_state)
         return true;                 // nothing to toggle: already correct

#ifdef PROP_MARKET_BUILD
      //--- no DLL in this build, so there is no way to post the command.
      //--- Say so once and let the caller escalate honestly rather than
      //--- report a success that never happened (C7).
      Print("CTerminalAlgoSwitch: the global Algo Trading switch is unavailable in "
            "this build -- the MQL5 Market forbids DLL calls. Entries stay blocked "
            "and positions are still flattened; flip the button yourself if you "
            "want the terminal-wide switch off as well.");
      return false;
#else
      if(m_main_window == 0)
         m_main_window = ResolveMainWindow();

      if(m_main_window == 0)
      {
         Print("CTerminalAlgoSwitch: could not resolve the terminal main window handle");
         return false;
      }

      ResetLastError();
      int posted = PostMessageW(m_main_window, (uint)PROP_WM_COMMAND,
                                (long)PROP_ALGO_COMMAND_ID, (long)0);

      m_attempts++;
      m_last_post_time = TimeCurrent();

      if(posted == 0)
      {
         PrintFormat("CTerminalAlgoSwitch: PostMessageW failed (attempt %d/%d, error %d)",
                     m_attempts, m_max_attempts, GetLastError());
         return false;
      }

      PrintFormat("CTerminalAlgoSwitch: toggle posted, attempt %d/%d, waiting for the "
                  "terminal to report TERMINAL_TRADE_ALLOWED=%s",
                  m_attempts, m_max_attempts, (m_desired_state ? "true" : "false"));
      return true;
#endif
   }

   void Escalate()
   {
      m_latch = ALGO_LATCH_UNRECOVERABLE;

      string text = StringFormat("PropFirm Guard: could NOT set Algo Trading to %s after "
                                 "%d attempts. Switch it manually NOW -- the guard cannot "
                                 "confirm the account is protected.",
                                 (m_desired_state ? "ON" : "OFF"), m_attempts);
      Print(text);
      Alert(text);
      if(m_notify)
         SendNotification(text);
   }

public:
   CTerminalAlgoSwitch()
      : m_required(false), m_ready(false), m_desired_state(true),
        m_latch(ALGO_LATCH_IDLE), m_disable_held(false), m_attempts(0),
        m_max_attempts(3), m_verify_seconds(10), m_request_time(0),
        m_last_post_time(0), m_notify(false), m_main_window(0) {}

   //+---------------------------------------------------------------+
   //| required = the profile asks for automatic Algo Trading control.|
   //|                                                                |
   //| When it is required, missing DLL permission is a HARD failure. |
   //| Silently degrading to "we will just not do it" is exactly how  |
   //| a trader ends up believing an account is protected while every |
   //| toggle request is discarded (a naive integration imports the   |
   //| WinAPI call without ever checking either permission).          |
   //+---------------------------------------------------------------+
   bool Init(const bool required, const int max_attempts, const int verify_seconds,
             const bool notify_on_escalation)
   {
      m_required       = required;
      m_max_attempts   = (max_attempts > 0) ? max_attempts : 1;
      m_verify_seconds = (verify_seconds > 0) ? verify_seconds : 1;
      m_notify         = notify_on_escalation;
      m_latch          = ALGO_LATCH_IDLE;
      m_disable_held   = false;
      m_attempts       = 0;
      m_ready          = false;

      if(!required)
      {
         m_ready = true;   // present but inert: no DLL is needed to do nothing
         return true;
      }

#ifdef PROP_MARKET_BUILD
      //--- asked for an actuator this build cannot have. Refusing to start
      //--- would leave the account with NO guard over an optional extra, which
      //--- is the worse failure for a protection tool -- so degrade the
      //--- actuator, keep every rule running, and say exactly what was lost.
      m_required = false;
      m_ready    = true;
      Print("CTerminalAlgoSwitch: 'disable Algo Trading on breach' was requested but "
            "is unavailable in this build -- the MQL5 Market forbids DLL calls and "
            "MQL5 has no native way to flip that button. Every rule stays active: "
            "entries are still blocked and positions still flattened. Turn the option "
            "off to silence this notice.");
      return true;
#endif

      if(!(bool)TerminalInfoInteger(TERMINAL_DLLS_ALLOWED))
      {
         Print("CTerminalAlgoSwitch::Init failed: 'Allow DLL imports' is OFF in the "
               "terminal options. There is no native MQL5 way to switch global Algo "
               "Trading, so either enable DLL imports or set the profile's "
               "disable_algo_on_breach to false and handle the lockdown manually.");
         return false;
      }

      if(!(bool)MQLInfoInteger(MQL_DLLS_ALLOWED))
      {
         Print("CTerminalAlgoSwitch::Init failed: this program was loaded without "
               "'Allow DLL imports' ticked in its own properties. Reload the EA with "
               "the option enabled, or disable automatic Algo Trading control.");
         return false;
      }

      m_main_window = ResolveMainWindow();
      if(m_main_window == 0)
         Print("CTerminalAlgoSwitch: main window handle not resolved yet, will retry "
               "on the first request.");

      m_ready = true;
      return true;
   }

   bool            IsReady()        const { return m_ready; }
   bool            IsRequired()     const { return m_required; }
   ENUM_ALGO_LATCH Latch()          const { return m_latch; }
   int             Attempts()       const { return m_attempts; }
   bool            DesiredState()   const { return m_desired_state; }
   bool            IsDisableHeld()  const { return m_disable_held; }
   bool            IsUnrecoverable() const { return m_latch == ALGO_LATCH_UNRECOVERABLE; }

   //+---------------------------------------------------------------+
   //| C7. The ONLY thing a caller may trust. Pending means "we asked |
   //| and the terminal has not confirmed yet" -- not "done".         |
   //+---------------------------------------------------------------+
   bool IsSettled() const
   {
      return (m_latch == ALGO_LATCH_IDLE || m_latch == ALGO_LATCH_SETTLED);
   }

   //+---------------------------------------------------------------+
   //| Requests Algo Trading OFF. Idempotent: repeating it while a    |
   //| disable latch is already pending does NOT post a second        |
   //| message -- the re-post schedule belongs to Update().           |
   //+---------------------------------------------------------------+
   bool RequestDisable()
   {
      if(!m_ready || !m_required)
         return false;

      if(m_disable_held && m_latch != ALGO_LATCH_IDLE)
         return true;                 // already asked for; do not spam the terminal

      m_desired_state  = false;
      m_disable_held   = true;
      m_latch          = ALGO_LATCH_PENDING;
      m_attempts       = 0;
      m_request_time   = TimeCurrent();
      m_last_post_time = 0;

      if(!PostToggle())
      {
         //--- keep the latch pending: Update() will retry under the budget
         return false;
      }

      //--- deliberately NOT verifying here. The terminal processes the
      //--- message on its own thread; reading TERMINAL_TRADE_ALLOWED on the
      //--- next line would report the pre-toggle value and be meaningless.
      return true;
   }

   //+---------------------------------------------------------------+
   //| C3. Requests Algo Trading ON -- and refuses while a disable is |
   //| held. The request is REJECTED, not queued: a queued enable     |
   //| would eventually fire and re-arm a breached account.           |
   //+---------------------------------------------------------------+
   bool RequestEnable()
   {
      if(!m_ready || !m_required)
         return false;

      if(m_disable_held)
      {
         Print("CTerminalAlgoSwitch: enable request REFUSED -- a protective disable is "
               "held. Only ClearLatch() lifts it.");
         return false;
      }

      m_desired_state  = true;
      m_latch          = ALGO_LATCH_PENDING;
      m_attempts       = 0;
      m_request_time   = TimeCurrent();
      m_last_post_time = 0;

      return PostToggle();
   }

   //+---------------------------------------------------------------+
   //| C7. Verification, on a LATER pass than the request.            |
   //|                                                                |
   //| Call once per Evaluate() pass. Sequence per pending latch:     |
   //|   - read the terminal's actual state;                          |
   //|   - if it matches, the latch settles;                          |
   //|   - otherwise, once verify_seconds have elapsed since the last |
   //|     post, either re-post (attempts left) or escalate loudly.   |
   //| No Sleep(), no busy wait: the passage of time between passes   |
   //| is the wait.                                                   |
   //+---------------------------------------------------------------+
   void Update(const datetime now)
   {
      if(!m_ready || m_latch != ALGO_LATCH_PENDING)
         return;

      bool actual = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);

      if(actual == m_desired_state)
      {
         m_latch = ALGO_LATCH_SETTLED;
         PrintFormat("CTerminalAlgoSwitch: verified, Algo Trading is now %s after %d "
                     "attempt(s) and %d second(s).",
                     (m_desired_state ? "ON" : "OFF"), m_attempts,
                     (int)((long)now - (long)m_request_time));
         return;
      }

      if(m_last_post_time != 0 && ((long)now - (long)m_last_post_time) < m_verify_seconds)
         return;                       // still inside this attempt's grace period

      if(m_attempts >= m_max_attempts)
      {
         Escalate();
         return;
      }

      PostToggle();
   }

   //+---------------------------------------------------------------+
   //| Lifts the disable hold. Two legitimate callers:                |
   //| CPropRulebook::ResetChallenge(), and the restore-rollback  |
   //| branch inside Init().                                          |
   //+---------------------------------------------------------------+
   void ClearLatch()
   {
      m_latch        = ALGO_LATCH_IDLE;
      m_disable_held = false;
      m_attempts     = 0;
      m_request_time = 0;
      m_last_post_time = 0;
   }

   string StateText() const
   {
      string latch_text;
      switch(m_latch)
      {
         case ALGO_LATCH_PENDING:       latch_text = "PENDING";       break;
         case ALGO_LATCH_SETTLED:       latch_text = "SETTLED";       break;
         case ALGO_LATCH_UNRECOVERABLE: latch_text = "UNRECOVERABLE"; break;
         default:                       latch_text = "IDLE";          break;
      }
      return StringFormat("algo=%s want=%s attempts=%d%s",
                          latch_text,
                          (m_desired_state ? "ON" : "OFF"),
                          m_attempts,
                          (m_disable_held ? " HOLD" : ""));
   }

   //--- persistence (C9): a terminal that reboots into a breached account
   //--- must come back holding the disable, not with a clean switch
   string Serialize() const
   {
      return StringFormat("%d,%d,%d,%d",
                          (int)m_latch, (m_desired_state ? 1 : 0),
                          (m_disable_held ? 1 : 0), m_attempts);
   }

   bool Deserialize(const string state)
   {
      string f[];
      if(StringSplit(state, (ushort)',', f) != 4)
         return false;

      int latch = (int)StringToInteger(f[0]);
      if(latch < 0 || latch > 3)
         return false;

      m_latch         = (ENUM_ALGO_LATCH)latch;
      m_desired_state = ((int)StringToInteger(f[1]) == 1);
      m_disable_held  = ((int)StringToInteger(f[2]) == 1);
      m_attempts      = (int)StringToInteger(f[3]);

      //--- a latch restored as PENDING is re-verified from scratch on the
      //--- next passes rather than assumed to have completed while the
      //--- terminal was down
      if(m_latch == ALGO_LATCH_PENDING)
      {
         m_attempts       = 0;
         m_request_time   = TimeCurrent();
         m_last_post_time = 0;
      }
      return true;
   }
};
//+------------------------------------------------------------------+
