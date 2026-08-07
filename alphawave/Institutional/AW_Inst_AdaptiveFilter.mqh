//+------------------------------------------------------------------+
//| AW_Inst_AdaptiveFilter.mqh                                       |
//| Adaptive Trade Filter — enable/disable Pro setups by regime      |
//| NO AI / NO auto parameter mutation                               |
//+------------------------------------------------------------------+
#ifndef AW_INST_ADAPTIVE_FILTER_MQH
#define AW_INST_ADAPTIVE_FILTER_MQH
#include "AW_Inst_Defines.mqh"
#include "../Pro/AW_Pro_Defines.mqh"

struct AWAdaptiveConfig
{
   // Per-regime: allow trend-like setups / allow range-like setups
   bool trendingAllowTrendSetups;
   bool trendingAllowRangeSetups;
   bool rangingAllowTrendSetups;
   bool rangingAllowRangeSetups;
   bool highVolAllowTrendSetups;
   bool highVolAllowRangeSetups;
   bool lowVolAllowAny;
   bool unstableAllowAny;
   // Weight multipliers for score (not lot!) — reduce junk without adding trades
   double weightTrendingTrend;
   double weightTrendingRange;
   double weightRangingTrend;
   double weightRangingRange;
   double weightHighVol;
   double weightLowVol;
   double weightUnstable;
};

class CAWInstAdaptiveFilter
{
private:
   AWAdaptiveConfig m_cfg;

public:
   void Init(const AWAdaptiveConfig &cfg) { m_cfg = cfg; }

   bool IsTrendLikeSetup(const ENUM_AW_SETUP_ID id) const
   {
      return (id == AW_SETUP_FIB_SWEEP_BOS || id == AW_SETUP_SWEEP_BOS ||
              id == AW_SETUP_FIB_CHOCH);
   }

   bool IsRangeLikeSetup(const ENUM_AW_SETUP_ID id) const
   {
      return (id == AW_SETUP_FIB_SWEEP_ENGULFING || id == AW_SETUP_SWEEP_ENGULFING ||
              id == AW_SETUP_FIB_ENGULFING);
   }

   bool AllowSetup(const ENUM_AW_REGIME regime, const ENUM_AW_SETUP_ID id) const
   {
      const bool trendLike = IsTrendLikeSetup(id);
      const bool rangeLike = IsRangeLikeSetup(id);
      switch(regime)
      {
         case AW_REGIME_TRENDING:
            if(trendLike) return m_cfg.trendingAllowTrendSetups;
            if(rangeLike) return m_cfg.trendingAllowRangeSetups;
            return true;
         case AW_REGIME_RANGING:
            if(trendLike) return m_cfg.rangingAllowTrendSetups;
            if(rangeLike) return m_cfg.rangingAllowRangeSetups;
            return true;
         case AW_REGIME_HIGH_VOL:
            if(trendLike) return m_cfg.highVolAllowTrendSetups;
            if(rangeLike) return m_cfg.highVolAllowRangeSetups;
            return true;
         case AW_REGIME_LOW_VOL:
            return m_cfg.lowVolAllowAny;
         case AW_REGIME_UNSTABLE:
         default:
            return m_cfg.unstableAllowAny;
      }
   }

   double SetupWeight(const ENUM_AW_REGIME regime, const ENUM_AW_SETUP_ID id) const
   {
      const bool trendLike = IsTrendLikeSetup(id);
      switch(regime)
      {
         case AW_REGIME_TRENDING:
            return trendLike ? m_cfg.weightTrendingTrend : m_cfg.weightTrendingRange;
         case AW_REGIME_RANGING:
            return trendLike ? m_cfg.weightRangingTrend : m_cfg.weightRangingRange;
         case AW_REGIME_HIGH_VOL:
            return m_cfg.weightHighVol;
         case AW_REGIME_LOW_VOL:
            return m_cfg.weightLowVol;
         default:
            return m_cfg.weightUnstable;
      }
   }
};

#endif
