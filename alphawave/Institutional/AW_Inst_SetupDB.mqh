//+------------------------------------------------------------------+
//| AW_Inst_SetupDB.mqh                                              |
//| Setup Performance Database — per-setup independent statistics    |
//| Collect & report ONLY — never auto-rewrites strategy logic       |
//+------------------------------------------------------------------+
#ifndef AW_INST_SETUP_DB_MQH
#define AW_INST_SETUP_DB_MQH
#include "AW_Inst_Stats.mqh"

struct AWSetupDbRow
{
   ENUM_AW_SETUP_ID id;
   string           name;
   AWPerfSlice      perf;
   bool             paused;
   string           pauseReason;
   datetime         pausedAt;
};

class CAWInstSetupDB
{
private:
   AWSetupDbRow m_rows[];

public:
   void Init()
   {
      ArrayResize(m_rows, AW_SETUP_COUNT);
      for(int i = 0; i < AW_SETUP_COUNT; ++i)
      {
         ZeroMemory(m_rows[i]);
         m_rows[i].id = (ENUM_AW_SETUP_ID)i;
         m_rows[i].name = AW_Pro_SetupName((ENUM_AW_SETUP_ID)i);
         m_rows[i].perf.name = m_rows[i].name;
         m_rows[i].paused = false;
         m_rows[i].pauseReason = "";
      }
   }

   void OnTradeClosed(const AWTradeRecord &rec)
   {
      const int idx = (int)rec.setupId;
      if(idx <= 0 || idx >= AW_SETUP_COUNT) return;
      // Recompute from single apply — store via local stats helper
      ApplyRow(m_rows[idx].perf, rec);
   }

   AWSetupDbRow Get(const ENUM_AW_SETUP_ID id) const
   {
      const int idx = (int)id;
      if(idx < 0 || idx >= ArraySize(m_rows))
      {
         AWSetupDbRow empty; ZeroMemory(empty); return empty;
      }
      return m_rows[idx];
   }

   bool IsPaused(const ENUM_AW_SETUP_ID id) const
   {
      const int idx = (int)id;
      if(idx < 0 || idx >= ArraySize(m_rows)) return false;
      return m_rows[idx].paused;
   }

   void SetPaused(const ENUM_AW_SETUP_ID id, const bool paused, const string reason)
   {
      const int idx = (int)id;
      if(idx < 0 || idx >= ArraySize(m_rows)) return;
      m_rows[idx].paused = paused;
      m_rows[idx].pauseReason = reason;
      m_rows[idx].pausedAt = TimeCurrent();
      PrintFormat("[AW SetupDB] setup=%s paused=%s reason=%s",
                  m_rows[idx].name, paused ? "true" : "false", reason);
   }

   string Snapshot() const
   {
      string out = "SetupDB:\n";
      for(int i = 1; i < ArraySize(m_rows); ++i)
      {
         const AWSetupDbRow r = m_rows[i];
         out += StringFormat("  %s n=%d PF=%.2f Exp=%.2f paused=%s %s\n",
                             r.name, r.perf.trades, r.perf.ProfitFactor(), r.perf.Expectancy(),
                             r.paused ? "Y" : "N", r.pauseReason);
      }
      return out;
   }

private:
   void ApplyRow(AWPerfSlice &s, const AWTradeRecord &rec)
   {
      s.trades++;
      s.sumR += rec.rMultiple;
      s.equityCurve += rec.pnl;
      if(s.equityCurve > s.peak) s.peak = s.equityCurve;
      const double dd = s.peak - s.equityCurve;
      if(dd > s.maxDd) s.maxDd = dd;
      if(rec.pnl > 0.0)
      {
         s.wins++; s.grossWin += rec.pnl;
         s.curConsecWin++; s.curConsecLoss = 0;
         if(s.curConsecWin > s.maxConsecWin) s.maxConsecWin = s.curConsecWin;
      }
      else
      {
         s.losses++; s.grossLoss += MathAbs(rec.pnl);
         s.curConsecLoss++; s.curConsecWin = 0;
         if(s.curConsecLoss > s.maxConsecLoss) s.maxConsecLoss = s.curConsecLoss;
      }
   }
};

#endif
