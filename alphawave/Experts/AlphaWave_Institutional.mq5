//+------------------------------------------------------------------+
//| AlphaWave_Institutional.mq5                                      |
//| Alpha Wave Institutional EA                                      |
//| Builds ON TOP of Alpha Wave Pro — does not overturn Pro          |
//|                                                                  |
//| Priority: MaxDD control > Expectancy > PF > Stability > Net PnL  |
//| Forbidden: ML auto-tune, Martingale, Grid, Recovery, lot-up      |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"
#property version   "1.00"
#property strict

#include "../Pro/AW_Pro_Engine.mqh"
#include "../Institutional/AW_Inst_Engine.mqh"

//---------------------------- Inputs: Pro (untouched semantics) ----
input group "=== Alpha Wave Pro (core, do not overturn) ==="
input ENUM_TIMEFRAMES InpEntryTF = PERIOD_M15;
input ENUM_TIMEFRAMES InpHtfTF   = PERIOD_H1;
input int    InpSwingLeft        = 2;
input int    InpSwingRight       = 2;
input int    InpStructLookback   = 80;
input int    InpSweepLookback    = 20;
input double InpSweepWickMinAtr  = 0.15;
input double InpFibLow           = 0.618;
input double InpFibHigh          = 0.786;
input double InpSlAtr            = 1.5;
input double InpTp1Atr           = 2.0;
input double InpTp2Atr           = 3.5;
input bool   InpEnFibSweepEngulf = true;
input bool   InpEnFibSweepBos    = true;
input bool   InpEnFibChoch       = true;
input bool   InpEnSweepBos       = true;
input bool   InpEnSweepEngulf    = true;
input bool   InpEnFibEngulf      = true;

//---------------------------- Regime (all thresholds input) --------
input group "=== Institutional: Market Regime Detector ==="
input int    InpAtrPeriod            = 14;
input int    InpAtrMaPeriod          = 50;
input int    InpAdxPeriod            = 14;
input double InpAdxTrendMin          = 22.0;
input double InpAdxRangeMax          = 18.0;
input double InpAtrHighMult          = 1.6;
input double InpAtrLowMult           = 0.7;
input double InpSessRangeAtrHigh     = 4.0;
input double InpUnstableFlipBars     = 3;
input int    InpStructFlipLookback   = 8;

//---------------------------- Adaptive filter ----------------------
input group "=== Institutional: Adaptive Trade Filter ==="
input bool   InpTrendingAllowTrend   = true;
input bool   InpTrendingAllowRange   = false;
input bool   InpRangingAllowTrend    = false;
input bool   InpRangingAllowRange    = true;
input bool   InpHighVolAllowTrend    = true;
input bool   InpHighVolAllowRange    = false;
input bool   InpLowVolAllowAny       = false;
input bool   InpUnstableAllowAny     = false;
input double InpWTrendingTrend       = 1.10;
input double InpWTrendingRange       = 0.70;
input double InpWRangingTrend        = 0.60;
input double InpWRangingRange        = 1.00;
input double InpWHighVol             = 0.85;
input double InpWLowVol              = 0.00;
input double InpWUnstable            = 0.00;

//---------------------------- Trade Score --------------------------
input group "=== Institutional: Advanced Trade Score ==="
input int InpPtsRegime     = 20;
input int InpPtsSession    = 15;
input int InpPtsAtr        = 10;
input int InpPtsSweep      = 15;
input int InpPtsHtf        = 15;
input int InpPtsFresh      = 10;
input int InpPtsConfirm    = 15;
input int InpGradeAPlus    = 90;
input int InpGradeA        = 80;
input int InpGradeB        = 70;
input int InpGradeC        = 60;

input group "=== Institutional: Dynamic Minimum Score ==="
input int  InpMinScoreNormal       = 75;
input int  InpMinScoreHighVol      = 85;
input int  InpMinScoreLowLiq       = 90;
input bool InpBlockLowVol          = true;
input bool InpBlockUnstable        = true;

//---------------------------- Drawdown -----------------------------
input group "=== Institutional: Drawdown Protection ==="
input double InpDailyL1   = 2.0;
input double InpDailyL2   = 3.5;
input double InpDailyL3   = 5.0;
input double InpWeeklyL1  = 4.0;
input double InpWeeklyL2  = 6.0;
input double InpWeeklyL3  = 8.0;
input double InpMonthlyL1 = 8.0;
input double InpMonthlyL2 = 12.0;
input double InpMonthlyL3 = 15.0;
input double InpRiskMultL1 = 0.5;
input int    InpGmtOffsetHours = 8; // Taipei default UTC+8 for day reset

//---------------------------- Auto disable (default false) ---------
input group "=== Institutional: Auto Disable Weak Setup ==="
input bool   InpAutoDisableEnabled = false;
input int    InpAutoDisableMinSamples = 100;
input double InpAutoDisableMinPF = 1.0;
input double InpAutoDisableMinExp = 0.0;

//---------------------------- Sessions (timezone aware) ------------
input group "=== Sessions (Taipei / configurable offset) ==="
input bool InpUseSessionFilter = true;
input bool InpTradeAsia = false;
input bool InpTradeLondon = true;
input bool InpTradeNY = true;
input int  InpAsiaStartMin = 7 * 60;       // 07:00
input int  InpAsiaEndMin   = 14 * 60;      // 14:00
input int  InpLonStartMin  = 15 * 60;      // 15:00
input int  InpLonEndMin    = 15 * 60 + 30 + 8 * 60; // 23:30 = 1410
input int  InpNyStartMin   = 21 * 60 + 30; // 21:30
input int  InpNyEndMin     = 4 * 60;       // 04:00 next day
input bool InpAsiaIsLowLiq = true;
input bool InpOverlapBoost = true;

//---------------------------- Risk / execution ---------------------
input group "=== Execution / Safety ==="
input double InpRiskPercent = 0.5;   // % equity risk per trade
input long   InpMagic       = 260807;
input int    InpSlippagePts = 30;
input bool   InpAllowAutoTrading = true;
input bool   InpShowDashboard = true;

//---------------------------- Globals ------------------------------
CAWProEngine   g_pro;
CAWInstEngine  g_inst;
datetime       g_lastBarTime = 0;
ulong          g_openTicketMeta[]; // parallel open tracking for stats

struct OpenMeta
{
   ulong            ticket;
   ENUM_AW_SETUP_ID setupId;
   ENUM_AW_GRADE    grade;
   ENUM_AW_REGIME   regime;
   int              score;
   int              confirmStrength;
   string           sessionName;
   double           riskMoney;
   double           lots;
};
OpenMeta g_meta[];

//---------------------------- Session helpers ----------------------
int LocalMinutesNow()
{
   const datetime adj = TimeGMT() + InpGmtOffsetHours * 3600;
   MqlDateTime dt; TimeToStruct(adj, dt);
   return dt.hour * 60 + dt.min;
}

bool InMinuteRange(const int nowMin, const int startMin, const int endMin)
{
   if(startMin == endMin) return false;
   if(startMin < endMin) return (nowMin >= startMin && nowMin < endMin);
   // overnight wrap (e.g. 21:30-04:00)
   return (nowMin >= startMin || nowMin < endMin);
}

void ResolveSession(string &name, bool &ok, bool &lowLiq, datetime &sessStart)
{
   const int nowMin = LocalMinutesNow();
   const datetime adj = TimeGMT() + InpGmtOffsetHours * 3600;
   MqlDateTime dt; TimeToStruct(adj, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   const datetime dayStart = StructToTime(dt);

   const bool asia = InMinuteRange(nowMin, InpAsiaStartMin, InpAsiaEndMin);
   const bool lon  = InMinuteRange(nowMin, InpLonStartMin, InpLonEndMin);
   const bool ny   = InMinuteRange(nowMin, InpNyStartMin, InpNyEndMin);

   ok = !InpUseSessionFilter ||
        ((InpTradeAsia && asia) || (InpTradeLondon && lon) || (InpTradeNY && ny));

   if(lon && ny) { name = "LON+NY"; sessStart = dayStart + InpLonStartMin * 60; }
   else if(ny)   { name = "NY";     sessStart = dayStart + InpNyStartMin * 60; if(nowMin < InpNyEndMin) sessStart -= 86400; }
   else if(lon)  { name = "LONDON"; sessStart = dayStart + InpLonStartMin * 60; }
   else if(asia) { name = "ASIA";   sessStart = dayStart + InpAsiaStartMin * 60; }
   else          { name = "OFF";    sessStart = dayStart; }

   lowLiq = (asia && InpAsiaIsLowLiq && !(lon || ny));
   if(InpOverlapBoost && lon && ny) lowLiq = false;
}

//---------------------------- Init configs -------------------------
bool BuildAndInit()
{
   AWProConfig pc;
   pc.symbol = _Symbol;
   pc.entryTf = InpEntryTF;
   pc.htfTf = InpHtfTF;
   pc.swingLeft = InpSwingLeft;
   pc.swingRight = InpSwingRight;
   pc.structLookback = InpStructLookback;
   pc.sweepLookback = InpSweepLookback;
   pc.sweepWickMinAtr = InpSweepWickMinAtr;
   pc.fibLow = InpFibLow;
   pc.fibHigh = InpFibHigh;
   pc.slAtrMult = InpSlAtr;
   pc.tp1AtrMult = InpTp1Atr;
   pc.tp2AtrMult = InpTp2Atr;
   pc.enableFibSweepEngulfing = InpEnFibSweepEngulf;
   pc.enableFibSweepBos = InpEnFibSweepBos;
   pc.enableFibChoch = InpEnFibChoch;
   pc.enableSweepBos = InpEnSweepBos;
   pc.enableSweepEngulfing = InpEnSweepEngulf;
   pc.enableFibEngulfing = InpEnFibEngulf;
   if(!g_pro.Init(pc)) return false;

   AWRegimeConfig rc;
   rc.atrPeriod = InpAtrPeriod;
   rc.atrMaPeriod = InpAtrMaPeriod;
   rc.adxPeriod = InpAdxPeriod;
   rc.adxTrendMin = InpAdxTrendMin;
   rc.adxRangeMax = InpAdxRangeMax;
   rc.atrHighMult = InpAtrHighMult;
   rc.atrLowMult = InpAtrLowMult;
   rc.sessionRangeAtrHigh = InpSessRangeAtrHigh;
   rc.unstableFlipBars = InpUnstableFlipBars;
   rc.structureFlipLookback = InpStructFlipLookback;

   AWAdaptiveConfig ac;
   ac.trendingAllowTrendSetups = InpTrendingAllowTrend;
   ac.trendingAllowRangeSetups = InpTrendingAllowRange;
   ac.rangingAllowTrendSetups = InpRangingAllowTrend;
   ac.rangingAllowRangeSetups = InpRangingAllowRange;
   ac.highVolAllowTrendSetups = InpHighVolAllowTrend;
   ac.highVolAllowRangeSetups = InpHighVolAllowRange;
   ac.lowVolAllowAny = InpLowVolAllowAny;
   ac.unstableAllowAny = InpUnstableAllowAny;
   ac.weightTrendingTrend = InpWTrendingTrend;
   ac.weightTrendingRange = InpWTrendingRange;
   ac.weightRangingTrend = InpWRangingTrend;
   ac.weightRangingRange = InpWRangingRange;
   ac.weightHighVol = InpWHighVol;
   ac.weightLowVol = InpWLowVol;
   ac.weightUnstable = InpWUnstable;

   AWScoreConfig sc;
   sc.ptsRegime = InpPtsRegime; sc.ptsSession = InpPtsSession; sc.ptsAtr = InpPtsAtr;
   sc.ptsSweep = InpPtsSweep; sc.ptsHtfAlign = InpPtsHtf; sc.ptsFreshness = InpPtsFresh;
   sc.ptsConfirm = InpPtsConfirm;
   sc.gradeAPlus = InpGradeAPlus; sc.gradeA = InpGradeA; sc.gradeB = InpGradeB; sc.gradeC = InpGradeC;
   sc.minScoreNormal = InpMinScoreNormal; sc.minScoreHighVol = InpMinScoreHighVol;
   sc.minScoreLowLiquidity = InpMinScoreLowLiq;
   sc.blockLowVol = InpBlockLowVol; sc.blockUnstable = InpBlockUnstable;

   AWDrawdownConfig dc;
   dc.dailyDdLevel1Pct = InpDailyL1; dc.dailyDdLevel2Pct = InpDailyL2; dc.dailyDdLevel3Pct = InpDailyL3;
   dc.weeklyDdLevel1Pct = InpWeeklyL1; dc.weeklyDdLevel2Pct = InpWeeklyL2; dc.weeklyDdLevel3Pct = InpWeeklyL3;
   dc.monthlyDdLevel1Pct = InpMonthlyL1; dc.monthlyDdLevel2Pct = InpMonthlyL2; dc.monthlyDdLevel3Pct = InpMonthlyL3;
   dc.riskMultLevel1 = InpRiskMultL1;
   dc.gmtOffsetHours = InpGmtOffsetHours;

   AWAutoDisableConfig adc;
   adc.enabled = InpAutoDisableEnabled;
   adc.minSamples = InpAutoDisableMinSamples;
   adc.minProfitFactor = InpAutoDisableMinPF;
   adc.minExpectancy = InpAutoDisableMinExp;

   return g_inst.Init(g_pro, rc, ac, sc, dc, adc, AccountInfoDouble(ACCOUNT_EQUITY));
}

//---------------------------- Trade send ---------------------------
bool AlreadyInPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      return true; // one position — no grid/pyramid
   }
   return false;
}

bool SendDecision(const AWInstDecision &d)
{
   if(!InpAllowAutoTrading) return false;
   if(AlreadyInPosition()) return false;
   if(CAWInstSafety::ForbidMartingale() == false) return false; // sanity

   const AWDrawdownState dd = g_inst.Dd();
   const double lots = CAWInstSafety::CalcLot(_Symbol,
                         AccountInfoDouble(ACCOUNT_EQUITY),
                         InpRiskPercent, dd.riskMult,
                         d.signal.entry, d.signal.sl);
   if(!CAWInstSafety::ValidateOrderRequest(lots, g_inst.LastLossLots()))
      return false;

   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.magic = InpMagic;
   req.volume = lots;
   req.deviation = InpSlippagePts;
   req.type_filling = ORDER_FILLING_IOC;
   req.sl = d.signal.sl;
   req.tp = d.signal.tp1;
   req.comment = StringFormat("AW|%s|%s|%d", d.signal.setupName, AW_GradeName(d.score.grade), d.score.score);

   if(d.signal.direction == AW_DIR_BUY)
   {
      req.type = ORDER_TYPE_BUY;
      req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }
   else
   {
      req.type = ORDER_TYPE_SELL;
      req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }

   if(!OrderSend(req, res) || res.retcode != TRADE_RETCODE_DONE)
   {
      PrintFormat("[AW] Order failed ret=%d", res.retcode);
      return false;
   }

   OpenMeta m;
   m.ticket = res.order;
   // Prefer position ticket if available
   if(res.deal > 0)
   {
      if(HistoryDealSelect(res.deal))
         m.ticket = (ulong)HistoryDealGetInteger(res.deal, DEAL_POSITION_ID);
   }
   m.setupId = d.signal.setupId;
   m.grade = d.score.grade;
   m.regime = g_inst.Regime().regime;
   m.score = d.score.score;
   m.confirmStrength = d.signal.confirmStrength;
   string sname; bool ok, low; datetime ss;
   ResolveSession(sname, ok, low, ss);
   m.sessionName = sname;
   m.lots = lots;
   m.riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPercent / 100.0) * dd.riskMult;
   const int n = ArraySize(g_meta);
   ArrayResize(g_meta, n + 1);
   g_meta[n] = m;
   return true;
}

OpenMeta FindMetaByPosition(const ulong posId)
{
   for(int i = 0; i < ArraySize(g_meta); ++i)
      if(g_meta[i].ticket == posId) return g_meta[i];
   OpenMeta empty; ZeroMemory(empty); return empty;
}

//---------------------------- Events -------------------------------
int OnInit()
{
   if(!BuildAndInit())
   {
      Print("[AW] Init failed");
      return INIT_FAILED;
   }
   Print("[AW Institutional] Ready — Pro core preserved; Institutional gates active");
   Print("[AW Safety] Martingale/Grid/Recovery/ML-mutation/Lot-up AFTER LOSS = FORBIDDEN");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   Comment("");
}

void OnTick()
{
   string sname; bool sessOk, lowLiq; datetime sessStart;
   ResolveSession(sname, sessOk, lowLiq, sessStart);
   g_inst.SetSessionContext(sname, sessOk, lowLiq);
   g_inst.OnTickUpdate(sessStart, TimeCurrent());

   if(InpShowDashboard)
      g_inst.RenderDashboard(StringFormat("Session=%s OK=%s", sname, sessOk ? "Y" : "N"));

   // New closed bar only — prevents duplicate trades / look-ahead
   const datetime barTime = iTime(_Symbol, InpEntryTF, 1);
   if(barTime == 0 || barTime == g_lastBarTime)
      return;
   g_lastBarTime = barTime;

   if(g_inst.Dd().status == AW_STATUS_STOPPED)
      return;

   AWInstDecision decisions[];
   const int n = g_inst.Decide(decisions, 8);
   for(int i = 0; i < n; ++i)
   {
      if(decisions[i].take)
      {
         SendDecision(decisions[i]);
         break; // one trade max per bar
      }
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   const long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;

   const ulong posId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   const OpenMeta meta = FindMetaByPosition(posId);
   const double pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                    + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                    + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   AWTradeRecord rec;
   ZeroMemory(rec);
   rec.ticket = trans.deal;
   rec.openTime = 0;
   rec.closeTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   rec.direction = (HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_SELL ? AW_DIR_BUY : AW_DIR_SELL);
   // DEAL_TYPE on exit is opposite of position direction
   if(HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY)
      rec.direction = AW_DIR_SELL; // closing sell position with buy
   else
      rec.direction = AW_DIR_BUY;

   rec.setupId = meta.setupId;
   rec.grade = meta.grade;
   rec.regime = meta.regime;
   rec.score = meta.score;
   rec.confirmStrength = meta.confirmStrength;
   rec.sessionName = meta.sessionName;
   MqlDateTime dt; TimeToStruct(rec.closeTime, dt);
   // day/hour in configured TZ
   const datetime adj = rec.closeTime - (TimeCurrent() - TimeGMT()) + InpGmtOffsetHours * 3600;
   TimeToStruct(adj, dt);
   rec.dayOfWeek = dt.day_of_week;
   rec.hour = dt.hour;
   rec.riskMoney = MathMax(meta.riskMoney, 1e-6);
   rec.pnl = pnl;
   rec.rMultiple = pnl / rec.riskMoney;

   if(pnl < 0.0 && meta.lots > 0.0)
      g_inst.SetLastLossLots(meta.lots);

   g_inst.OnClosedDeal(rec);
}
