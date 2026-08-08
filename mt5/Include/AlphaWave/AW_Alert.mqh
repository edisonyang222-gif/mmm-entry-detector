//+------------------------------------------------------------------+
//| AW_Alert.mqh                                                      |
//| Alert when trade score reaches threshold (no trading)             |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_ALERT_MQH
#define AW_ALERT_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"

class CAWAlert
  {
private:
   CAWLogger        *m_logger;
   bool              m_enable;
   bool              m_popup;
   bool              m_push;
   bool              m_sound;
   string            m_sound_file;
   string            m_last_key;

public:
                     CAWAlert(void)
     {
      m_logger=NULL;
      m_enable=true;
      m_popup=true;
      m_push=false;
      m_sound=true;
      m_sound_file="alert.wav";
      m_last_key="";
     }

   bool Init(CAWLogger *logger,
             const bool enable,
             const bool popup,
             const bool push,
             const bool sound,
             const string sound_file)
     {
      m_logger=logger;
      m_enable=enable;
      m_popup=popup;
      m_push=push;
      m_sound=sound;
      m_sound_file=sound_file;
      if(m_logger!=NULL)
         m_logger.Info("Alert","initialized (analysis alerts only)");
      return true;
     }

   void DailyReset(const AWDailyContext &ctx)
     {
      AW_UNUSED(ctx);
      m_last_key="";
     }

   void MaybeAlert(const string symbol,
                   const AWScoreState &score,
                   const AWConfirmState &conf,
                   const int min_score)
     {
      if(!m_enable) return;
      if(score.score<min_score) return;
      if(score.direction==AW_SIGNAL_NONE) return;

      const string key=StringFormat("%s|%s|%d|%s|%s",
                                    symbol,
                                    AW_SignalDirToText(score.direction),
                                    score.score,
                                    score.setup_name,
                                    TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES));
      // de-dupe same minute content
      const string dedupe=StringFormat("%s|%s|%s|%s",
                                       symbol,
                                       AW_SignalDirToText(score.direction),
                                       score.setup_name,
                                       TimeToString(iTime(symbol,PERIOD_M5,0),TIME_DATE|TIME_MINUTES));
      if(dedupe==m_last_key)
         return;
      m_last_key=dedupe;

      const string msg=StringFormat(
         "Alpha Wave Lite ALERT\nSymbol: %s\nDirection: %s\nScore: %d (%s)\nSetup: %s\nTime: %s\nConfirmation: %s",
         symbol,
         AW_SignalDirToText(score.direction),
         score.score,
         AW_ScoreBandToText(score.band),
         score.setup_name,
         TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
         (conf.active? conf.name : "None"));

      if(m_logger!=NULL)
         m_logger.Info("Alert",msg);

      if(m_popup)
         Alert(msg);
      if(m_sound)
         PlaySound(m_sound_file);
      if(m_push)
         SendNotification(msg);

      AW_UNUSED(key);
     }
  };

#endif
//+------------------------------------------------------------------+
