//+------------------------------------------------------------------+
//| Intraday_OHLC_EA.mq5                                              |
//| Intraday OHLC entry Expert Advisor (can open trades)              |
//| Copy to: MQL5/Experts/                                            |
//| Also copy Include/OHLC/IntradayOHLCLogic.mqh -> MQL5/Include/OHLC/|
//+------------------------------------------------------------------+
#property copyright "MMM Entry Detector"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <OHLC/IntradayOHLCLogic.mqh>

input group "OHLC Detection"
input ENUM_OHLC_MODE InpMode             = OHLC_MODE_ALL;
input int            InpSessionStartHour = 0;       // Session day start hour (server)
input int            InpOrbBars          = 4;       // Opening range bars
input int            InpAtrPeriod        = 14;
input double         InpTouchTolAtr      = 0.05;
input double         InpMinBreakAtr      = 0.02;
input double         InpRejectBodyRatio  = 0.45;
input double         InpStopAtrMult      = 0.8;
input double         InpMinRR            = 1.5;
input double         InpTpRR             = 2.0;
input bool           InpUseLevelTP       = true;
input bool           InpOnePerDay        = true;
input bool           InpAllowBuy         = true;
input bool           InpAllowSell        = true;

input group "Session filter (server hour)"
input bool           InpUseHourFilter    = false;
input int            InpTradeStartHour   = 8;       // Inclusive
input int            InpTradeEndHour     = 20;      // Exclusive

input group "Trading"
input double         InpLots             = 0.10;
input int            InpMagic            = 202608071;
input int            InpSlippagePoints   = 20;
input bool           InpOneTradeAtATime  = true;
input bool           InpMarketEntry      = true;    // true=market, false=stop pending at close
input int            InpPendingExpireBars= 6;
input bool           InpTradeOnNewBar    = true;
input bool           InpCloseAtSessionEnd= false;   // Flat before next session day

OHLCConfig     g_cfg;
OHLCDayTracker g_tr;
CTrade         g_trade;
datetime       g_lastBarTime = 0;
bool           g_historyReady = false;

int OnInit()
  {
   OHLC_InitConfig(g_cfg, InpMode, InpSessionStartHour, InpOrbBars,
                   InpTouchTolAtr, InpMinBreakAtr, InpRejectBodyRatio,
                   InpStopAtrMult, InpMinRR, InpTpRR, InpUseLevelTP, InpOnePerDay);
   OHLC_ResetTracker(g_tr);
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_historyReady = false;
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

bool InTradeWindow()
  {
   if(!InpUseHourFilter)
      return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpTradeStartHour < InpTradeEndHour)
      return (dt.hour >= InpTradeStartHour && dt.hour < InpTradeEndHour);
   // overnight window e.g. 22 -> 6
   return (dt.hour >= InpTradeStartHour || dt.hour < InpTradeEndHour);
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
      if(barsElapsed >= InpPendingExpireBars)
         g_trade.OrderDelete(ticket);
     }
  }

void CloseAllManaged()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      g_trade.PositionClose(ticket);
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      g_trade.OrderDelete(ticket);
     }
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
   OHLC_ResetTracker(g_tr);
   const int need = InpAtrPeriod + 100;
   const int bars = Bars(_Symbol, PERIOD_CURRENT);
   if(bars < need)
      return;

   // Walk oldest -> newest closed bar (shift large = older)
   const int oldestShift = bars - 2;
   for(int shift = oldestShift; shift >= 1; shift--)
     {
      const double atr = CalcATR(shift, InpAtrPeriod);
      OHLCSignal sig;
      OHLC_EvaluateBar(g_tr, g_cfg,
                       iTime(_Symbol, PERIOD_CURRENT, shift),
                       iOpen(_Symbol, PERIOD_CURRENT, shift),
                       iHigh(_Symbol, PERIOD_CURRENT, shift),
                       iLow(_Symbol, PERIOD_CURRENT, shift),
                       iClose(_Symbol, PERIOD_CURRENT, shift),
                       iClose(_Symbol, PERIOD_CURRENT, shift + 1),
                       atr, sig);
     }
  }

bool PlaceTrade(const OHLCSignal &sig)
  {
   if(!sig.valid)
      return false;
   if(sig.side == OHLC_BUY && !InpAllowBuy)
      return false;
   if(sig.side == OHLC_SELL && !InpAllowSell)
      return false;
   if(InpOneTradeAtATime && HasOpenPositionOrOrder())
      return false;

   const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   const double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double entry = NormalizeDouble(sig.entry, digits);
   const double sl = NormalizeDouble(sig.stopLoss, digits);
   const double tp = NormalizeDouble(sig.takeProfit, digits);
   const string cmt = "OHLC " + OHLC_SignalTypeName(sig.type);

   bool ok = false;
   if(sig.side == OHLC_BUY)
     {
      if(InpMarketEntry)
         ok = g_trade.Buy(InpLots, _Symbol, 0.0, sl, tp, cmt);
      else
        {
         const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(entry > ask + point)
            ok = g_trade.BuyStop(InpLots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
         else
            ok = g_trade.Buy(InpLots, _Symbol, 0.0, sl, tp, cmt);
        }
     }
   else
     {
      if(InpMarketEntry)
         ok = g_trade.Sell(InpLots, _Symbol, 0.0, sl, tp, cmt);
      else
        {
         const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(entry < bid - point)
            ok = g_trade.SellStop(InpLots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
         else
            ok = g_trade.Sell(InpLots, _Symbol, 0.0, sl, tp, cmt);
        }
     }

   if(ok)
      PrintFormat("OHLC %s %s entry=%.5f sl=%.5f tp=%.5f rr=%.2f",
                  (sig.side == OHLC_BUY ? "BUY" : "SELL"),
                  OHLC_SignalTypeName(sig.type),
                  entry, sl, tp, sig.riskReward);
   else
      PrintFormat("OHLC order failed: %s", g_trade.ResultRetcodeDescription());
   return ok;
  }

void OnTick()
  {
   CancelExpiredPendings();

   if(InpTradeOnNewBar && !IsNewBar())
      return;

   if(!g_historyReady)
     {
      RebuildHistoryState();
      g_historyReady = true;
      // Do not trade the historical last signal on attach
      return;
     }

   // Optional flatten near session rollover
   if(InpCloseAtSessionEnd)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.hour == ((InpSessionStartHour + 23) % 24) && dt.min >= 50)
         CloseAllManaged();
     }

   if(!InTradeWindow())
      return;

   const int shift = 1; // just-closed bar
   const double atr = CalcATR(shift, InpAtrPeriod);
   OHLCSignal sig;
   const bool hit = OHLC_EvaluateBar(g_tr, g_cfg,
                                     iTime(_Symbol, PERIOD_CURRENT, shift),
                                     iOpen(_Symbol, PERIOD_CURRENT, shift),
                                     iHigh(_Symbol, PERIOD_CURRENT, shift),
                                     iLow(_Symbol, PERIOD_CURRENT, shift),
                                     iClose(_Symbol, PERIOD_CURRENT, shift),
                                     iClose(_Symbol, PERIOD_CURRENT, shift + 1),
                                     atr, sig);
   if(hit)
      PlaceTrade(sig);
  }
//+------------------------------------------------------------------+
