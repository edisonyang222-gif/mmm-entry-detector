//+------------------------------------------------------------------+
//| AlphaWave_Lite.mq5                                                |
//| Alpha Wave Lite — analysis / hints / scoring scaffold             |
//| NO entry strategy. NO auto trading.                               |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"
#property version   "1.00"
#property description "Alpha Wave Lite — modular scaffold (analysis only)"

// Include path expects MT5 tree:
//   MQL5/Experts/AlphaWave_Lite.mq5
//   MQL5/Include/AlphaWave/*.mqh
// In this repo files live under mt5/Experts and mt5/Include.
#include <AlphaWave/AW_All.mqh>

//+------------------------------------------------------------------+
//| Compile-time edition lock                                         |
//+------------------------------------------------------------------+
#define AW_EA_EDITION AW_EDITION_LITE

//+------------------------------------------------------------------+
//| Inputs — General                                                  |
//+------------------------------------------------------------------+
input group "=== General ==="
input string            InpSymbolOverride      = "";           // Leave empty = chart symbol (prefer XAUUSD)
input int               InpMagicNumber         = 20260807;     // Magic (reserved for Pro+)
input int               InpSlippagePoints      = 30;           // Slippage points (reserved)

//+------------------------------------------------------------------+
//| Inputs — Time / Session day                                       |
//+------------------------------------------------------------------+
input group "=== Time (UTC+8 session day) ==="
input int               InpBrokerUtcOffsetHrs  = 2;            // Broker server UTC offset (hours)
input int               InpTradeTzOffsetHrs    = 8;            // Trade timezone offset (UTC+8)
input int               InpSessionStartHour    = 4;            // Daily structure start hour (UTC+8)
input int               InpSessionStartMinute  = 45;           // Daily structure start minute (UTC+8)

//+------------------------------------------------------------------+
//| Inputs — Logger                                                   |
//+------------------------------------------------------------------+
input group "=== Logger ==="
input ENUM_AW_LOG_LEVEL InpLogMinLevel         = AW_LOG_DEBUG; // Minimum log level
input bool              InpLogToTerminal       = true;         // Print to Experts journal
input bool              InpLogToFile           = false;        // Also write Common\\Files log
input string            InpLogFileName         = "";           // Empty = auto AlphaWave_YYYY.MM.DD.log
input bool              InpDebugHeartbeat      = true;         // Periodic debug heartbeat
input int               InpHeartbeatSeconds    = 60;           // Heartbeat interval (seconds)

//+------------------------------------------------------------------+
//| Inputs — Module switches                                          |
//+------------------------------------------------------------------+
input group "=== Module Switches ==="
input bool              InpEnableMarketStructure = true;
input bool              InpEnableSessionManager  = true;
input bool              InpEnableLiquidity       = true;
input bool              InpEnableFib             = true;
input bool              InpEnableSetupDetector   = true;
input bool              InpEnableConfirmation    = true;
input bool              InpEnableTradeScore      = true;
input bool              InpEnableRiskManager     = true;       // Monitor only in Lite
input bool              InpEnableTradeManager    = false;      // Lite: forced OFF
input bool              InpEnableStatistics      = true;

//+------------------------------------------------------------------+
//| Inputs — Market Structure                                         |
//+------------------------------------------------------------------+
input group "=== Market Structure ==="
input bool              InpMS_EnableH4         = true;         // Use H4 bias
input bool              InpMS_EnableH1         = true;         // Use H1 bias
input bool              InpMS_EnableM15        = true;         // Use M15 structure

//+------------------------------------------------------------------+
//| Inputs — Session windows (UTC+8 minutes from midnight)            |
//+------------------------------------------------------------------+
input group "=== Session Windows (UTC+8 minutes) ==="
input bool              InpSess_EnableAsia     = true;
input bool              InpSess_EnableLondon   = true;
input bool              InpSess_EnableNY       = true;
input int               InpSess_AsiaStartMin   = 0;            // 00:00
input int               InpSess_AsiaEndMin     = 480;          // 08:00
input int               InpSess_LondonStartMin = 480;          // 08:00
input int               InpSess_LondonEndMin   = 960;          // 16:00
input int               InpSess_NYStartMin     = 780;          // 13:00
input int               InpSess_NYEndMin       = 1320;         // 22:00

//+------------------------------------------------------------------+
//| Inputs — Liquidity / Fib / Setup / Score (scaffold)               |
//+------------------------------------------------------------------+
input group "=== Liquidity ==="
input int               InpLiq_LookbackBars    = 50;

input group "=== Setup Detector (placeholders) ==="
input bool              InpSetup_EnableA       = true;         // TODO setup A
input bool              InpSetup_EnableB       = true;         // TODO setup B
input bool              InpSetup_EnableC       = false;        // TODO setup C

input group "=== Trade Score ==="
input int               InpScore_MinHint       = 60;           // Lite hint threshold
input int               InpScore_MinTrade      = 70;           // Reserved for Pro+

//+------------------------------------------------------------------+
//| Inputs — Risk (monitor only in Lite)                              |
//+------------------------------------------------------------------+
input group "=== Risk (monitor only in Lite) ==="
input double            InpRisk_PercentPerTrade = 0.5;         // % equity per trade (Pro+)
input double            InpRisk_MaxDailyLossPct = 2.0;         // Max daily loss %
input double            InpRisk_MaxDrawdownPct  = 5.0;         // Max account DD %
input int               InpRisk_MaxOpenTrades   = 1;           // Max concurrent trades

//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
CAWLogger               g_logger;
CAWTimeManager          g_time;
CAWMarketStructure      g_structure;
CAWSessionManager       g_session;
CAWLiquidityManager     g_liquidity;
CAWFibManager           g_fib;
CAWSetupDetector        g_setup;
CAWConfirmationManager  g_confirm;
CAWTradeScore           g_score;
CAWRiskManager          g_risk;
CAWTradeManager         g_trade;
CAWStatistics           g_stats;

string                  g_symbol;
AWDailyContext          g_daily;
datetime                g_lastHeartbeat = 0;

//+------------------------------------------------------------------+
string ResolveSymbol(void)
  {
   string s = InpSymbolOverride;
   StringTrimLeft(s);
   StringTrimRight(s);
   if(s=="")
      s = _Symbol;
   return s;
  }

//+------------------------------------------------------------------+
void RunDailyReset(const datetime sessionDayKey)
  {
   g_daily.sessionDayKey = sessionDayKey;
   g_daily.lastResetTime = TimeCurrent();
   g_daily.resetDone     = true;

   g_structure.DailyReset(g_daily);
   g_session.DailyReset(g_daily);
   g_liquidity.DailyReset(g_daily);
   g_fib.DailyReset(g_daily);
   g_setup.DailyReset(g_daily);
   g_confirm.DailyReset(g_daily);
   g_score.DailyReset(g_daily);
   g_risk.DailyReset(g_daily);
   g_trade.DailyReset(g_daily);
   g_stats.DailyReset(g_daily);

   g_logger.Info("EA",
                 StringFormat("DailyReset applied sessionDayKey=%s tradeTzNow=%s",
                              TimeToString(sessionDayKey,TIME_DATE|TIME_MINUTES),
                              TimeToString(g_time.NowTradeTz(),TIME_DATE|TIME_SECONDS)));
  }

//+------------------------------------------------------------------+
void UpdateModules(void)
  {
   if(InpEnableMarketStructure)
      g_structure.Update();
   if(InpEnableSessionManager)
      g_session.Update();
   if(InpEnableLiquidity)
      g_liquidity.Update();
   if(InpEnableFib)
      g_fib.Update();
   if(InpEnableSetupDetector)
      g_setup.Update();
   if(InpEnableConfirmation)
      g_confirm.Update();
   if(InpEnableTradeScore)
      g_score.Update();
   if(InpEnableRiskManager)
      g_risk.Update();
   // TradeManager stays inert in Lite even if switch is true.
   g_trade.Update();
   if(InpEnableStatistics)
      g_stats.Update();
  }

//+------------------------------------------------------------------+
void MaybeHeartbeat(void)
  {
   if(!InpDebugHeartbeat)
      return;
   const int interval = MathMax(5,InpHeartbeatSeconds);
   const datetime now = TimeCurrent();
   if(g_lastHeartbeat!=0 && (now-g_lastHeartbeat)<interval)
      return;
   g_lastHeartbeat = now;

   g_logger.Debug("EA",
                  StringFormat("HB symbol=%s sess=%s tradeTz=%s dayKey=%s H4=%s H1=%s M15=%s score=%d kill=%s stats={%s}",
                               g_symbol,
                               g_session.ActiveSession(),
                               TimeToString(g_time.NowTradeTz(),TIME_DATE|TIME_SECONDS),
                               TimeToString(g_daily.sessionDayKey,TIME_DATE|TIME_MINUTES),
                               AW_BiasToText(g_structure.GetH4Bias()),
                               AW_BiasToText(g_structure.GetH1Bias()),
                               AW_BiasToText(g_structure.GetM15Bias()),
                               g_score.LastScore(),
                               (g_risk.KillSwitchArmed() ? g_risk.KillReason() : "OFF"),
                               g_stats.Snapshot()));
  }

//+------------------------------------------------------------------+
int OnInit(void)
  {
   g_symbol = ResolveSymbol();
   ZeroMemory(g_daily);

   if(!g_logger.Init("AW-Lite",InpLogMinLevel,InpLogToTerminal,InpLogToFile,InpLogFileName))
     {
      // File open may fail; terminal logging can still work if Init partially succeeded.
      Print("AlphaWave_Lite: Logger Init warning (file may be unavailable)");
     }

   g_logger.Info("EA",
                 StringFormat("Starting %s Lite on %s | edition=%s",
                              AW_PRODUCT_NAME,g_symbol,AW_EditionToText(AW_EA_EDITION)));

   if(StringFind(g_symbol,"XAU")<0 && StringFind(g_symbol,"GOLD")<0)
      g_logger.Warn("EA","Symbol is not XAU/GOLD — system is designed primarily for XAUUSD");

   if(!g_time.Init(&g_logger,
                   InpBrokerUtcOffsetHrs,
                   InpTradeTzOffsetHrs,
                   InpSessionStartHour,
                   InpSessionStartMinute))
     {
      g_logger.Error("EA","TimeManager Init failed");
      return INIT_FAILED;
     }

   g_structure.Init(g_symbol,&g_logger,&g_time,
                    InpMS_EnableH4,InpMS_EnableH1,InpMS_EnableM15);

   g_session.Init(&g_logger,&g_time,
                  InpSess_EnableAsia,InpSess_EnableLondon,InpSess_EnableNY,
                  InpSess_AsiaStartMin,InpSess_AsiaEndMin,
                  InpSess_LondonStartMin,InpSess_LondonEndMin,
                  InpSess_NYStartMin,InpSess_NYEndMin);

   g_liquidity.Init(g_symbol,&g_logger,InpEnableLiquidity,InpLiq_LookbackBars);
   g_fib.Init(g_symbol,&g_logger,InpEnableFib);
   g_setup.Init(g_symbol,&g_logger,InpEnableSetupDetector,
                InpSetup_EnableA,InpSetup_EnableB,InpSetup_EnableC);
   g_confirm.Init(g_symbol,&g_logger,InpEnableConfirmation);
   g_score.Init(&g_logger,InpEnableTradeScore,InpScore_MinHint,InpScore_MinTrade);
   g_risk.Init(&g_logger,InpEnableRiskManager,
               InpRisk_PercentPerTrade,InpRisk_MaxDailyLossPct,
               InpRisk_MaxDrawdownPct,InpRisk_MaxOpenTrades);

   // Lite hard-lock: auto trade always false regardless of input.
   const bool want_trade = false;
   if(InpEnableTradeManager)
      g_logger.Warn("EA","InpEnableTradeManager=true ignored in Lite edition");

   g_trade.Init(g_symbol,&g_logger,&g_risk,AW_EA_EDITION,want_trade,
                (ulong)InpMagicNumber,InpSlippagePoints);
   g_stats.Init(&g_logger,InpEnableStatistics);

   // First-load daily reset
   datetime dayKey = 0;
   if(g_time.CheckAndConsumeDailyReset(dayKey))
      RunDailyReset(dayKey);

   UpdateModules();
   MaybeHeartbeat();

   g_logger.Info("EA","OnInit complete — analysis scaffold ready (no strategy / no trading)");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_logger.Info("EA",StringFormat("OnDeinit reason=%d stats={%s}",reason,g_stats.Snapshot()));
   g_logger.Close();
  }

//+------------------------------------------------------------------+
void OnTick(void)
  {
   // Keep OnTick thin: time reset → module updates → debug heartbeat.
   datetime dayKey = 0;
   if(g_time.CheckAndConsumeDailyReset(dayKey))
      RunDailyReset(dayKey);

   UpdateModules();
   MaybeHeartbeat();

   // Intentionally no entry strategy and no order placement in Lite scaffold.
  }

//+------------------------------------------------------------------+
