//+------------------------------------------------------------------+
//| AW_ConfirmationManager.mqh                                        |
//| M5 entry confirmation scaffolding                                 |
//| TODO: implement confirmation candle / micro-structure rules       |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_CONFIRMATION_MANAGER_MQH
#define AW_CONFIRMATION_MANAGER_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"

class CAWConfirmationManager
  {
private:
   string            m_symbol;
   CAWLogger        *m_logger;
   bool              m_enable;
   bool              m_confirmed;
   string            m_reason;

public:
                     CAWConfirmationManager(void)
     {
      m_symbol="";
      m_logger=NULL;
      m_enable=true;
      m_confirmed=false;
      m_reason="";
     }

   bool              Init(const string symbol,CAWLogger *logger,const bool enable)
     {
      m_symbol=symbol;
      m_logger=logger;
      m_enable=enable;
      if(m_logger!=NULL)
         m_logger.Info("ConfirmationManager","initialized");
      return true;
     }

   void              DailyReset(const AWDailyContext &ctx)
     {
      AW_UNUSED(ctx);
      m_confirmed=false;
      m_reason="";
      if(m_logger!=NULL)
         m_logger.Debug("ConfirmationManager","DailyReset");
     }

   void              Update(void)
     {
      if(!m_enable)
        {
         m_confirmed=false;
         m_reason="confirmation_disabled";
         return;
        }
      // TODO: confirm M15 setup on M5 closed bars.
      AW_UNUSED(m_symbol);
      m_confirmed=false;
      m_reason="awaiting_strategy_rules";
     }

   bool              IsConfirmed(void) const { return m_confirmed; }
   string            Reason(void) const { return m_reason; }
  };

#endif
//+------------------------------------------------------------------+
