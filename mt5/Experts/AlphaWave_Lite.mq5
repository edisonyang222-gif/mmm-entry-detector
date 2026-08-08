//+------------------------------------------------------------------+
//| AlphaWave_Lite.mq5                                                |
//| Alpha Wave Lite — analysis / panel / alerts ONLY                  |
//| FORBIDDEN: any order API, auto trading, auto SL/TP                |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"
#property version   "1.10"
#property description "Alpha Wave Lite — XAUUSD analysis (no auto trading)"

#include <AlphaWave/AW_All.mqh>

#define AW_EA_EDITION AW_EDITION_LITE

//+------------------------------------------------------------------+
//| Hard compile-time guard — Lite must never trade                   |
//+------------------------------------------------------------------+
#ifdef AW_LITE_ALLOW_ORDERS
#error Alpha Wave Lite must not enable order APIs
#endif

//+------------------------------------------------------------------+
input group "=== General ==="
input string            InpSymbolOverride      = "";
input ulong             InpMagicNumber         = 20260807;     // reserved (unused in Lite)
input int               InpSlippagePoints      = 30;           // reserved (unused in Lite)

input group "=== Time (UTC+8) ==="
input int               InpBrokerUtcOffsetHrs  = 2;
input int               InpTradeTzOffsetHrs    = 8;
input int               InpSessionStartHour    = 4;
input int               InpSessionStartMinute  = 45;

input group "=== Logger ==="
input ENUM_AW_LOG_LEVEL InpLogMinLevel         = AW_LOG_INFO;
input bool              InpLogToTerminal       = true;
input bool              InpLogToFile           = false;
input string            InpLogFileName         = "";
input bool              InpDebugHeartbeat      = true;
input int               InpHeartbeatSeconds    = 60;

input group "=== Module Switches ==="
input bool              InpEnableMarketStructure = true;
input bool              InpEnableSessionManager  = true;
input bool              InpEnableLiquidity       = true;
input bool              InpEnableFib             = true;
input bool              InpEnableSetupDetector   = true;
input bool              InpEnableConfirmation    = true;
input bool              InpEnableTradeScore      = true;
input bool              InpEnablePanel           = true;
input bool              InpEnableAlert           = true;
input bool              InpEnableStatistics      = true;

input group "=== Session Windows (UTC+8 minutes from midnight) ==="
input bool              InpSess_EnableAsia     = true;
input bool              InpSess_EnableLondon   = true;
input bool              InpSess_EnableNY       = true;
input int               InpSess_AsiaStartMin   = 285;   // 04:45
input int               InpSess_AsiaEndMin     = 720;   // 12:00
input int               InpSess_LondonStartMin = 900;   // 15:00
input int               InpSess_LondonEndMin   = 1260;  // 21:00
input int               InpSess_NYStartMin     = 1200;  // 20:00
input int               InpSess_NYEndMin       = 150;   // 02:30 (overnight)

input group "=== Market Structure ==="
input bool              InpMS_EnableH4         = true;
input bool              InpMS_EnableH1         = true;
input bool              InpMS_EnableM15        = true;
input int               InpMS_SwingLeft        = 2;     // swing left bars
input int               InpMS_SwingRight       = 2;     // swing right confirm bars
input int               InpMS_Lookback         = 300;

input group "=== Liquidity Sweep ==="
input double            InpLiq_PiercePoints    = 50;    // min pierce beyond level (points)
input double            InpLiq_ReclaimPoints   = 20;    // reclaim buffer (points)

input group "=== Fib Setup ==="
input double            InpFib_Tol50Points     = 150;   // 0.5 zone tolerance (points)
input int               InpFib_MinImpulsePts   = 300;   // min impulse leg (points)

input group "=== M5 Confirmation ==="
input bool              InpConf_Engulfing      = true;
input bool              InpConf_PinBar         = true;
input bool              InpConf_Rejection      = true;
input bool              InpConf_BOS            = true;
input bool              InpConf_CHoCH          = true;
input double            InpConf_PinWickBody    = 2.0;   // pin wick >= body * N
input double            InpConf_RejectWickBody = 1.5;
input int               InpConf_SwingLeft      = 2;
input int               InpConf_SwingRight     = 2;

input group "=== Trade Score Weights ==="
input int               InpW_H4                = 15;
input int               InpW_H1                = 15;
input int               InpW_M15               = 15;
input int               InpW_Sweep             = 15;
input int               InpW_Fib50             = 15;
input int               InpW_TwoLegPB          = 10;
input int               InpW_M5Conf            = 15;

input group "=== Bias Score Weights ==="
input int               InpBiasW_H4            = 20;
input int               InpBiasW_H1            = 20;
input int               InpBiasW_M15           = 20;
input int               InpBiasW_PD            = 15;
input int               InpBiasW_Asia          = 15;
input int               InpBiasW_Sweep         = 10;

input group "=== Alert ==="
input int               InpAlert_MinScore      = 70;    // alert only if score >= this
input bool              InpAlert_Popup         = true;
input bool              InpAlert_Push          = false;
input bool              InpAlert_Sound         = true;
input string            InpAlert_SoundFile     = "alert.wav";

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
CAWTradeManager         g_trade;      // present but hard-disabled
CAWStatistics           g_stats;
CAWPanel                g_panel;
CAWAlert                g_alert;

string                  g_symbol;
AWDailyContext          g_daily;
datetime                g_lastHeartbeat=0;

//+------------------------------------------------------------------+
string ResolveSymbol(void)
  {
   string s=InpSymbolOverride;
   StringTrimLeft(s);
   StringTrimRight(s);
   if(s=="") s=_Symbol;
   return s;
  }

//+------------------------------------------------------------------+
void RunDailyReset(const datetime sessionDayKey)
  {
   g_daily.sessionDayKey=sessionDayKey;
   g_daily.lastResetTime=TimeCurrent();
   g_daily.resetDone=true;

   g_structure.DailyReset(g_daily);
   g_session.DailyReset(g_daily);
   g_liquidity.DailyReset(g_daily);
   g_fib.DailyReset(g_daily);
   g_setup.DailyReset(g_daily);
   g_confirm.DailyReset(g_daily);
   g_score.DailyReset(g_daily);
   g_trade.DailyReset(g_daily);
   g_stats.DailyReset(g_daily);
   g_alert.DailyReset(g_daily);

   g_logger.Info("EA",
                 StringFormat("DailyReset @ UTC+8 %s",
                              TimeToString(sessionDayKey,TIME_DATE|TIME_MINUTES)));
  }

//+------------------------------------------------------------------+
void UpdateAnalysis(void)
  {
   if(InpEnableSessionManager)
      g_session.Update();

   if(InpEnableMarketStructure)
      g_structure.Update();

   const AWSessionLevels sess=g_session.Levels();

   if(InpEnableLiquidity)
      g_liquidity.Update(sess);

   if(InpEnableFib)
      g_fib.Update(&g_structure);

   const AWFibSetupState fib=g_fib.State();
   if(InpEnableSetupDetector)
      g_setup.UpdateFromFib(fib);

   if(InpEnableConfirmation)
      g_confirm.Update(fib.in_zone,fib.direction);

   const AWSweepState sweep=g_liquidity.State();
   const AWConfirmState conf=g_confirm.State();
   const double bid=SymbolInfoDouble(g_symbol,SYMBOL_BID);

   if(InpEnableTradeScore)
     {
      g_score.UpdateBias(g_structure.GetH4Bias(),
                         g_structure.GetH1Bias(),
                         g_structure.GetM15Bias(),
                         sess,sweep,bid);
      g_score.UpdateScore(g_structure.GetH4Bias(),
                          g_structure.GetH1Bias(),
                          g_structure.GetM15Bias(),
                          fib,sweep,conf);
     }

   // TradeManager must remain inert
   g_trade.Update();

   if(InpEnableStatistics)
      g_stats.Update();

   const AWScoreState sc=g_score.ScoreState();

   if(InpEnablePanel)
      g_panel.Render(g_symbol,
                     g_score.IntradayBias(),
                     g_structure.GetH4Bias(),
                     g_structure.GetH1Bias(),
                     g_structure.GetM15Bias(),
                     sess,fib,sweep,conf,sc);

   if(InpEnableAlert)
      g_alert.MaybeAlert(g_symbol,sc,conf,InpAlert_MinScore);
  }

//+------------------------------------------------------------------+
void MaybeHeartbeat(void)
  {
   if(!InpDebugHeartbeat) return;
   const int interval=MathMax(5,InpHeartbeatSeconds);
   const datetime now=TimeCurrent();
   if(g_lastHeartbeat!=0 && (now-g_lastHeartbeat)<interval) return;
   g_lastHeartbeat=now;

   const AWScoreState sc=g_score.ScoreState();
   g_logger.Debug("EA",
                  StringFormat("HB %s sess=%s bias=%s setup=%s score=%d conf=%s",
                               g_symbol,
                               g_session.ActiveSessionName(),
                               AW_BiasToText(g_score.IntradayBias()),
                               g_setup.Label(),
                               sc.score,
                               g_confirm.Reason()));
  }

//+------------------------------------------------------------------+
int OnInit(void)
  {
   g_symbol=ResolveSymbol();
   ZeroMemory(g_daily);

   g_logger.Init("AW-Lite",InpLogMinLevel,InpLogToTerminal,InpLogToFile,InpLogFileName);
   g_logger.Info("EA",StringFormat("Starting %s Lite on %s (NO AUTO TRADE)",
                                   AW_PRODUCT_NAME,g_symbol));

   if(StringFind(g_symbol,"XAU")<0 && StringFind(g_symbol,"GOLD")<0)
      g_logger.Warn("EA","Primary design target is XAUUSD");

   if(!g_time.Init(&g_logger,InpBrokerUtcOffsetHrs,InpTradeTzOffsetHrs,
                   InpSessionStartHour,InpSessionStartMinute))
      return INIT_FAILED;

   g_structure.Init(g_symbol,&g_logger,
                    InpMS_EnableH4,InpMS_EnableH1,InpMS_EnableM15,
                    InpMS_SwingLeft,InpMS_SwingRight,InpMS_Lookback);

   g_session.Init(g_symbol,&g_logger,&g_time,
                  InpSess_EnableAsia,InpSess_EnableLondon,InpSess_EnableNY,
                  InpSess_AsiaStartMin,InpSess_AsiaEndMin,
                  InpSess_LondonStartMin,InpSess_LondonEndMin,
                  InpSess_NYStartMin,InpSess_NYEndMin);

   g_liquidity.Init(g_symbol,&g_logger,InpEnableLiquidity,
                    InpLiq_PiercePoints,InpLiq_ReclaimPoints);

   g_fib.Init(g_symbol,&g_logger,InpEnableFib,
              InpFib_Tol50Points,InpFib_MinImpulsePts);

   g_setup.Init(&g_logger,InpEnableSetupDetector);

   g_confirm.Init(g_symbol,&g_logger,InpEnableConfirmation,
                  InpConf_Engulfing,InpConf_PinBar,InpConf_Rejection,
                  InpConf_BOS,InpConf_CHoCH,
                  InpConf_PinWickBody,InpConf_RejectWickBody,
                  InpConf_SwingLeft,InpConf_SwingRight);

   AWScoreWeights w;
   ZeroMemory(w);
   w.w_h4=InpW_H4; w.w_h1=InpW_H1; w.w_m15=InpW_M15;
   w.w_sweep=InpW_Sweep; w.w_fib50=InpW_Fib50;
   w.w_two_leg_pb=InpW_TwoLegPB; w.w_m5_conf=InpW_M5Conf;
   w.bias_h4=InpBiasW_H4; w.bias_h1=InpBiasW_H1; w.bias_m15=InpBiasW_M15;
   w.bias_pd_pos=InpBiasW_PD; w.bias_asia=InpBiasW_Asia; w.bias_sweep=InpBiasW_Sweep;

   g_score.Init(&g_logger,InpEnableTradeScore,w,InpAlert_MinScore);

   // Lite: trade manager forced OFF — never place orders
   g_trade.Init(g_symbol,&g_logger,NULL,AW_EA_EDITION,false,InpMagicNumber,InpSlippagePoints);

   g_stats.Init(&g_logger,InpEnableStatistics);
   g_alert.Init(&g_logger,InpEnableAlert,InpAlert_Popup,InpAlert_Push,
                InpAlert_Sound,InpAlert_SoundFile);

   if(InpEnablePanel)
      g_panel.Init(ChartID(),"AWLitePanel");

   datetime dayKey=0;
   if(g_time.CheckAndConsumeDailyReset(dayKey))
      RunDailyReset(dayKey);

   UpdateAnalysis();
   MaybeHeartbeat();

   g_logger.Info("EA","OnInit complete — analysis only");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_panel.Deinit();
   g_logger.Info("EA",StringFormat("OnDeinit reason=%d",reason));
   g_logger.Close();
  }

//+------------------------------------------------------------------+
void OnTick(void)
  {
   datetime dayKey=0;
   if(g_time.CheckAndConsumeDailyReset(dayKey))
      RunDailyReset(dayKey);

   UpdateAnalysis();
   MaybeHeartbeat();

   // Intentionally no order placement / no positions / no SL-TP management.
  }

//+------------------------------------------------------------------+
void OnTimer(void) {}

//+------------------------------------------------------------------+
//| Safety: reject any future trade attempt at EA layer               |
//+------------------------------------------------------------------+
bool AW_LiteBlockTrading(string &reason)
  {
   reason="Alpha Wave Lite forbids auto trading";
   g_logger.LogRejectReason("TRADE_BLOCK",reason);
   return false;
  }
//+------------------------------------------------------------------+
