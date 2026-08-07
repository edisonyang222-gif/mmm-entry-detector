//+------------------------------------------------------------------+
//| AW_SetupDetector.mqh                                              |
//| M15 primary setup scaffolding                                     |
//| TODO: implement setup patterns; keep each condition toggleable    |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_SETUP_DETECTOR_MQH
#define AW_SETUP_DETECTOR_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"

class CAWSetupDetector
  {
private:
   string            m_symbol;
   CAWLogger        *m_logger;
   bool              m_enable;
   bool              m_enable_setup_a;
   bool              m_enable_setup_b;
   bool              m_enable_setup_c;
   string            m_last_setup_id;
   datetime          m_last_setup_bar_time;
   ENUM_AW_SIGNAL_DIR m_last_dir;

public:
                     CAWSetupDetector(void)
     {
      m_symbol="";
      m_logger=NULL;
      m_enable=true;
      m_enable_setup_a=true;
      m_enable_setup_b=true;
      m_enable_setup_c=false;
      m_last_setup_id="";
      m_last_setup_bar_time=0;
      m_last_dir=AW_SIGNAL_NONE;
     }

   bool              Init(const string symbol,
                          CAWLogger *logger,
                          const bool enable,
                          const bool enable_setup_a,
                          const bool enable_setup_b,
                          const bool enable_setup_c)
     {
      m_symbol=symbol;
      m_logger=logger;
      m_enable=enable;
      m_enable_setup_a=enable_setup_a;
      m_enable_setup_b=enable_setup_b;
      m_enable_setup_c=enable_setup_c;
      if(m_logger!=NULL)
         m_logger.Info("SetupDetector","initialized");
      return true;
     }

   void              DailyReset(const AWDailyContext &ctx)
     {
      AW_UNUSED(ctx);
      m_last_setup_id="";
      m_last_setup_bar_time=0;
      m_last_dir=AW_SIGNAL_NONE;
      if(m_logger!=NULL)
         m_logger.Debug("SetupDetector","DailyReset");
     }

   void              Update(void)
     {
      if(!m_enable)
        {
         m_last_dir=AW_SIGNAL_NONE;
         return;
        }
      // TODO: detect M15 setups using MarketStructure/Liquidity/Fib modules.
      // IMPORTANT: same bar must not re-trigger the same setup id.
      AW_UNUSED(m_symbol);
      AW_UNUSED(m_enable_setup_a);
      AW_UNUSED(m_enable_setup_b);
      AW_UNUSED(m_enable_setup_c);
     }

   bool              HasSetup(void) const { return(m_last_dir!=AW_SIGNAL_NONE); }
   string            LastSetupId(void) const { return m_last_setup_id; }
   ENUM_AW_SIGNAL_DIR LastDirection(void) const { return m_last_dir; }
   datetime          LastSetupBarTime(void) const { return m_last_setup_bar_time; }

   bool              ConsumeIfNewBar(const string setup_id,
                                     const datetime bar_time,
                                     const ENUM_AW_SIGNAL_DIR dir)
     {
      // Helper for future strategy code: prevent duplicate same-signal on same bar.
      if(setup_id==m_last_setup_id && bar_time==m_last_setup_bar_time)
         return false;
      m_last_setup_id=setup_id;
      m_last_setup_bar_time=bar_time;
      m_last_dir=dir;
      return true;
     }
  };

#endif
//+------------------------------------------------------------------+
