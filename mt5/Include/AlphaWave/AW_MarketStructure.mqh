//+------------------------------------------------------------------+
//| AW_MarketStructure.mqh                                            |
//| H4/H1 bias + M15 daily structure scaffolding                      |
//| TODO: implement swing structure, BOS/CHOCH, valid S/R levels      |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_MARKET_STRUCTURE_MQH
#define AW_MARKET_STRUCTURE_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"
#include "AW_TimeManager.mqh"

class CAWMarketStructure
  {
private:
   string            m_symbol;
   CAWLogger        *m_logger;
   CAWTimeManager   *m_time;
   bool              m_enable_h4;
   bool              m_enable_h1;
   bool              m_enable_m15;
   ENUM_AW_BIAS      m_h4_bias;
   ENUM_AW_BIAS      m_h1_bias;
   ENUM_AW_BIAS      m_m15_bias;
   datetime          m_last_update_broker;

public:
                     CAWMarketStructure(void)
     {
      m_symbol="";
      m_logger=NULL;
      m_time=NULL;
      m_enable_h4=true;
      m_enable_h1=true;
      m_enable_m15=true;
      m_h4_bias=AW_BIAS_NEUTRAL;
      m_h1_bias=AW_BIAS_NEUTRAL;
      m_m15_bias=AW_BIAS_NEUTRAL;
      m_last_update_broker=0;
     }

   bool              Init(const string symbol,
                          CAWLogger *logger,
                          CAWTimeManager *time_mgr,
                          const bool enable_h4,
                          const bool enable_h1,
                          const bool enable_m15)
     {
      m_symbol=symbol;
      m_logger=logger;
      m_time=time_mgr;
      m_enable_h4=enable_h4;
      m_enable_h1=enable_h1;
      m_enable_m15=enable_m15;
      if(m_logger!=NULL)
         m_logger.Info("MarketStructure","initialized");
      return true;
     }

   void              DailyReset(const AWDailyContext &ctx)
     {
      // TODO: recalculate daily structure anchors from UTC+8 04:45 open.
      AW_UNUSED(ctx);
      m_m15_bias=AW_BIAS_NEUTRAL;
      if(m_logger!=NULL)
         m_logger.Debug("MarketStructure","DailyReset");
     }

   void              Update(void)
     {
      // TODO: compute H4/H1 bias and M15 structure using non-repainting closed bars.
      AW_UNUSED(m_symbol);
      AW_UNUSED(m_time);
      m_last_update_broker=TimeCurrent();
      if(!m_enable_h4)
         m_h4_bias=AW_BIAS_NEUTRAL;
      if(!m_enable_h1)
         m_h1_bias=AW_BIAS_NEUTRAL;
      if(!m_enable_m15)
         m_m15_bias=AW_BIAS_NEUTRAL;
     }

   ENUM_AW_BIAS      GetH4Bias(void) const { return m_h4_bias; }
   ENUM_AW_BIAS      GetH1Bias(void) const { return m_h1_bias; }
   ENUM_AW_BIAS      GetM15Bias(void) const { return m_m15_bias; }
   datetime          LastUpdateBroker(void) const { return m_last_update_broker; }
  };

#endif
//+------------------------------------------------------------------+
