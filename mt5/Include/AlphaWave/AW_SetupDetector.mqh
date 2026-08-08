//+------------------------------------------------------------------+
//| AW_SetupDetector.mqh                                              |
//| Aggregates current Lite setup view (Fib-centric)                  |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_SETUP_DETECTOR_MQH
#define AW_SETUP_DETECTOR_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"
#include "AW_FibManager.mqh"

class CAWSetupDetector
  {
private:
   CAWLogger        *m_logger;
   bool              m_enable;
   string            m_last_setup_id;
   datetime          m_last_setup_bar_time;
   ENUM_AW_SIGNAL_DIR m_last_dir;
   string            m_label;

public:
                     CAWSetupDetector(void)
     {
      m_logger=NULL;
      m_enable=true;
      m_last_setup_id="";
      m_last_setup_bar_time=0;
      m_last_dir=AW_SIGNAL_NONE;
      m_label="None";
     }

   bool Init(CAWLogger *logger,const bool enable)
     {
      m_logger=logger;
      m_enable=enable;
      if(m_logger!=NULL)
         m_logger.Info("SetupDetector","initialized");
      return true;
     }

   void DailyReset(const AWDailyContext &ctx)
     {
      AW_UNUSED(ctx);
      m_last_setup_id="";
      m_last_setup_bar_time=0;
      m_last_dir=AW_SIGNAL_NONE;
      m_label="None";
     }

   void UpdateFromFib(const AWFibSetupState &fib)
     {
      if(!m_enable)
        {
         m_label="None";
         m_last_dir=AW_SIGNAL_NONE;
         return;
        }
      if(!fib.ready)
        {
         m_label="None";
         m_last_dir=AW_SIGNAL_NONE;
         return;
        }
      m_last_dir=fib.direction;
      if(fib.in_zone)
         m_label=StringFormat("Fib0.5 %s",AW_SignalDirToText(fib.direction));
      else if(fib.two_leg_pullback)
         m_label=StringFormat("FibPB %s",AW_SignalDirToText(fib.direction));
      else
         m_label=StringFormat("FibArmed %s",AW_SignalDirToText(fib.direction));
     }

   void Update(void) {}

   bool HasSetup(void) const { return(m_last_dir!=AW_SIGNAL_NONE); }
   string LastSetupId(void) const { return m_last_setup_id; }
   string Label(void) const { return m_label; }
   ENUM_AW_SIGNAL_DIR LastDirection(void) const { return m_last_dir; }
   datetime LastSetupBarTime(void) const { return m_last_setup_bar_time; }

   bool ConsumeIfNewBar(const string setup_id,const datetime bar_time,const ENUM_AW_SIGNAL_DIR dir)
     {
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
