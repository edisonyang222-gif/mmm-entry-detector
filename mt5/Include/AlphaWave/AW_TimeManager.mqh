//+------------------------------------------------------------------+
//| AW_TimeManager.mqh                                                |
//| Alpha Wave — UTC+8 轉換、交易日 04:45、每日 reset 偵測              |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_TIME_MANAGER_MQH
#define AW_TIME_MANAGER_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"

class CAWTimeManager
  {
private:
   CAWLogger        *m_log;
   int               m_brokerUtcOffsetHours; // 券商伺服器相對 UTC 的時差（小時）
   int               m_tradeTzOffsetHours;   // 交易基準時區，預設 +8
   int               m_sessionStartHour;     // UTC+8 日切換：時
   int               m_sessionStartMinute;   // UTC+8 日切換：分
   datetime          m_lastSessionDayKey;    // 上次已處理的交易日 key（UTC+8 04:45）
   bool              m_ready;

   datetime NormalizeToHourMinute(const datetime src, const int hour, const int minute) const
     {
      MqlDateTime dt;
      TimeToStruct(src, dt);
      dt.hour = hour;
      dt.min  = minute;
      dt.sec  = 0;
      return StructToTime(dt);
     }

public:
   CAWTimeManager(void)
     {
      m_log = NULL;
      m_brokerUtcOffsetHours = 2;
      m_tradeTzOffsetHours   = 8;
      m_sessionStartHour     = 4;
      m_sessionStartMinute   = 45;
      m_lastSessionDayKey    = 0;
      m_ready = false;
     }

   bool Init(CAWLogger *logger,
             const int brokerUtcOffsetHours,
             const int tradeTzOffsetHours = 8,
             const int sessionStartHour = 4,
             const int sessionStartMinute = 45)
     {
      m_log = logger;
      m_brokerUtcOffsetHours = brokerUtcOffsetHours;
      m_tradeTzOffsetHours   = tradeTzOffsetHours;
      m_sessionStartHour     = sessionStartHour;
      m_sessionStartMinute   = sessionStartMinute;
      m_lastSessionDayKey    = 0;
      m_ready = true;

      if(m_log != NULL)
         m_log.Info("TimeManager",
                    StringFormat("Init brokerUTC=%+d tradeTZ=UTC%+d session=%02d:%02d",
                                 m_brokerUtcOffsetHours,
                                 m_tradeTzOffsetHours,
                                 m_sessionStartHour,
                                 m_sessionStartMinute));
      return true;
     }

   //--- 券商伺服器時間 → UTC
   datetime ServerToUtc(const datetime serverTime) const
     {
      return serverTime - (datetime)(m_brokerUtcOffsetHours * 3600);
     }

   //--- UTC → 券商伺服器時間
   datetime UtcToServer(const datetime utcTime) const
     {
      return utcTime + (datetime)(m_brokerUtcOffsetHours * 3600);
     }

   //--- 券商伺服器時間 → UTC+8（或自訂交易時區）
   datetime ServerToTradeTz(const datetime serverTime) const
     {
      const datetime utc = ServerToUtc(serverTime);
      return utc + (datetime)(m_tradeTzOffsetHours * 3600);
     }

   //--- 交易時區 → 券商伺服器時間
   datetime TradeTzToServer(const datetime tradeTzTime) const
     {
      const datetime utc = tradeTzTime - (datetime)(m_tradeTzOffsetHours * 3600);
      return UtcToServer(utc);
     }

   datetime NowServer(void) const { return TimeCurrent(); }
   datetime NowBroker(void) const { return NowServer(); } // alias
   datetime NowTradeTz(void) const { return ServerToTradeTz(TimeCurrent()); }

   //--- UTC+8（交易時區）當日已過分鐘數 0..1439
   int Utc8MinutesOfDay(const datetime serverTime) const
     {
      MqlDateTime dt;
      TimeToStruct(ServerToTradeTz(serverTime),dt);
      return(dt.hour*60+dt.min);
     }

   //--- 取得「該時刻所屬交易日」的起始（交易時區 04:45）
   datetime SessionDayStartTradeTz(const datetime tradeTzTime) const
     {
      const datetime todayStart = NormalizeToHourMinute(tradeTzTime,
                                                        m_sessionStartHour,
                                                        m_sessionStartMinute);
      if(tradeTzTime >= todayStart)
         return todayStart;
      return todayStart - 86400;
     }

   datetime SessionDayStartServer(const datetime serverTime) const
     {
      return TradeTzToServer(SessionDayStartTradeTz(ServerToTradeTz(serverTime)));
     }

   datetime CurrentSessionDayKey(void) const
     {
      return SessionDayStartTradeTz(NowTradeTz());
     }

   //--- 是否跨越新的交易日（04:45 UTC+8）
   // 回傳 true 時，呼叫端應執行 DailyReset
   bool CheckAndConsumeDailyReset(datetime &outSessionDayKey)
     {
      outSessionDayKey = 0;
      if(!m_ready)
         return false;

      const datetime key = CurrentSessionDayKey();
      if(m_lastSessionDayKey == 0)
        {
         // 首次掛載：記錄當日 key，並視為需要一次初始化 reset
         m_lastSessionDayKey = key;
         outSessionDayKey = key;
         if(m_log != NULL)
            m_log.LogDailyReset(key);
         return true;
        }

      if(key != m_lastSessionDayKey)
        {
         m_lastSessionDayKey = key;
         outSessionDayKey = key;
         if(m_log != NULL)
            m_log.LogDailyReset(key);
         return true;
        }
      return false;
     }

   //--- 強制標記已 reset（測試用）
   void ForceSetSessionDayKey(const datetime key)
     {
      m_lastSessionDayKey = key;
     }

   int BrokerUtcOffsetHours(void) const { return m_brokerUtcOffsetHours; }
   int TradeTzOffsetHours(void) const { return m_tradeTzOffsetHours; }
   int SessionStartHour(void) const { return m_sessionStartHour; }
   int SessionStartMinute(void) const { return m_sessionStartMinute; }
  };

#endif // AW_TIME_MANAGER_MQH
//+------------------------------------------------------------------+
