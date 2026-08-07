//+------------------------------------------------------------------+
//| AW_Inst_Engine.mqh                                               |
//| Institutional orchestrator — wraps Pro, does NOT replace Pro     |
//+------------------------------------------------------------------+
#ifndef AW_INST_ENGINE_MQH
#define AW_INST_ENGINE_MQH

#include "../Pro/AW_Pro_Engine.mqh"
#include "AW_Inst_Regime.mqh"
#include "AW_Inst_AdaptiveFilter.mqh"
#include "AW_Inst_TradeScore.mqh"
#include "AW_Inst_Drawdown.mqh"
#include "AW_Inst_Stats.mqh"
#include "AW_Inst_SetupDB.mqh"
#include "AW_Inst_AutoDisable.mqh"
#include "AW_Inst_Safety.mqh"
#include "AW_Inst_Dashboard.mqh"

struct AWInstDecision
{
   bool         take;
   AWProSignal  signal;
   AWScoreResult score;
   double       lots;
   string       denyReason;
};

class CAWInstEngine
{
private:
   CAWProEngine*          m_pro; // external Pro instance — not owned/overturned
   CAWInstRegime          m_regime;
   CAWInstAdaptiveFilter  m_filter;
   CAWInstTradeScore      m_scorer;
   CAWInstDrawdown        m_dd;
   CAWInstStats           m_stats;
   CAWInstSetupDB         m_setupDb;
   CAWInstAutoDisable     m_autoDis;
   CAWInstDashboard       m_dash;
   AWScoreResult          m_lastScore;
   string                 m_sessionName;
   bool                   m_sessionOk;
   bool                   m_lowLiq;
   double                 m_lastLossLots;
   ulong                  m_seenDealTickets[];

public:
   CAWInstEngine(): m_pro(NULL), m_lastLossLots(0.0)
   {
      ZeroMemory(m_lastScore);
      m_sessionName = "";
      m_sessionOk = false;
      m_lowLiq = false;
   }

   bool Init(CAWProEngine &pro,
             const AWRegimeConfig &regCfg,
             const AWAdaptiveConfig &adpCfg,
             const AWScoreConfig &scoreCfg,
             const AWDrawdownConfig &ddCfg,
             const AWAutoDisableConfig &autoCfg,
             const double equityNow)
   {
      m_pro = GetPointer(pro);
      if(!m_regime.Init(_Symbol, regCfg)) return false;
      m_filter.Init(adpCfg);
      m_scorer.Init(scoreCfg);
      m_dd.Init(ddCfg, equityNow);
      m_setupDb.Init();
      m_autoDis.Init(autoCfg);
      m_stats.Reset();
      return true;
   }

   CAWInstStats* Stats() { return GetPointer(m_stats); }
   CAWInstSetupDB* SetupDB() { return GetPointer(m_setupDb); }
   AWDrawdownState Dd() const { return m_dd.State(); }
   AWRegimeState Regime() const { return m_regime.State(); }
   AWScoreResult LastScore() const { return m_lastScore; }

   void SetSessionContext(const string name, const bool ok, const bool lowLiquidity)
   {
      m_sessionName = name;
      m_sessionOk = ok;
      m_lowLiq = lowLiquidity;
   }

   void OnTickUpdate(const datetime sessStart, const datetime now)
   {
      if(m_pro == NULL) return;
      m_pro.Update();
      m_regime.Update(m_pro.EntryBias(), m_pro.HtfBias(), sessStart, now);
      m_dd.Update(AccountInfoDouble(ACCOUNT_EQUITY));
      m_autoDis.Evaluate(m_setupDb);
   }

   // Evaluate Pro signals through Institutional gates
   int Decide(AWInstDecision &out[], const int maxOut)
   {
      ArrayResize(out, 0);
      if(m_pro == NULL) return 0;

      const AWDrawdownState dd = m_dd.State();
      if(dd.status == AW_STATUS_STOPPED)
         return 0;

      AWProSignal raw[];
      const int n = m_pro.CollectSignals(raw, 16);
      const AWRegimeState reg = m_regime.State();

      for(int i = 0; i < n; ++i)
      {
         AWInstDecision d;
         ZeroMemory(d);
         d.signal = raw[i];

         if(!m_sessionOk)
         {
            d.denyReason = "session blocked";
            continue;
         }
         if(m_setupDb.IsPaused(d.signal.setupId))
         {
            d.denyReason = "setup paused: " + m_setupDb.Get(d.signal.setupId).pauseReason;
            continue;
         }
         if(!m_filter.AllowSetup(reg.regime, d.signal.setupId))
         {
            d.denyReason = "adaptive filter blocked setup in " + AW_RegimeName(reg.regime);
            continue;
         }

         const double weight = m_filter.SetupWeight(reg.regime, d.signal.setupId);
         const bool htfAligned =
            (d.signal.direction == AW_DIR_BUY && m_pro.HtfBias() == AW_DIR_BUY) ||
            (d.signal.direction == AW_DIR_SELL && m_pro.HtfBias() == AW_DIR_SELL);

         d.score = m_scorer.Evaluate(d.signal, reg, weight, m_sessionOk, m_lowLiq, htfAligned, 1);
         m_lastScore = d.score;

         if(dd.status == AW_STATUS_A_PLUS_ONLY && d.score.grade != AW_GRADE_A_PLUS)
         {
            d.denyReason = "DD Level2 requires A+";
            continue;
         }
         if(!d.score.pass)
         {
            d.denyReason = d.score.reason;
            continue;
         }

         const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         // risk percent passed from EA via global — set lots in EA after Decide
         d.take = true;
         d.denyReason = "";
         const int k = ArraySize(out);
         if(k < maxOut)
         {
            ArrayResize(out, k + 1);
            out[k] = d;
         }
      }
      return ArraySize(out);
   }

   void RenderDashboard(const string extra)
   {
      const AWSetupDbRow cur = m_setupDb.Get(AW_SETUP_FIB_SWEEP_ENGULFING);
      const string perf = StringFormat("%s PF=%.2f n=%d", m_stats.SummaryLine(),
                                       cur.perf.ProfitFactor(), cur.perf.trades);
      m_dash.Render(m_regime.State(), m_dd.State(), m_lastScore, perf, extra);
   }

   // Call from OnTradeTransaction after deal close — no floating PnL
   void OnClosedDeal(const AWTradeRecord &rec)
   {
      // duplicate deal guard
      for(int i = 0; i < ArraySize(m_seenDealTickets); ++i)
         if(m_seenDealTickets[i] == rec.ticket) return;
      const int n = ArraySize(m_seenDealTickets);
      ArrayResize(m_seenDealTickets, n + 1);
      m_seenDealTickets[n] = rec.ticket;

      m_stats.OnTradeClosed(rec);
      m_setupDb.OnTradeClosed(rec);
      if(rec.pnl < 0.0)
         m_lastLossLots = 0.0; // lot size tracking for safety done in EA; reset marker
      m_autoDis.Evaluate(m_setupDb);
   }

   double LastLossLots() const { return m_lastLossLots; }
   void SetLastLossLots(const double v) { m_lastLossLots = v; }
};

#endif
