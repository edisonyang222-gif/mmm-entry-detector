//+------------------------------------------------------------------+
//| AW_Inst_AutoDisable.mqh                                          |
//| Auto Disable Weak Setup — DEFAULT OFF                            |
//| Only after minSamples; pauses setup; records reason              |
//| Does NOT rewrite strategy parameters                             |
//+------------------------------------------------------------------+
#ifndef AW_INST_AUTO_DISABLE_MQH
#define AW_INST_AUTO_DISABLE_MQH
#include "AW_Inst_SetupDB.mqh"

struct AWAutoDisableConfig
{
   bool   enabled;          // default false
   int    minSamples;       // e.g. 100
   double minProfitFactor;
   double minExpectancy;
};

class CAWInstAutoDisable
{
private:
   AWAutoDisableConfig m_cfg;

public:
   void Init(const AWAutoDisableConfig &cfg) { m_cfg = cfg; }

   void Evaluate(CAWInstSetupDB &db)
   {
      if(!m_cfg.enabled) return;
      for(int i = 1; i < AW_SETUP_COUNT; ++i)
      {
         const ENUM_AW_SETUP_ID id = (ENUM_AW_SETUP_ID)i;
         const AWSetupDbRow row = db.Get(id);
         if(row.paused) continue;
         if(row.perf.trades < m_cfg.minSamples) continue;

         string reason = "";
         bool weak = false;
         if(row.perf.ProfitFactor() < m_cfg.minProfitFactor)
         {
            weak = true;
            reason += StringFormat("PF %.2f < %.2f; ", row.perf.ProfitFactor(), m_cfg.minProfitFactor);
         }
         if(row.perf.Expectancy() < m_cfg.minExpectancy)
         {
            weak = true;
            reason += StringFormat("Exp %.2f < %.2f; ", row.perf.Expectancy(), m_cfg.minExpectancy);
         }
         if(weak)
         {
            reason = StringFormat("AutoDisable after %d samples: %s", row.perf.trades, reason);
            db.SetPaused(id, true, reason);
         }
      }
   }
};

#endif
