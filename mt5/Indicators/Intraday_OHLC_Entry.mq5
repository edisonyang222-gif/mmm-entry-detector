//+------------------------------------------------------------------+
//| Intraday_OHLC_Entry.mq5                                           |
//| Intraday OHLC entry signal indicator (signals only, no trading)   |
//| Copy to: MQL5/Indicators/                                         |
//| Also copy Include/OHLC/IntradayOHLCLogic.mqh -> MQL5/Include/OHLC/|
//+------------------------------------------------------------------+
#property copyright "MMM Entry Detector"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "OHLC Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2

#property indicator_label2  "OHLC Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrOrangeRed
#property indicator_width2  2

#include <OHLC/IntradayOHLCLogic.mqh>

input group "Signal"
input ENUM_OHLC_MODE InpMode             = OHLC_MODE_ALL; // Signal mode
input int            InpSessionStartHour = 0;             // Session day start hour (server)
input int            InpOrbBars          = 4;             // Opening range bars
input int            InpAtrPeriod        = 14;            // ATR period
input double         InpTouchTolAtr      = 0.05;          // Touch tolerance (ATR)
input double         InpMinBreakAtr      = 0.02;          // Min break beyond level (ATR)
input double         InpRejectBodyRatio  = 0.45;          // Rejection min body/range
input double         InpStopAtrMult      = 0.8;           // Stop ATR multiple
input double         InpMinRR            = 1.5;           // Min risk/reward
input double         InpTpRR             = 2.0;           // TP RR multiple
input bool           InpUseLevelTP       = true;          // Prefer OHLC level TP
input bool           InpOnePerDay        = true;          // One signal/day/side
input bool           InpShowBuy          = true;
input bool           InpShowSell         = true;

input group "Display"
input bool           InpDrawLevels       = true;          // Draw PDH/PDL/Open/ORB
input bool           InpDrawEntryLevels  = true;          // Draw entry/SL/TP on signal
input bool           InpShowLabels       = true;          // Label signal type

double BuyBuffer[];
double SellBuffer[];

OHLCConfig     g_cfg;
OHLCDayTracker g_tr;

int OnInit()
  {
   SetIndexBuffer(0, BuyBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SellBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME, "Intraday OHLC Entry");

   OHLC_InitConfig(g_cfg, InpMode, InpSessionStartHour, InpOrbBars,
                   InpTouchTolAtr, InpMinBreakAtr, InpRejectBodyRatio,
                   InpStopAtrMult, InpMinRR, InpTpRR, InpUseLevelTP, InpOnePerDay);
   OHLC_ResetTracker(g_tr);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "OHLC_");
  }

double CalcATR(const double &high[], const double &low[], const double &close[],
               const int endIndex, const int period)
  {
   if(endIndex - period < 0)
      return 0.0;
   double sum = 0.0;
   for(int i = endIndex - period + 1; i <= endIndex; i++)
     {
      const double tr1 = high[i] - low[i];
      const double tr2 = MathAbs(high[i] - close[i - 1]);
      const double tr3 = MathAbs(low[i] - close[i - 1]);
      sum += MathMax(tr1, MathMax(tr2, tr3));
     }
   return sum / period;
  }

void DrawRay(const string name, const double price,
             const color clr, const ENUM_LINE_STYLE style = STYLE_SOLID, const int width = 1)
  {
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetString(0, name, OBJPROP_TEXT, name);
  }

void DrawSignalPlan(const datetime t, const OHLCSignal &sig, const int idx)
  {
   if(!InpDrawEntryLevels || !sig.valid)
      return;
   const string p = StringFormat("OHLC_SIG_%d_%d_", (int)sig.side, idx);
   ObjectDelete(0, p + "E");
   ObjectDelete(0, p + "SL");
   ObjectDelete(0, p + "TP");
   ObjectDelete(0, p + "L");

   const datetime t2 = t + (datetime)PeriodSeconds() * 10;
   const color cEntry = (sig.side == OHLC_BUY) ? clrDodgerBlue : clrOrangeRed;

   ObjectCreate(0, p + "E", OBJ_TREND, 0, t, sig.entry, t2, sig.entry);
   ObjectSetInteger(0, p + "E", OBJPROP_COLOR, cEntry);
   ObjectSetInteger(0, p + "E", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, p + "E", OBJPROP_RAY_RIGHT, false);

   ObjectCreate(0, p + "SL", OBJ_TREND, 0, t, sig.stopLoss, t2, sig.stopLoss);
   ObjectSetInteger(0, p + "SL", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, p + "SL", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, p + "SL", OBJPROP_RAY_RIGHT, false);

   ObjectCreate(0, p + "TP", OBJ_TREND, 0, t, sig.takeProfit, t2, sig.takeProfit);
   ObjectSetInteger(0, p + "TP", OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, p + "TP", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, p + "TP", OBJPROP_RAY_RIGHT, false);

   if(InpShowLabels)
     {
      ObjectCreate(0, p + "L", OBJ_TEXT, 0, t, sig.entry);
      ObjectSetString(0, p + "L", OBJPROP_TEXT, OHLC_SignalTypeName(sig.type));
      ObjectSetInteger(0, p + "L", OBJPROP_COLOR, cEntry);
      ObjectSetInteger(0, p + "L", OBJPROP_ANCHOR,
                       (sig.side == OHLC_BUY) ? ANCHOR_UPPER : ANCHOR_LOWER);
     }
  }

void DrawSessionLevels(const OHLCDayLevels &lv)
  {
   if(!InpDrawLevels || !lv.valid)
      return;
   DrawRay("OHLC_PDH", lv.pdh, clrTeal, STYLE_SOLID, 1);
   DrawRay("OHLC_PDL", lv.pdl, clrTomato, STYLE_SOLID, 1);
   DrawRay("OHLC_PDC", lv.pdc, clrGray, STYLE_DOT, 1);
   DrawRay("OHLC_MID", lv.mid, clrSilver, STYLE_DASH, 1);
   DrawRay("OHLC_DO",  lv.dayOpen, clrGold, STYLE_SOLID, 2);
   if(lv.orbReady)
     {
      DrawRay("OHLC_ORH", lv.orbHigh, clrDodgerBlue, STYLE_DASHDOT, 1);
      DrawRay("OHLC_ORL", lv.orbLow,  clrOrangeRed, STYLE_DASHDOT, 1);
     }
  }

void FillLevelsFromTracker(const OHLCDayTracker &tr, OHLCDayLevels &lv)
  {
   ZeroMemory(lv);
   lv.dayKey = tr.curDayKey;
   lv.dayOpen = tr.curOpen;
   lv.orbHigh = tr.orbHigh;
   lv.orbLow = tr.orbLow;
   lv.orbReady = tr.orbReady;
   if(tr.prevReady)
     {
      lv.pdh = tr.prevHigh;
      lv.pdl = tr.prevLow;
      lv.pdo = tr.prevOpen;
      lv.pdc = tr.prevClose;
      lv.mid = 0.5 * (lv.pdh + lv.pdl);
      lv.valid = true;
     }
  }

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < InpAtrPeriod + 50)
      return 0;

   ArrayInitialize(BuyBuffer, EMPTY_VALUE);
   ArrayInitialize(SellBuffer, EMPTY_VALUE);
   ObjectsDeleteAll(0, "OHLC_");
   OHLC_ResetTracker(g_tr);

   OHLCDayLevels lastLevels;
   ZeroMemory(lastLevels);

   // index 0 = oldest; skip still-forming last bar
   for(int i = 1; i < rates_total - 1; i++)
     {
      const double atr = CalcATR(high, low, close, i, InpAtrPeriod);
      OHLCSignal sig;
      const bool hit = OHLC_EvaluateBar(g_tr, g_cfg, time[i],
                                        open[i], high[i], low[i], close[i],
                                        close[i - 1], atr, sig);

      OHLCDayLevels lv;
      FillLevelsFromTracker(g_tr, lv);
      if(lv.valid)
         lastLevels = lv;

      if(!hit || !sig.valid)
         continue;

      if(sig.side == OHLC_BUY && InpShowBuy)
        {
         BuyBuffer[i] = low[i];
         DrawSignalPlan(time[i], sig, i);
        }
      else if(sig.side == OHLC_SELL && InpShowSell)
        {
         SellBuffer[i] = high[i];
         DrawSignalPlan(time[i], sig, i);
        }
     }

   DrawSessionLevels(lastLevels);
   return rates_total;
  }
//+------------------------------------------------------------------+
