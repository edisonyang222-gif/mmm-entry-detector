//+------------------------------------------------------------------+
//| MMXM_Entry_EA.mq5                                                 |
//| ICT Market Maker Model Expert Advisor (can open trades)           |
//| Copy to: MQL5/Experts/                                            |
//| Also copy Include/MMXM/MMXMLogic.mqh -> MQL5/Include/MMXM/        |
//+------------------------------------------------------------------+
#property copyright "MMM Entry Detector"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <MMXM/MMXMLogic.mqh>

input group "MMXM Detection"
input int            InpLookback        = 20;
input int            InpAtrPeriod       = 14;
input double         InpMaxRangeAtr     = 3.5;
input double         InpManipAtr        = 0.3;
input double         InpDispBodyRatio   = 0.65;
input double         InpDispAtrMult     = 0.8;
input double         InpMinRR           = 1.5;
input double         InpStopBufAtr      = 0.05;
input ENUM_MMXM_FILL InpEntryFill       = MMXM_FILL_MIDPOINT;
input bool           InpAllowBuy        = true;
input bool           InpAllowSell       = true;

input group "Trading"
input double         InpLots            = 0.10;     // Fixed lot size
input int            InpMagic           = 20260807; // Magic number
input int            InpSlippagePoints  = 20;       // Slippage (points)
input bool           InpOneTradeAtATime = true;     // Block new entries while position open
input bool           InpUseLimitEntry   = true;     // true=limit at FVG entry, false=market
input int            InpLimitExpireBars = 10;       // Cancel pending after N bars
input bool           InpTradeOnNewBar   = true;     // Evaluate only on new bar

MMXMConfig g_cfg;
MMXMState  g_buy;
MMXMState  g_sell;
CTrade     g_trade;
datetime   g_lastBarTime = 0;

int OnInit()
  {
   MMXM_InitConfig(g_cfg, InpLookback, InpAtrPeriod, InpMaxRangeAtr, InpManipAtr,
                   InpDispBodyRatio, InpDispAtrMult, InpMinRR, InpStopBufAtr, InpEntryFill);
   MMXM_ResetState(g_buy, MMXM_BUY);
   MMXM_ResetState(g_sell, MMXM_SELL);

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
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

void CancelExpiredPendings()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;

      const datetime setup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      const int barsElapsed = Bars(_Symbol, PERIOD_CURRENT, setup, TimeCurrent());
      if(barsElapsed >= InpLimitExpireBars)
         g_trade.OrderDelete(ticket);
     }
  }

double HighestHigh(const int endShift, const int count)
  {
   // shift: 0 = current forming, 1 = last closed
   double v = iHigh(_Symbol, PERIOD_CURRENT, endShift);
   for(int s = endShift; s <= endShift + count - 1; s++)
      v = MathMax(v, iHigh(_Symbol, PERIOD_CURRENT, s));
   return v;
  }

double LowestLow(const int endShift, const int count)
  {
   double v = iLow(_Symbol, PERIOD_CURRENT, endShift);
   for(int s = endShift; s <= endShift + count - 1; s++)
      v = MathMin(v, iLow(_Symbol, PERIOD_CURRENT, s));
   return v;
  }

double CalcATR(const int endShift, const int period)
  {
   double sum = 0.0;
   for(int s = endShift; s <= endShift + period - 1; s++)
     {
      const double h = iHigh(_Symbol, PERIOD_CURRENT, s);
      const double l = iLow(_Symbol, PERIOD_CURRENT, s);
      const double prevC = iClose(_Symbol, PERIOD_CURRENT, s + 1);
      const double tr = MathMax(h - l, MathMax(MathAbs(h - prevC), MathAbs(l - prevC)));
      sum += tr;
     }
   return sum / period;
  }

void RebuildHistoryState()
  {
   // Rebuild state from history so EA restarts safely.
   MMXM_ResetState(g_buy, MMXM_BUY);
   MMXM_ResetState(g_sell, MMXM_SELL);

   const int need = InpLookback + InpAtrPeriod + 50;
   const int bars = Bars(_Symbol, PERIOD_CURRENT);
   if(bars < need)
      return;

   // Walk oldest -> newest using shifts: large shift = older
   const int oldestShift = bars - 2;
   const int newestClosed = 1;
   for(int shift = oldestShift - MathMax(InpLookback, InpAtrPeriod); shift >= newestClosed; shift--)
     {
      const double atr = CalcATR(shift, InpAtrPeriod);
      if(atr <= 0.0)
         continue;
      const double rh = HighestHigh(shift, InpLookback);
      const double rl = LowestLow(shift, InpLookback);
      const int barIndex = bars - 1 - shift;

      MMXMSignal buySig, sellSig;
      MMXM_Step(g_buy, g_cfg, barIndex,
                iOpen(_Symbol, PERIOD_CURRENT, shift),
                iHigh(_Symbol, PERIOD_CURRENT, shift),
                iLow(_Symbol, PERIOD_CURRENT, shift),
                iClose(_Symbol, PERIOD_CURRENT, shift),
                iHigh(_Symbol, PERIOD_CURRENT, shift + 2),
                iLow(_Symbol, PERIOD_CURRENT, shift + 2),
                atr, rh, rl, buySig);

      MMXM_Step(g_sell, g_cfg, barIndex,
                iOpen(_Symbol, PERIOD_CURRENT, shift),
                iHigh(_Symbol, PERIOD_CURRENT, shift),
                iLow(_Symbol, PERIOD_CURRENT, shift),
                iClose(_Symbol, PERIOD_CURRENT, shift),
                iHigh(_Symbol, PERIOD_CURRENT, shift + 2),
                iLow(_Symbol, PERIOD_CURRENT, shift + 2),
                atr, rh, rl, sellSig);
     }
  }

bool PlaceTrade(const MMXMSignal &sig)
  {
   if(!sig.valid)
      return false;
   if(InpOneTradeAtATime && HasOpenPositionOrOrder())
      return false;

   const double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   const double entry = NormalizeDouble(sig.entry, digits);
   const double sl = NormalizeDouble(sig.stopLoss, digits);
   const double tp = NormalizeDouble(sig.takeProfit, digits);

   bool ok = false;
   if(sig.side == MMXM_BUY && InpAllowBuy)
     {
      if(InpUseLimitEntry)
        {
         // Buy limit below/at market
         const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(entry < ask - point)
            ok = g_trade.BuyLimit(InpLots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "MMXM MMBM");
         else
            ok = g_trade.Buy(InpLots, _Symbol, 0.0, sl, tp, "MMXM MMBM");
        }
      else
         ok = g_trade.Buy(InpLots, _Symbol, 0.0, sl, tp, "MMXM MMBM");
     }
   else if(sig.side == MMXM_SELL && InpAllowSell)
     {
      if(InpUseLimitEntry)
        {
         const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(entry > bid + point)
            ok = g_trade.SellLimit(InpLots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "MMXM MMSM");
         else
            ok = g_trade.Sell(InpLots, _Symbol, 0.0, sl, tp, "MMXM MMSM");
        }
      else
         ok = g_trade.Sell(InpLots, _Symbol, 0.0, sl, tp, "MMXM MMSM");
     }

   if(ok)
      PrintFormat("MMXM %s entry=%.5f sl=%.5f tp=%.5f rr=%.2f",
                  (sig.side == MMXM_BUY ? "BUY" : "SELL"),
                  entry, sl, tp, sig.riskReward);
   else
      PrintFormat("MMXM order failed: %s", g_trade.ResultRetcodeDescription());
   return ok;
  }

void OnTick()
  {
   CancelExpiredPendings();

   if(InpTradeOnNewBar && !IsNewBar())
      return;

   // Evaluate the just-closed bar (shift=1)
   static bool historyReady = false;
   if(!historyReady)
     {
      RebuildHistoryState();
      historyReady = true;
      // Avoid trading the historical last signal on attach; wait for next live signal.
      return;
     }

   const int shift = 1;
   const double atr = CalcATR(shift, InpAtrPeriod);
   if(atr <= 0.0)
      return;

   const double rh = HighestHigh(shift, InpLookback);
   const double rl = LowestLow(shift, InpLookback);
   const int bars = Bars(_Symbol, PERIOD_CURRENT);
   const int barIndex = bars - 1 - shift;

   MMXMSignal buySig, sellSig;
   const bool buyHit = MMXM_Step(g_buy, g_cfg, barIndex,
                                 iOpen(_Symbol, PERIOD_CURRENT, shift),
                                 iHigh(_Symbol, PERIOD_CURRENT, shift),
                                 iLow(_Symbol, PERIOD_CURRENT, shift),
                                 iClose(_Symbol, PERIOD_CURRENT, shift),
                                 iHigh(_Symbol, PERIOD_CURRENT, shift + 2),
                                 iLow(_Symbol, PERIOD_CURRENT, shift + 2),
                                 atr, rh, rl, buySig);

   const bool sellHit = MMXM_Step(g_sell, g_cfg, barIndex,
                                  iOpen(_Symbol, PERIOD_CURRENT, shift),
                                  iHigh(_Symbol, PERIOD_CURRENT, shift),
                                  iLow(_Symbol, PERIOD_CURRENT, shift),
                                  iClose(_Symbol, PERIOD_CURRENT, shift),
                                  iHigh(_Symbol, PERIOD_CURRENT, shift + 2),
                                  iLow(_Symbol, PERIOD_CURRENT, shift + 2),
                                  atr, rh, rl, sellSig);

   if(buyHit)
      PlaceTrade(buySig);
   if(sellHit)
      PlaceTrade(sellSig);
  }
//+------------------------------------------------------------------+
