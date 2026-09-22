//+------------------------------------------------------------------+
//|                                        CPropDashboardPanel.mqh   |
//|                                                     Bruno Myrrha |
//+------------------------------------------------------------------+
//| Purpose:      On-chart panel for CPropRulebook, built for the     |
//|               Market listing only. NOT part of the article       |
//|               package submitted to mql5.com (design.json records |
//|               the original "no UI class" decision -- that stays  |
//|               true for the article; this file exists next to it, |
//|               not inside it).                                     |
//|               Reads the guard through its existing public API     |
//|               (GetVerdict/GetHeadroom/LastDirective/              |
//|               IsPayoutEligible/IsProtectionSettled) only -- it     |
//|               adds no new guard state and cannot influence a      |
//|               directive.                                          |
//| Layout v3:    Real structure, not colored text in a box -- a blue |
//|               title band, a colored status BADGE (filled rect,    |
//|               not just colored text), divider lines, four labeled |
//|               rule groups (Drawdown / Loss & Target / Payout      |
//|               Rules / Conduct) each with a small severity dot per |
//|               row, and a divider before the footer. 2026-09-08    |
//|               rebuild after v1/v2 read as "text in a box" with no |
//|               visual hierarchy.                                   |
//| Dependencies: src/CPropRulebook.mqh (for the enums/struct types;  |
//|               the panel takes a reference, never owns the guard)  |
//+------------------------------------------------------------------+
#property copyright "Bruno Nunes Myrrha Ribeiro"
#property link      "https://www.mql5.com/en/users/bruno_myrrha"
#property version   "1.01"

//--- este arquivo usa os enums e structs do pacote (ENUM_PROP_SEVERITY,
//--- ENUM_PROP_DIRECTIVE, PropRuleVerdict...). Sem esta linha ele so
//--- compila se quem usa incluir CPropRulebook.mqh antes -- e quem
//--- baixa o pacote e abre o arquivo direto recebe 69 erros.
#include "CPropRulebook.mqh"

#define STAT_ROWS 6

class CPropDashboardPanel
{
private:
   string   m_prefix;
   long     m_chart_id;
   int      m_x;
   int      m_y;
   int      m_width;
   int      m_line_h;
   bool     m_created;

   string Name(const string suffix) const { return m_prefix + suffix; }

   void CreateRect(const string suffix, int x, int y, int w, int h,
                    color bg, color border)
   {
      string name = Name(suffix);
      if(ObjectFind(m_chart_id, name) < 0)
         ObjectCreate(m_chart_id, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(m_chart_id, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart_id, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chart_id, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chart_id, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(m_chart_id, name, OBJPROP_YSIZE, h);
      ObjectSetInteger(m_chart_id, name, OBJPROP_BGCOLOR, bg);
      ObjectSetInteger(m_chart_id, name, OBJPROP_COLOR, border);
      ObjectSetInteger(m_chart_id, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(m_chart_id, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(m_chart_id, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(m_chart_id, name, OBJPROP_BACK, false);
      ObjectSetInteger(m_chart_id, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chart_id, name, OBJPROP_HIDDEN, true);
   }

   void SetRectColor(const string suffix, color clr)
   {
      string name = Name(suffix);
      ObjectSetInteger(m_chart_id, name, OBJPROP_BGCOLOR, clr);
      ObjectSetInteger(m_chart_id, name, OBJPROP_COLOR, clr);
   }

   void CreateLabel(const string suffix, int x, int y, color clr, int size)
   {
      string name = Name(suffix);
      if(ObjectFind(m_chart_id, name) < 0)
         ObjectCreate(m_chart_id, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(m_chart_id, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart_id, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chart_id, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chart_id, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chart_id, name, OBJPROP_FONTSIZE, size);
      ObjectSetString(m_chart_id, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(m_chart_id, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chart_id, name, OBJPROP_HIDDEN, true);
   }

   void SetLabel(const string suffix, const string text, color clr)
   {
      string name = Name(suffix);
      ObjectSetString(m_chart_id, name, OBJPROP_TEXT, text);
      ObjectSetInteger(m_chart_id, name, OBJPROP_COLOR, clr);
   }

   //--- "Classic" palette sampled from Bruno's own EA Portfolios web
   //--- dashboard (colors only -- no brand name/logo anywhere in this file;
   //--- mql5/CLAUDE.md bans mentioning EA Portfolios in anything that
   //--- reaches mql5.com, since it competes with their own Market):
   //--- header blue #547CB3, accent gold #E5BC52, positive green #64BE70,
   //--- negative red #E23C4A, white cards. Values below are the same hues
   //--- deepened for legibility as small text/fills on white.
   color SeverityColor(const ENUM_PROP_SEVERITY sev) const
   {
      switch(sev)
      {
         case PROP_SEV_BREACH:   return C'200,40,55';    // red    (from #E23C4A)
         case PROP_SEV_ADVISORY: return C'150,110,10';   // gold   (from #E5BC52)
         case PROP_SEV_WARNING:  return C'150,110,10';   // gold
         case PROP_SEV_INFO:     return C'60,90,150';    // blue   (from #547CB3)
         default:                return C'40,150,80';    // green  (from #64BE70, OK)
      }
   }

   color DirectiveColor(const ENUM_PROP_DIRECTIVE dir) const
   {
      switch(dir)
      {
         case PROP_DIRECTIVE_LOCKDOWN:          return C'200,40,55';   // red
         case PROP_DIRECTIVE_FLATTEN:           return C'184,90,20';   // orange (between gold and red)
         case PROP_DIRECTIVE_BLOCK_NEW_ENTRIES: return C'150,110,10';  // gold
         case PROP_DIRECTIVE_ADVISORY:          return C'60,90,150';   // blue
         default:                               return C'40,150,80';   // green
      }
   }

   string PadRight(const string s, const int width) const
   {
      string out = s;
      while(StringLen(out) < width)
         out += " ";
      return out;
   }

   //--- group layout: which rule sits in which of the 4 labeled sections
   static string GroupTitle(const int g)
   {
      switch(g)
      {
         case 0: return "DRAWDOWN";
         case 1: return "LOSS & TARGET";
         case 2: return "PAYOUT RULES";
         default: return "CONDUCT";
      }
   }

public:
   CPropDashboardPanel(const string prefix = "PFD_Panel_")
      : m_prefix(prefix), m_chart_id(0), m_x(20), m_y(20),
        m_width(340), m_line_h(16), m_created(false) {}

   ~CPropDashboardPanel() { Destroy(); }

   //+------------------------------------------------------------------+
   //| Creates every object once, top to bottom, tracking a running y    |
   //| cursor so the card height is whatever the content actually needs |
   //| -- then backfills "bg"'s final height. Update() below only ever  |
   //| changes text/fill color on the objects created here.             |
   //+------------------------------------------------------------------+
   void Create(const int x = 20, const int y = 20, const long chart_id = 0)
   {
      m_x        = x;
      m_y        = y;
      m_chart_id = (chart_id == 0) ? ChartID() : chart_id;

      color border = C'150,168,196';
      color blue   = C'84,118,179';
      color muted  = C'140,140,140';
      color text   = C'60,60,60';

      //--- card body: created first (temp height), resized at the end once
      //--- the real content height is known -- keeps it behind everything
      //--- else, which is all created after it.
      CreateRect("bg", m_x, m_y, m_width, 10, clrWhite, border);

      int band_h = m_line_h + 10;
      CreateRect("head", m_x, m_y, m_width, band_h, blue, blue);
      CreateLabel("title", m_x + 10, m_y + 7, clrWhite, 10);
      SetLabel("title", "PROPFIRM DEFENSE", clrWhite);

      int cy = m_y + band_h + 8;

      //--- status: a filled BADGE, not colored text -- this is the one
      //--- number a user glances at first, so it gets real chrome.
      CreateRect("statusbadge", m_x + 10, cy, m_width - 20, 20, C'40,150,80', C'40,150,80');
      CreateLabel("status", m_x + 16, cy + 5, clrWhite, 9);
      cy += 20 + 8;

      CreateRect("div1", m_x + 10, cy, m_width - 20, 1, border, border);
      cy += 10;

      int rule_idx = 0;
      for(int g = 0; g < 4; g++)
      {
         CreateLabel("grp" + IntegerToString(g), m_x + 10, cy, muted, 7);
         SetLabel("grp" + IntegerToString(g), GroupTitle(g), muted);
         cy += 12;

         for(int r = 0; r < 2; r++)
         {
            CreateRect("dot" + IntegerToString(rule_idx), m_x + 10, cy + 4, 7, 7, muted, muted);
            CreateLabel("rule" + IntegerToString(rule_idx), m_x + 23, cy + 2, text, 8);
            cy += m_line_h;
            rule_idx++;
         }
         cy += 4;
      }

      CreateRect("div2", m_x + 10, cy, m_width - 20, 1, border, border);
      cy += 10;

      //--- bloco de estatisticas: tudo isto ja vem pronto no snapshot de cada
      //--- passada (GetSnapshot), o painel so nao mostrava. Nenhuma conta nova
      //--- e feita aqui -- e leitura, igual ao resto do painel.
      CreateLabel("grpstats", m_x + 10, cy, muted, 7);
      SetLabel("grpstats", "STATISTICS", muted);
      cy += 12;

      for(int s = 0; s < STAT_ROWS; s++)
      {
         CreateLabel("stat" + IntegerToString(s), m_x + 23, cy + 2, text, 8);
         cy += m_line_h;
      }
      cy += 4;

      CreateRect("div3", m_x + 10, cy, m_width - 20, 1, border, border);
      cy += 10;

      CreateRect("dot_payout", m_x + 10, cy + 4, 7, 7, muted, muted);
      CreateLabel("footer1", m_x + 23, cy + 2, text, 8);
      cy += m_line_h;

      CreateRect("dot_settled", m_x + 10, cy + 4, 7, 7, muted, muted);
      CreateLabel("footer2", m_x + 23, cy + 2, text, 8);
      cy += m_line_h;

      cy += 8;

      ObjectSetInteger(m_chart_id, Name("bg"), OBJPROP_YSIZE, cy - m_y);

      m_created = true;
      ChartRedraw(m_chart_id);
   }

   //+------------------------------------------------------------------+
   //| Pure read of the guard's already-computed state. Never calls      |
   //| Evaluate() itself -- the caller runs the guard pass, then calls   |
   //| Update() to reflect it, same as the journal's StatusReport().     |
   //+------------------------------------------------------------------+
   void Update(CPropRulebook &guard)
   {
      if(!m_created)
         Create(m_x, m_y);

      //--- C1 na tela: um guard sem NENHUMA regra registrada nao pode aparecer
      //--- como "STATUS: NONE" em verde -- isso le como "esta tudo protegido"
      //--- quando nao ha uma unica regra ativa. O default do pacote e
      //--- deliberadamente nao guardar nada ate ser configurado (PROP_PRESET_
      //--- CUSTOM com limites zerados), entao esse estado e o primeiro que o
      //--- comprador ve. Ele tem que gritar, nao tranquilizar.
      if(guard.RuleCount() == 0)
      {
         SetRectColor("statusbadge", C'200,40,55');
         SetLabel("status", "NOT CONFIGURED - NO RULE IS ACTIVE", clrWhite);
      }
      else
      {
         ENUM_PROP_DIRECTIVE dir   = guard.LastDirective();
         color                dclr = DirectiveColor(dir);
         SetRectColor("statusbadge", dclr);
         SetLabel("status", StringFormat("STATUS: %s", PropDirectiveName(dir)), clrWhite);
      }

      ENUM_PROP_RULE rules[8] =
      {
         PROP_RULE_STATIC_DD, PROP_RULE_TRAILING_DD, PROP_RULE_DAILY_LOSS,
         PROP_RULE_PROFIT_TARGET, PROP_RULE_CONSISTENCY, PROP_RULE_MIN_TRADING_DAYS,
         PROP_RULE_NEWS_WINDOW, PROP_RULE_WEEKEND_FLAT
      };

      for(int i = 0; i < 8; i++)
      {
         PropRuleVerdict v = guard.GetVerdict(rules[i]);
         string name = PadRight(PropRuleName(rules[i]), 15);
         string line;
         color  clr;
         color  dotclr;

         if(!v.evaluated)
         {
            line   = name + "off";
            clr    = C'170,170,170';
            dotclr = C'210,210,210';
         }
         else if(v.abstained)
         {
            line   = name + "no data";
            clr    = C'170,170,170';
            dotclr = C'210,210,210';
         }
         else
         {
            //--- measured vs. the configured threshold -- the actual stats,
            //--- not just the distance left, per Bruno's 2026-09-08 review
            line = StringFormat("%s%-8s %.2f/%.2f %s",
                                 name, PropSeverityName(v.severity),
                                 v.measured, v.threshold, v.unit);
            clr    = SeverityColor(v.severity);
            dotclr = clr;
         }
         SetLabel("rule" + IntegerToString(i), line, clr);
         SetRectColor("dot" + IntegerToString(i), dotclr);
      }

      //--- estatisticas: leitura direta do snapshot da passada que acabou de
      //--- rodar. O guard ja calculou tudo isto; o painel so nao mostrava.
      PropAccountSnapshot snap;
      guard.GetSnapshot(snap);

      color stat_clr = C'60,60,60';
      SetLabel("stat0", StringFormat("%-15s%.2f / %.2f", "equity/balance", snap.equity, snap.balance), stat_clr);
      SetLabel("stat1", StringFormat("%-15s%.2f", "floating P/L", snap.floating_pl),
               snap.floating_pl >= 0.0 ? C'40,150,80' : C'200,40,55');
      SetLabel("stat2", StringFormat("%-15s%.2f", "realized today", snap.realized_today),
               snap.realized_today >= 0.0 ? C'40,150,80' : C'200,40,55');
      SetLabel("stat3", StringFormat("%-15s%.2f", "peak equity", snap.peak_equity), stat_clr);
      SetLabel("stat4", StringFormat("%-15s%.2f / %.2f", "MFE/MAE eq", snap.mfe_equity, snap.mae_equity), stat_clr);
      SetLabel("stat5", StringFormat("%-15s%.0f%% best day, %d days", "payout stats",
                                      snap.best_day_share * 100.0, snap.qualifying_days), stat_clr);

      string payout_reason = "";
      bool   payout_ok = guard.IsPayoutEligible(payout_reason);
      color  payout_clr = payout_ok ? C'40,150,80' : C'150,110,10';
      SetLabel("footer1", StringFormat("payout: %s", payout_ok ? "eligible" : "blocked"), payout_clr);
      SetRectColor("dot_payout", payout_clr);

      bool  settled     = guard.IsProtectionSettled();
      color settled_clr = settled ? C'40,150,80' : C'150,110,10';
      SetLabel("footer2", StringFormat("protection settled: %s", settled ? "yes" : "no"), settled_clr);
      SetRectColor("dot_settled", settled_clr);

      ChartRedraw(m_chart_id);
   }

   void Destroy()
   {
      if(!m_created)
         return;
      ObjectsDeleteAll(m_chart_id, m_prefix);
      m_created = false;
   }
};
