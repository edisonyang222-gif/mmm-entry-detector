//+------------------------------------------------------------------+
//| AW_Logger.mqh                                                     |
//| Alpha Wave — Debug / Info log，進場與拒絕原因記錄介面               |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_LOGGER_MQH
#define AW_LOGGER_MQH

#include "AW_Common.mqh"

class CAWLogger
  {
private:
   ENUM_AW_LOG_LEVEL m_minLevel;
   bool              m_toTerminal;
   bool              m_toFile;
   string            m_fileName;
   int               m_fileHandle;
   string            m_prefix;

   string LevelText(const ENUM_AW_LOG_LEVEL lv) const
     {
      switch(lv)
        {
         case AW_LOG_DEBUG: return "DEBUG";
         case AW_LOG_INFO:  return "INFO";
         case AW_LOG_WARN:  return "WARN";
         case AW_LOG_ERROR: return "ERROR";
        }
      return "LOG";
     }

   void WriteLine(const ENUM_AW_LOG_LEVEL lv, const string module, const string msg)
     {
      if(lv < m_minLevel)
         return;

      const string line = StringFormat("%s [%s] [%s] [%s] %s",
                                       TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
                                       m_prefix,
                                       LevelText(lv),
                                       module,
                                       msg);

      if(m_toTerminal)
         Print(line);

      if(m_toFile && m_fileHandle != INVALID_HANDLE)
        {
         FileWriteString(m_fileHandle, line + "\n");
         FileFlush(m_fileHandle);
        }
     }

public:
   CAWLogger(void)
     {
      m_minLevel   = AW_LOG_DEBUG;
      m_toTerminal = true;
      m_toFile     = false;
      m_fileName   = "";
      m_fileHandle = INVALID_HANDLE;
      m_prefix     = "AW";
     }

   ~CAWLogger(void)
     {
      Close();
     }

   bool Init(const string prefix,
             const ENUM_AW_LOG_LEVEL minLevel,
             const bool toTerminal,
             const bool toFile,
             const string fileName = "")
     {
      Close();
      m_prefix     = prefix;
      m_minLevel   = minLevel;
      m_toTerminal = toTerminal;
      m_toFile     = toFile;
      m_fileName   = fileName;

      if(m_toFile)
        {
         if(m_fileName == "")
            m_fileName = StringFormat("AlphaWave_%s.log",
                                      TimeToString(TimeCurrent(), TIME_DATE));
         // FILE_COMMON 方便在 Terminal Common\Files 找到
         m_fileHandle = FileOpen(m_fileName, FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ);
         if(m_fileHandle == INVALID_HANDLE)
           {
            m_toFile = false;
            Print("AW_Logger: 無法開啟檔案 ", m_fileName, " err=", GetLastError());
            return false;
           }
         FileSeek(m_fileHandle, 0, SEEK_END);
        }

      Info("Logger", StringFormat("初始化完成 terminal=%s file=%s level=%s",
                                  m_toTerminal ? "Y" : "N",
                                  m_toFile ? m_fileName : "N",
                                  LevelText(m_minLevel)));
      return true;
     }

   void Close(void)
     {
      if(m_fileHandle != INVALID_HANDLE)
        {
         FileClose(m_fileHandle);
         m_fileHandle = INVALID_HANDLE;
        }
     }

   void SetMinLevel(const ENUM_AW_LOG_LEVEL lv) { m_minLevel = lv; }

   void Debug(const string module, const string msg) { WriteLine(AW_LOG_DEBUG, module, msg); }
   void Info (const string module, const string msg) { WriteLine(AW_LOG_INFO,  module, msg); }
   void Warn (const string module, const string msg) { WriteLine(AW_LOG_WARN,  module, msg); }
   void Error(const string module, const string msg) { WriteLine(AW_LOG_ERROR, module, msg); }

   //--- 進場 / 拒絕原因（Lite 先提供介面；Pro 再呼叫）
   void LogEntryReason(const string setupId, const string reason)
     {
      Info("Entry", StringFormat("setup=%s | reason=%s", setupId, reason));
     }

   void LogRejectReason(const string setupId, const string reason)
     {
      Info("Reject", StringFormat("setup=%s | reason=%s", setupId, reason));
     }

   void LogDailyReset(const datetime sessionDayKey)
     {
      Info("TimeManager", StringFormat("每日結構重置 sessionDayKey=%s",
                                       TimeToString(sessionDayKey, TIME_DATE|TIME_MINUTES)));
     }
  };

#endif // AW_LOGGER_MQH
//+------------------------------------------------------------------+
