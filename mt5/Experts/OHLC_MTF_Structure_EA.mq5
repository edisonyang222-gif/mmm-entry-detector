//+------------------------------------------------------------------+
//| OHLC_MTF_Structure_EA.mq5                                         |
//| 多時框偏向 + 流動性掃除 + 回踩有效S/R 自動進場                      |
//| 複製到: MQL5/Experts/                                             |
//| 並複製 Include/OHLC/StructureLogic.mqh -> MQL5/Include/OHLC/      |
//+------------------------------------------------------------------+
#property copyright "MMM Entry Detector"
#property version   "1.10"
#property strict

#include <Trade/Trade.mqh>
#include <OHLC/StructureLogic.mqh>

input group "時框"
input ENUM_TIMEFRAMES InpHTF = PERIOD_H1;
input ENUM_TIMEFRAMES InpMTF = PERIOD_M15;
input ENUM_TIMEFRAMES InpLTF = PERIOD_CURRENT; // 進場評估用當前圖表

input group "結構參數"
input int    InpSwingLeft        = 2;
input int    InpSwingRight       = 2;
input int    InpAtrPeriod        = 14;
input int    InpSweepLookback    = 30;
input int    InpStructLookback   = 80;
input double InpSweepWickAtr     = 0.05;
input double InpZoneAtr          = 0.35;
input double InpConfirmBody      = 0.45;
input double InpStopBufAtr       = 0.15;
input double InpMinRR            = 1.5;
input double InpTpRR             = 2.0;
input bool   InpRequireHtfAlign  = true;
input bool   InpRequireSweep     = true;
input bool   InpOnePerSetup      = true;

input group "交易"
input double InpLots             = 0.10;
input int    InpMagic            = 202608072;
input int    InpSlippagePoints   = 20;
input bool   InpAllowBuy         = true;
input bool   InpAllowSell        = true;
input bool   InpOneTradeAtATime  = true;
input bool   InpTradeOnNewBar    = true;
input int    InpHistoryBars      = 400;   // 重啟時重建狀態用

StructureConfig g_cfg;
SweepMemory     g_mem;
BiasSnapshot    g_bias;
CTrade          g_trade;
datetime        g_lastBarTime = 0;
bool            g_ready = false;
ulong           g_lastSignalId = 0;

int OnInit()
  {
   Structure_InitConfig(g_cfg, InpSwingLeft, InpSwingRight, InpAtrPeriod,
                        InpSweepLookback, InpStructLookback, InpSweepWickAtr,
                        InpZoneAtr, InpConfirmBody, InpStopBufAtr, InpMinRR, InpTpRR,
                        InpRequireHtfAlign, InpRequireSweep, InpOnePerSetup);
   Structure_ResetSweepMemory(g_mem);
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_ready = false;
   g_lastSignalId = 0;
   return INIT_SUCCEEDED;
  }

bool IsNewBar()
  {
   const datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t != g_lastBarTime)
     {
      g_lastBarTime = t;
      return true;
     }
   return false;
  }

bool HasOpenPositionOrOrder()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (int)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         (int)OrderGetInteger(ORDER_MAGIC) == InpMagic)
         return true;
     }
   return false;
  }

bool CopyOldestFirst(const int count, datetime &time[], double &open[], double &high[],
                     double &low[], double &close[])
  {
   double th[], tl[], to[], tc[];
   datetime tt[];
   ArraySetAsSeries(th, true);
   ArraySetAsSeries(tl, true);
   ArraySetAsSeries(to, true);
   ArraySetAsSeries(tc, true);
   ArraySetAsSeries(tt, true);
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, count, th) < count)
      return false;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, count, tl) < count)
      return false;
   if(CopyOpen(_Symbol, PERIOD_CURRENT, 0, count, to) < count)
      return false;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, count, tc) < count)
      return false;
   if(CopyTime(_Symbol, PERIOD_CURRENT, 0, count, tt) < count)
      return false;

   ArrayResize(high, count);
   ArrayResize(low, count);
   ArrayResize(open, count);
   ArrayResize(close, count);
   ArrayResize(time, count);
   for(int i = 0; i < count; i++)
     {
      high[i] = th[count - 1 - i];
      low[i] = tl[count - 1 - i];
      open[i] = to[count - 1 - i];
      close[i] = tc[count - 1 - i];
      time[i] = tt[count - 1 - i];
     }
   return true;
  }

void RebuildState(const bool tradeLast)
  {
   Structure_ResetSweepMemory(g_mem);
   const int need = MathMax(InpHistoryBars, InpStructLookback + InpAtrPeriod + 50);
   datetime time[];
   double open[], high[], low[], close[];
   if(!CopyOldestFirst(need, time, open, high, low, close))
      return;

   Structure_BuildBias(_Symbol, InpHTF, InpMTF,
                       (InpLTF == PERIOD_CURRENT ? PERIOD_CURRENT : InpLTF),
                       g_cfg, g_bias);

   const int lastClosed = need - 2;
   StructureSignal lastHit;
   ZeroMemory(lastHit);

   for(int i = InpAtrPeriod + InpSwingLeft + InpSwingRight + 2; i <= lastClosed; i++)
     {
      StructureSignal sig;
      if(Structure_EvaluateEntry(open, high, low, close, time, i, need,
                                 g_cfg, g_bias, g_mem, sig) && sig.valid)
         lastHit = sig;
     }

   if(tradeLast && lastHit.valid && lastHit.signalId != g_lastSignalId)
     {
      // 僅在明確要求時才交易重建出的最後訊號；預設掛載不交易
     }
   if(lastHit.valid)
      g_lastSignalId = lastHit.signalId;
  }

bool PlaceTrade(const StructureSignal &sig)
  {
   if(!sig.valid)
      return false;
   if(sig.side == SIDE_BUY && !InpAllowBuy)
      return false;
   if(sig.side == SIDE_SELL && !InpAllowSell)
      return false;
   if(InpOneTradeAtATime && HasOpenPositionOrOrder())
      return false;
   if(sig.signalId == g_lastSignalId)
      return false;

   const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   const double sl = NormalizeDouble(sig.stopLoss, digits);
   const double tp = NormalizeDouble(sig.takeProfit, digits);
   const string cmt = sig.patternCN;

   bool ok = false;
   if(sig.side == SIDE_BUY)
      ok = g_trade.Buy(InpLots, _Symbol, 0.0, sl, tp, cmt);
   else
      ok = g_trade.Sell(InpLots, _Symbol, 0.0, sl, tp, cmt);

   if(ok)
     {
      g_lastSignalId = sig.signalId;
      PrintFormat("結構進場 %s %s 進場=%.5f SL=%.5f TP=%.5f RR=%.2f | %s",
                  (sig.side == SIDE_BUY ? "買入" : "賣出"),
                  sig.patternCN, sig.entry, sl, tp, sig.riskReward, sig.noteCN);
     }
   else
      PrintFormat("下單失敗: %s", g_trade.ResultRetcodeDescription());
   return ok;
  }

void OnTick()
  {
   if(InpTradeOnNewBar && !IsNewBar())
      return;

   if(!g_ready)
     {
      RebuildState(false);
      g_ready = true;
      return; // 掛載後不追單歷史最後訊號
     }

   const int need = MathMax(InpHistoryBars, InpStructLookback + InpAtrPeriod + 50);
   datetime time[];
   double open[], high[], low[], close[];
   if(!CopyOldestFirst(need, time, open, high, low, close))
      return;

   Structure_BuildBias(_Symbol, InpHTF, InpMTF,
                       (InpLTF == PERIOD_CURRENT ? PERIOD_CURRENT : InpLTF),
                       g_cfg, g_bias);

   // 重建至上一根已收盤之前，再單獨評估最新已收盤K（避免漏掉掃除記憶）
   Structure_ResetSweepMemory(g_mem);
   const int lastClosed = need - 2;
   StructureSignal liveSig;
   ZeroMemory(liveSig);

   for(int i = InpAtrPeriod + InpSwingLeft + InpSwingRight + 2; i <= lastClosed; i++)
     {
      StructureSignal sig;
      const bool hit = Structure_EvaluateEntry(open, high, low, close, time, i, need,
                                               g_cfg, g_bias, g_mem, sig);
      if(i == lastClosed && hit)
         liveSig = sig;
     }

   if(liveSig.valid)
      PlaceTrade(liveSig);
  }
//+------------------------------------------------------------------+
