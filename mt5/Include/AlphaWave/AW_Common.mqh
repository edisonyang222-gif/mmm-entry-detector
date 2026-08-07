//+------------------------------------------------------------------+
//| AW_Common.mqh                                                     |
//| Alpha Wave — 共用型別 / 常數 / 版本定義                            |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_COMMON_MQH
#define AW_COMMON_MQH

#define AW_VERSION_LITE          1
#define AW_VERSION_PRO           2
#define AW_VERSION_INSTITUTIONAL 3

#define AW_PRODUCT_NAME          "Alpha Wave"
#define AW_DEFAULT_SYMBOL        "XAUUSD"

// Suppress unused-parameter warnings in scaffold stubs
#define AW_UNUSED(x) ((void)(x))

//--- 日誌等級
enum ENUM_AW_LOG_LEVEL
  {
   AW_LOG_DEBUG = 0,
   AW_LOG_INFO  = 1,
   AW_LOG_WARN  = 2,
   AW_LOG_ERROR = 3
  };

//--- 系統版本（編譯期由 EA 指定）
enum ENUM_AW_EDITION
  {
   AW_EDITION_LITE          = AW_VERSION_LITE,
   AW_EDITION_PRO           = AW_VERSION_PRO,
   AW_EDITION_INSTITUTIONAL = AW_VERSION_INSTITUTIONAL
  };

//--- 偏向（模組共用，策略細節 TODO）
enum ENUM_AW_BIAS
  {
   AW_BIAS_NEUTRAL = 0,
   AW_BIAS_BULL    = 1,
   AW_BIAS_BEAR    = -1
  };

//--- 訊號方向（模組共用，策略細節 TODO）
enum ENUM_AW_SIGNAL_DIR
  {
   AW_SIGNAL_NONE = 0,
   AW_SIGNAL_BUY  = 1,
   AW_SIGNAL_SELL = -1
  };

//--- 時框角色
enum ENUM_AW_TF_ROLE
  {
   AW_TF_H4  = 0,
   AW_TF_H1  = 1,
   AW_TF_M15 = 2,
   AW_TF_M5  = 3
  };

//--- 模組啟用開關打包（由 EA input 填入）
struct AWModuleSwitches
  {
   bool enableMarketStructure;
   bool enableSessionManager;
   bool enableLiquidityManager;
   bool enableFibManager;
   bool enableSetupDetector;
   bool enableConfirmation;
   bool enableTradeScore;
   bool enableRiskManager;     // Lite：僅分析預覽，不下單
   bool enableTradeManager;    // Lite：必須關閉實際下單
   bool enableStatistics;
  };

//--- 每日結構快照（先留欄位，策略後補）
struct AWDailyContext
  {
   datetime sessionDayKey;     // 當日 UTC+8 04:45 起點（交易時區）
   datetime lastResetTime;     // 券商伺服器時間
   bool     resetDone;
   // TODO: PDH/PDL/日開盤等結構欄位 — 待規則確認後補
  };

void AW_InitModuleSwitches(AWModuleSwitches &sw)
  {
   sw.enableMarketStructure   = true;
   sw.enableSessionManager    = true;
   sw.enableLiquidityManager  = true;
   sw.enableFibManager        = true;
   sw.enableSetupDetector     = true;
   sw.enableConfirmation      = true;
   sw.enableTradeScore        = true;
   sw.enableRiskManager       = true;  // Lite：監控用，不下單
   sw.enableTradeManager      = false; // Lite 禁止下單
   sw.enableStatistics        = true;
  }

string AW_BiasToText(const ENUM_AW_BIAS b)
  {
   if(b==AW_BIAS_BULL)
      return "BULL";
   if(b==AW_BIAS_BEAR)
      return "BEAR";
   return "NEUTRAL";
  }

string AW_SignalDirToText(const ENUM_AW_SIGNAL_DIR d)
  {
   if(d==AW_SIGNAL_BUY)
      return "BUY";
   if(d==AW_SIGNAL_SELL)
      return "SELL";
   return "NONE";
  }

string AW_EditionToText(const ENUM_AW_EDITION e)
  {
   if(e==AW_EDITION_PRO)
      return "Pro";
   if(e==AW_EDITION_INSTITUTIONAL)
      return "Institutional";
   return "Lite";
  }

#endif // AW_COMMON_MQH
//+------------------------------------------------------------------+
