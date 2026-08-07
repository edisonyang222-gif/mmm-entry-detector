//+------------------------------------------------------------------+
//| AW_SessionManager.mqh                                             |
//| UTC+8 session windows scaffolding                                 |
//| TODO: define Asia / London / NY windows and filters               |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_SESSION_MANAGER_MQH
#define AW_SESSION_MANAGER_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"
#include "AW_TimeManager.mqh"

class CAWSessionManager
  {
private:
   CAWLogger        *m_logger;
   CAWTimeManager   *m_time;
   bool              m_enable_asia;
   bool              m_enable_london;
   bool              m_enable_ny;
   int               m_asia_start_min;   // minutes from midnight UTC+8
   int               m_asia_end_min;
   int               m_london_start_min;
   int               m_london_end_min;
   int               m_ny_start_min;
   int               m_ny_end_min;
   string            m_active_session;

public:
                     CAWSessionManager(void)
     {
      m_logger=NULL;
      m_time=NULL;
      m_enable_asia=true;
      m_enable_london=true;
      m_enable_ny=true;
      // Defaults are placeholders only — refine later with confirmed session rules.
      m_asia_start_min=0;      // 00:00
      m_asia_end_min=480;      // 08:00
      m_london_start_min=480;  // 08:00
      m_london_end_min=960;    // 16:00
      m_ny_start_min=780;      // 13:00
      m_ny_end_min=1320;       // 22:00
      m_active_session="NONE";
     }

   bool              Init(CAWLogger *logger,
                          CAWTimeManager *time_mgr,
                          const bool enable_asia,
                          const bool enable_london,
                          const bool enable_ny,
                          const int asia_start_min,
                          const int asia_end_min,
                          const int london_start_min,
                          const int london_end_min,
                          const int ny_start_min,
                          const int ny_end_min)
     {
      m_logger=logger;
      m_time=time_mgr;
      m_enable_asia=enable_asia;
      m_enable_london=enable_london;
      m_enable_ny=enable_ny;
      m_asia_start_min=asia_start_min;
      m_asia_end_min=asia_end_min;
      m_london_start_min=london_start_min;
      m_london_end_min=london_end_min;
      m_ny_start_min=ny_start_min;
      m_ny_end_min=ny_end_min;
      if(m_logger!=NULL)
         m_logger.Info("SessionManager","initialized");
      return true;
     }

   void              DailyReset(const AWDailyContext &ctx)
     {
      AW_UNUSED(ctx);
      m_active_session="NONE";
      if(m_logger!=NULL)
         m_logger.Debug("SessionManager","DailyReset");
     }

   void              Update(void)
     {
      // TODO: refine overlap handling and tradable-session policy.
      if(m_time==NULL)
        {
         m_active_session="NONE";
         return;
        }

      const int mins=m_time.Utc8MinutesOfDay(m_time.NowBroker());
      m_active_session="OFF";

      if(m_enable_asia && InWindow(mins,m_asia_start_min,m_asia_end_min))
         m_active_session="ASIA";
      if(m_enable_london && InWindow(mins,m_london_start_min,m_london_end_min))
         m_active_session=(m_active_session=="ASIA" ? "ASIA_LONDON" : "LONDON");
      if(m_enable_ny && InWindow(mins,m_ny_start_min,m_ny_end_min))
        {
         if(m_active_session=="LONDON" || m_active_session=="ASIA_LONDON")
            m_active_session="LONDON_NY";
         else if(m_active_session=="OFF")
            m_active_session="NY";
         else
            m_active_session=m_active_session+"_NY";
        }
     }

   string            ActiveSession(void) const { return m_active_session; }

   bool              IsTradableSession(void) const
     {
      // TODO: decide which sessions are tradable for Lite/Pro/Institutional.
      return(m_active_session!="OFF" && m_active_session!="NONE");
     }

private:
   bool              InWindow(const int mins,const int start_min,const int end_min) const
     {
      if(start_min==end_min)
         return false;
      if(start_min<end_min)
         return(mins>=start_min && mins<end_min);
      // Overnight window
      return(mins>=start_min || mins<end_min);
     }
  };

#endif
//+------------------------------------------------------------------+
