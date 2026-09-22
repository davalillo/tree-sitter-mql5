//+------------------------------------------------------------------+
//|                                              PropFirmDefense.mq5 |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| The CodeBase release. Same guard published as the Market product |
//| (194936) -- source form, for readers who want the classes rather  |
//| than the compiled .ex5. This file is NOT part of the article      |
//| submission: it lives in codebase/ on purpose. The 24 headers it   |
//| includes are expected in MQL5\Include\PropRulebook\, per the      |
//| Location chosen for each file when this was uploaded.             |
//+------------------------------------------------------------------+
#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"
//--- Sem #property icon aqui de proposito: o campo de anexo do CodeBase
//--- nao aceita .ico (accept="...gif,.png,.jpg..." -- .ico esta fora da
//--- lista). Um icone declarado sem o arquivo presente quebraria o
//--- compile de quem baixar so o .mq5 + os headers. O icone e coisa do
//--- build do Market (market/PropFirmDefense.mq5), onde o .ex5 e um
//--- unico arquivo compilado e o .ico entra junto no binario.
#property description "Watches the prop-firm rulebook your EA knows nothing about: drawdown (static and trailing), daily loss, profit target,"
#property description "payout consistency, minimum trading days, news blackout and the pre-weekend cutoff."
#property description "Eight rules, one frozen account snapshot per pass, at most one directive out of it. On-chart panel with live statistics."
#property description "Runs next to any EA, manual trading or copied signal, and takes no position of its own."

//--- Mesma chave usada no build do Market: sem ela o pacote importa
//--- user32.dll (CTerminalAlgoSwitch) para o botao global de Algo
//--- Trading. Mantida aqui tambem -- o validador automatico do
//--- CodeBase roda o mesmo checklist de robo referenciado no guia
//--- oficial de publicacao ("The checks a trading robot must pass
//--- before publication in the Market"), e o degradar-em-vez-de-
//--- recusar segue sendo o comportamento certo.
#define PROP_MARKET_BUILD

#include <PropRulebook\CPropRulebook.mqh>
#include <PropRulebook\CPropDashboardPanel.mqh>

//--- Every threshold, the preset picker and account/magic/timezone/DLL
//--- inputs already come from PropFirmProfile.mqh (12 input groups,
//--- InpPF_*) -- it is #included via CPropRulebook.mqh above, and MQL5
//--- surfaces an included file's `input` declarations in this program's
//--- own Inputs dialog. Redeclaring InpDemo_AccountSize/Magic/etc. here
//--- would just be a second, disconnected copy of the same setting --
//--- removed on purpose (2026-09-08 review). Only what genuinely does
//--- not exist in the profile stays demo-local.
input group "=== PropFirmDefense ==="
input string InpDemo_Symbol              = "";        // Symbol for the simulated entry ("" = chart symbol)
input double InpDemo_Volume              = 0.10;      // Lots the simulated entry would send
input int    InpDemo_SignalIntervalSec   = 30;        // How often the demo pretends its strategy wants to buy
input int    InpDemo_PanelX              = 20;        // Panel X offset (pixels, left corner)
input int    InpDemo_PanelY              = 20;        // Panel Y offset (pixels, top corner)

CPropRulebook       g_guard;
CPropDashboardPanel g_panel;
string              g_symbol         = "";

ENUM_PROP_DIRECTIVE g_last_directive = PROP_DIRECTIVE_NONE;
double              g_last_floor     = 0.0;
bool                g_last_settled   = true;
bool                g_first_pass     = true;

//+------------------------------------------------------------------+
//| One guard pass, the same change-only journal as the article's     |
//| demo, plus an unconditional panel refresh -- the panel always     |
//| shows the latest pass, not just the passes that changed a line.   |
//+------------------------------------------------------------------+
void RunGuardPass()
{
   ENUM_PROP_DIRECTIVE directive = g_guard.Evaluate();

   PropRuleVerdict trailing = g_guard.GetVerdict(PROP_RULE_TRAILING_DD);
   double floor_level = trailing.evaluated ? trailing.threshold : 0.0;
   bool   settled      = g_guard.IsProtectionSettled();
   bool   floor_moved   = (MathAbs(floor_level - g_last_floor) > 0.01);

   g_panel.Update(g_guard);

   if(!g_first_pass && !floor_moved &&
      directive == g_last_directive && settled == g_last_settled)
      return;

   if(!g_first_pass && floor_moved)
      PrintFormat("PropFirm Defense: trailing floor %.2f -> %.2f | %s",
                  g_last_floor, floor_level, trailing.message);

   if(!g_first_pass && directive != g_last_directive)
      PrintFormat("PropFirm Defense: directive %s -> %s",
                  PropDirectiveName(g_last_directive), PropDirectiveName(directive));

   if(!g_first_pass && settled != g_last_settled)
      PrintFormat("PropFirm Defense: protection settled %s -> %s",
                  (g_last_settled ? "yes" : "no"), (settled ? "yes" : "no"));

   Print("PropFirm Defense: ", g_guard.StatusReport());

   g_first_pass     = false;
   g_last_directive = directive;
   g_last_floor     = floor_level;
   g_last_settled   = settled;
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_symbol = (InpDemo_Symbol == "") ? _Symbol : InpDemo_Symbol;

   //--- InpPF_Preset == CUSTOM ("fill every field yourself", the enum's own
   //--- default) means the buyer's InpPF_* fields ARE the profile, verbatim.
   //--- Any other value means they picked a researched firm preset instead,
   //--- and LoadPreset() supplies every threshold -- the two are alternate
   //--- modes, not layered, so a preset pick is never silently overwritten
   //--- by the zeroed InpPF_* defaults sitting unused next to it.
   PropFirmProfile profile;
   if(InpPF_Preset == PROP_PRESET_CUSTOM)
   {
      BuildProfileFromInputs(profile);
   }
   else if(!CPropRulebook::LoadPreset(profile, InpPF_Preset, InpPF_AccountSize))
   {
      Print("PropFirm Defense: LoadPreset() refused the account size, error ", GetLastError());
      return INIT_FAILED;
   }

   if(!g_guard.Init(profile))
   {
      Print("PropFirm Defense: guard did not start -- ", g_guard.InitError());
      return INIT_FAILED;
   }

   PrintFormat("PropFirm Defense: guarding '%s' with %.2f lots of simulated size, "
               "magic %I64u, preset '%s'",
               g_symbol, InpDemo_Volume, profile.magic, profile.firm_name);

   //--- primeira coisa que o comprador ve: com os defaults (preset Custom e
   //--- limites zerados) NENHUMA regra e registrada, de proposito. Silenciar
   //--- isso deixaria alguem achando que esta protegido sem estar.
   if(g_guard.RuleCount() == 0)
      Print("PropFirm Defense: NO RULE IS ACTIVE. The defaults guard nothing on "
            "purpose -- open Inputs, pick your firm in 'Firm preset', or set the "
            "thresholds by hand under the 'PropFirm Guard' groups. Nothing is being "
            "watched until you do.");

   g_panel.Create(InpDemo_PanelX, InpDemo_PanelY);
   RunGuardPass();

   EventSetTimer(InpDemo_SignalIntervalSec);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   g_panel.Destroy();
   g_guard.Release();
}

//+------------------------------------------------------------------+
void OnTick()
{
   RunGuardPass();
}

//+------------------------------------------------------------------+
void OnTimer()
{
   RunGuardPass();

   if(!g_guard.CanOpen(g_symbol, InpDemo_Volume))
   {
      PrintFormat("PropFirm Defense: entry on %s (%.2f lots) BLOCKED by the guard",
                  g_symbol, InpDemo_Volume);
      return;
   }

   //--- No live OrderSend() here on purpose -- same as the article's demo,
   //--- this exists to prove the guard's behaviour on the journal and on
   //--- the panel, never to trade on its own.
   PrintFormat("PropFirm Defense: [simulated OrderSend()] %s %.2f lots cleared by "
               "CanOpen(), %.2f of trailing-floor headroom left",
               g_symbol, InpDemo_Volume, g_guard.GetHeadroom(PROP_RULE_TRAILING_DD));

   string payout_reason = "";
   if(!g_guard.IsPayoutEligible(payout_reason))
      Print("PropFirm Defense: payout not yet eligible -- ", payout_reason);
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   g_guard.OnTradeTransaction(trans);
}
