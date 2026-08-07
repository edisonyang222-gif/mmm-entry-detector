//+------------------------------------------------------------------+
//| AW_Inst_Regime.mqh                                               |
//| Market Regime Detector — all thresholds are inputs               |
//| Uses ATR, ADX, M15/H1 structure bias, session range              |
//+------------------------------------------------------------------+
#ifndef AW_INST_REGIME_MQH
#define AW_INST_REGIME_MQH
#include "AW_Inst_Defines.mqh"
#include "../Pro/AW_Pro_Defines.mqh"

struct AWRegimeConfig
{
   int    atrPeriod;
   int    atrMaPeriod;
   int    adxPeriod;
   double adxTrendMin;       // ADX >= → trending candidate
   double adxRangeMax;       // ADX <= → ranging candidate
   double atrHighMult;       // ATR/ATR_MA >= → high vol
   double atrLowMult;        // ATR/ATR_MA <= → low vol
   double sessionRangeAtrHigh; // session range / ATR high
   double unstableFlipBars;  // structure flips within N bars → unstable
   int    structureFlipLookback;
};

struct AWRegimeState
{
   ENUM_AW_REGIME regime;
   double atr;
   double atrMa;
   double atrRatio;
   double adx;
   double sessionRangeAtr;
   ENUM_AW_DIR h1Bias;
   ENUM_AW_DIR m15Bias;
   int    structureFlips;
};

class CAWInstRegime
{
private:
   AWRegimeConfig m_cfg;
   string m_symbol;
   int m_atrHandle;
   int m_adxHandle;
   AWRegimeState m_state;
   ENUM_AW_DIR m_biasHist[];
   int m_biasHistCount;

public:
   CAWInstRegime(): m_atrHandle(INVALID_HANDLE), m_adxHandle(INVALID_HANDLE), m_biasHistCount(0)
   {
      ZeroMemory(m_state);
      m_state.regime = AW_REGIME_UNSTABLE;
   }

   ~CAWInstRegime()
   {
      if(m_atrHandle != INVALID_HANDLE) IndicatorRelease(m_atrHandle);
      if(m_adxHandle != INVALID_HANDLE) IndicatorRelease(m_adxHandle);
   }

   bool Init(const string symbol, const AWRegimeConfig &cfg)
   {
      m_symbol = symbol;
      m_cfg = cfg;
      m_atrHandle = iATR(symbol, PERIOD_H1, cfg.atrPeriod);
      m_adxHandle = iADX(symbol, PERIOD_H1, cfg.adxPeriod);
      ArrayResize(m_biasHist, MathMax(5, cfg.structureFlipLookback));
      ArrayInitialize(m_biasHist, (int)AW_DIR_NONE);
      return (m_atrHandle != INVALID_HANDLE && m_adxHandle != INVALID_HANDLE);
   }

   AWRegimeState State() const { return m_state; }

   void Update(const ENUM_AW_DIR m15Bias, const ENUM_AW_DIR h1Bias,
               const datetime sessStart, const datetime now)
   {
      double atrBuf[], atrMaBuf[], adxBuf[];
      // Closed H1 bars only
      if(CopyBuffer(m_atrHandle, 0, 1, m_cfg.atrMaPeriod + 2, atrBuf) < m_cfg.atrMaPeriod + 1)
         return;
      if(CopyBuffer(m_adxHandle, 0, 1, 2, adxBuf) < 1)
         return;

      m_state.atr = atrBuf[0];
      double sum = 0.0;
      for(int i = 0; i < m_cfg.atrMaPeriod; ++i) sum += atrBuf[i];
      m_state.atrMa = sum / m_cfg.atrMaPeriod;
      m_state.atrRatio = (m_state.atrMa > 0.0 ? m_state.atr / m_state.atrMa : 1.0);
      m_state.adx = adxBuf[0];
      m_state.m15Bias = m15Bias;
      m_state.h1Bias = h1Bias;

      // Session range / ATR (today session so far, using M15 highs/lows — no future)
      m_state.sessionRangeAtr = CalcSessionRangeAtr(sessStart, now, m_state.atr);

      // Structure flip counter
      PushBias(h1Bias);
      m_state.structureFlips = CountFlips();

      m_state.regime = Classify();
   }

private:
   ENUM_AW_REGIME Classify() const
   {
      if(m_state.structureFlips >= (int)m_cfg.unstableFlipBars)
         return AW_REGIME_UNSTABLE;
      if(m_state.atrRatio >= m_cfg.atrHighMult || m_state.sessionRangeAtr >= m_cfg.sessionRangeAtrHigh)
         return AW_REGIME_HIGH_VOL;
      if(m_state.atrRatio <= m_cfg.atrLowMult)
         return AW_REGIME_LOW_VOL;
      if(m_state.adx >= m_cfg.adxTrendMin && m_state.m15Bias != AW_DIR_NONE &&
         m_state.m15Bias == m_state.h1Bias)
         return AW_REGIME_TRENDING;
      if(m_state.adx <= m_cfg.adxRangeMax)
         return AW_REGIME_RANGING;
      return AW_REGIME_UNSTABLE;
   }

   void PushBias(const ENUM_AW_DIR b)
   {
      const int n = ArraySize(m_biasHist);
      for(int i = n - 1; i > 0; --i)
         m_biasHist[i] = m_biasHist[i - 1];
      m_biasHist[0] = b;
      if(m_biasHistCount < n) m_biasHistCount++;
   }

   int CountFlips() const
   {
      int flips = 0;
      const int n = MathMin(m_biasHistCount, ArraySize(m_biasHist));
      for(int i = 1; i < n; ++i)
      {
         if(m_biasHist[i] != AW_DIR_NONE && m_biasHist[i - 1] != AW_DIR_NONE &&
            m_biasHist[i] != m_biasHist[i - 1])
            flips++;
      }
      return flips;
   }

   double CalcSessionRangeAtr(const datetime sessStart, const datetime now, const double atr) const
   {
      if(atr <= 0.0 || sessStart <= 0 || now < sessStart) return 0.0;
      double hi = -DBL_MAX, lo = DBL_MAX;
      const int bars = Bars(m_symbol, PERIOD_M15);
      for(int i = 1; i < bars; ++i) // start at 1 = closed
      {
         const datetime t = iTime(m_symbol, PERIOD_M15, i);
         if(t < sessStart) break;
         if(t > now) continue;
         hi = MathMax(hi, iHigh(m_symbol, PERIOD_M15, i));
         lo = MathMin(lo, iLow(m_symbol, PERIOD_M15, i));
      }
      if(hi < lo) return 0.0;
      return (hi - lo) / atr;
   }
};

#endif
