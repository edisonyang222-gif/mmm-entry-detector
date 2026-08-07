//+------------------------------------------------------------------+
//| AW_Inst_TradeScore.mqh                                           |
//| Advanced Trade Score — base 100 → grade A+/A/B/C/NO TRADE        |
//+------------------------------------------------------------------+
#ifndef AW_INST_TRADE_SCORE_MQH
#define AW_INST_TRADE_SCORE_MQH
#include "AW_Inst_Defines.mqh"
#include "AW_Inst_Regime.mqh"
#include "../Pro/AW_Pro_Defines.mqh"

struct AWScoreConfig
{
   // Component max points (should sum conceptually around base path)
   int ptsRegime;
   int ptsSession;
   int ptsAtr;
   int ptsSweep;
   int ptsHtfAlign;
   int ptsFreshness;
   int ptsConfirm;
   // Grade thresholds on final weighted score
   int gradeAPlus;
   int gradeA;
   int gradeB;
   int gradeC;
   // Dynamic minimum
   int minScoreNormal;
   int minScoreHighVol;
   int minScoreLowLiquidity;
   bool blockLowVol;
   bool blockUnstable;
};

struct AWScoreResult
{
   int score;              // 0-100+ after weight, clipped display 0-100
   int rawScore;
   ENUM_AW_GRADE grade;
   int minRequired;
   bool pass;
   int cRegime, cSession, cAtr, cSweep, cHtf, cFresh, cConfirm;
   string reason;
};

class CAWInstTradeScore
{
private:
   AWScoreConfig m_cfg;

public:
   void Init(const AWScoreConfig &cfg) { m_cfg = cfg; }

   int DynamicMinScore(const ENUM_AW_REGIME regime, const bool lowLiquiditySession) const
   {
      if(regime == AW_REGIME_LOW_VOL && m_cfg.blockLowVol)
         return 1000; // impossible → block
      if(regime == AW_REGIME_UNSTABLE && m_cfg.blockUnstable)
         return 1000;
      if(lowLiquiditySession)
         return m_cfg.minScoreLowLiquidity;
      if(regime == AW_REGIME_HIGH_VOL)
         return m_cfg.minScoreHighVol;
      return m_cfg.minScoreNormal;
   }

   AWScoreResult Evaluate(const AWProSignal &sig,
                          const AWRegimeState &reg,
                          const double setupWeight,
                          const bool sessionQualityOk,
                          const bool lowLiquiditySession,
                          const bool htfAligned,
                          const int barsSinceSetupFresh) // freshness: smaller better
   {
      AWScoreResult r;
      ZeroMemory(r);

      // --- components (additive toward ~100) ---
      // Regime quality
      switch(reg.regime)
      {
         case AW_REGIME_TRENDING: r.cRegime = m_cfg.ptsRegime; break;
         case AW_REGIME_RANGING:  r.cRegime = (int)(m_cfg.ptsRegime * 0.7); break;
         case AW_REGIME_HIGH_VOL: r.cRegime = (int)(m_cfg.ptsRegime * 0.5); break;
         case AW_REGIME_LOW_VOL:  r.cRegime = (int)(m_cfg.ptsRegime * 0.2); break;
         default:                 r.cRegime = 0; break;
      }

      r.cSession = sessionQualityOk ? m_cfg.ptsSession : 0;

      // ATR quality: prefer near 1.0 ratio
      const double ratio = reg.atrRatio;
      if(ratio >= 0.8 && ratio <= 1.4) r.cAtr = m_cfg.ptsAtr;
      else if(ratio >= 0.6 && ratio <= 1.8) r.cAtr = (int)(m_cfg.ptsAtr * 0.6);
      else r.cAtr = (int)(m_cfg.ptsAtr * 0.2);

      // Sweep quality from signal flags / confirm
      if(sig.hasSweep) r.cSweep = m_cfg.ptsSweep;
      else r.cSweep = (int)(m_cfg.ptsSweep * 0.25);

      r.cHtf = htfAligned ? m_cfg.ptsHtfAlign : 0;

      // Freshness: signal on just-closed bar is freshest
      if(barsSinceSetupFresh <= 1) r.cFresh = m_cfg.ptsFreshness;
      else if(barsSinceSetupFresh <= 3) r.cFresh = (int)(m_cfg.ptsFreshness * 0.6);
      else r.cFresh = (int)(m_cfg.ptsFreshness * 0.2);

      r.cConfirm = (int)MathRound(m_cfg.ptsConfirm * (sig.confirmStrength / 5.0));

      r.rawScore = r.cRegime + r.cSession + r.cAtr + r.cSweep + r.cHtf + r.cFresh + r.cConfirm;
      // Start from base 100 scaled by component fill then apply setup weight
      const int maxPts = MathMax(1, m_cfg.ptsRegime + m_cfg.ptsSession + m_cfg.ptsAtr +
                                 m_cfg.ptsSweep + m_cfg.ptsHtfAlign + m_cfg.ptsFreshness + m_cfg.ptsConfirm);
      r.score = (int)MathRound(100.0 * r.rawScore / maxPts * setupWeight);
      r.score = (int)MathMax(0, MathMin(100, r.score));

      if(r.score >= m_cfg.gradeAPlus) r.grade = AW_GRADE_A_PLUS;
      else if(r.score >= m_cfg.gradeA) r.grade = AW_GRADE_A;
      else if(r.score >= m_cfg.gradeB) r.grade = AW_GRADE_B;
      else if(r.score >= m_cfg.gradeC) r.grade = AW_GRADE_C;
      else r.grade = AW_GRADE_NO_TRADE;

      r.minRequired = DynamicMinScore(reg.regime, lowLiquiditySession);
      r.pass = (r.score >= r.minRequired && r.grade != AW_GRADE_NO_TRADE);
      if(!r.pass)
         r.reason = StringFormat("score %d < min %d or grade NO TRADE", r.score, r.minRequired);
      else
         r.reason = "pass";
      return r;
   }
};

#endif
