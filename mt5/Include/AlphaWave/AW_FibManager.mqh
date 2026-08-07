//+------------------------------------------------------------------+
//| AW_FibManager.mqh                                                 |
//| Fibonacci levels scaffolding                                      |
//| TODO: define swing anchors and OTE / retracement rules            |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_FIB_MANAGER_MQH
#define AW_FIB_MANAGER_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"

class CAWFibManager
  {
private:
   string            m_symbol;
   CAWLogger        *m_logger;
   bool              m_enable;
   double            m_level_382;
   double            m_level_500;
   double            m_level_618;
   double            m_level_705;
   double            m_anchor_high;
   double            m_anchor_low;
   bool              m_valid;

public:
                     CAWFibManager(void)
     {
      m_symbol="";
      m_logger=NULL;
      m_enable=true;
      m_level_382=0.0;
      m_level_500=0.0;
      m_level_618=0.0;
      m_level_705=0.0;
      m_anchor_high=0.0;
      m_anchor_low=0.0;
      m_valid=false;
     }

   bool              Init(const string symbol,CAWLogger *logger,const bool enable)
     {
      m_symbol=symbol;
      m_logger=logger;
      m_enable=enable;
      if(m_logger!=NULL)
         m_logger.Info("FibManager","initialized");
      return true;
     }

   void              DailyReset(const AWDailyContext &ctx)
     {
      AW_UNUSED(ctx);
      m_level_382=0.0;
      m_level_500=0.0;
      m_level_618=0.0;
      m_level_705=0.0;
      m_anchor_high=0.0;
      m_anchor_low=0.0;
      m_valid=false;
      if(m_logger!=NULL)
         m_logger.Debug("FibManager","DailyReset");
     }

   void              Update(void)
     {
      if(!m_enable)
        {
         m_valid=false;
         return;
        }
      // TODO: locate swing high/low anchors and compute Fib levels.
      AW_UNUSED(m_symbol);
     }

   bool              IsValid(void) const { return m_valid; }
   double            Level382(void) const { return m_level_382; }
   double            Level500(void) const { return m_level_500; }
   double            Level618(void) const { return m_level_618; }
   double            Level705(void) const { return m_level_705; }
  };

#endif
//+------------------------------------------------------------------+
