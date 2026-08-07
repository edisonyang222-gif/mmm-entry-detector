//+------------------------------------------------------------------+
//| MMXM_Entry_Detector.mq5                                           |
//| ICT Market Maker Model indicator (signals only, no trading)       |
//| Copy to: MQL5/Indicators/                                         |
//| Also copy Include/MMXM/MMXMLogic.mqh -> MQL5/Include/MMXM/        |
//+------------------------------------------------------------------+
#property copyright "MMM Entry Detector"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "MMBM"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrTeal
#property indicator_width1  2

#property indicator_label2  "MMSM"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrTomato
#property indicator_width2  2

#include <MMXM/MMXMLogic.mqh>

input int            InpLookback        = 20;                 // Accumulation lookback
input int            InpAtrPeriod       = 14;                 // ATR period
input double         InpMaxRangeAtr     = 3.5;                // Max range ATR mult
input double         InpManipAtr        = 0.3;                // Manipulation ATR mult
input double         InpDispBodyRatio   = 0.65;               // Displacement body ratio
input double         InpDispAtrMult     = 0.8;                // Displacement ATR mult
input double         InpMinRR           = 1.5;                // Min risk/reward
input double         InpStopBufAtr      = 0.05;               // Stop buffer ATR mult
input ENUM_MMXM_FILL InpEntryFill       = MMXM_FILL_MIDPOINT; // Entry fill
input bool           InpShowBuy         = true;               // Show buy model
input bool           InpShowSell        = true;               // Show sell model
input bool           InpDrawLevels      = true;               // Draw entry/SL/TP

double BuyBuffer[];
double SellBuffer[];

MMXMConfig g_cfg;
MMXMState  g_buy;
MMXMState  g_sell;

int OnInit()
  {
   SetIndexBuffer(0, BuyBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SellBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME, "MMXM Entry Detector");

   MMXM_InitConfig(g_cfg, InpLookback, InpAtrPeriod, InpMaxRangeAtr, InpManipAtr,
                   InpDispBodyRatio, InpDispAtrMult, InpMinRR, InpStopBufAtr, InpEntryFill);
   MMXM_ResetState(g_buy, MMXM_BUY);
   MMXM_ResetState(g_sell, MMXM_SELL);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "MMXM_");
  }

double HighestHigh(const double &high[], const int endIndex, const int count)
  {
   // endIndex inclusive, OnCalculate style: 0 = oldest
   double v = high[endIndex - count + 1];
   for(int i = endIndex - count + 1; i <= endIndex; i++)
      v = MathMax(v, high[i]);
   return v;
  }

double LowestLow(const double &low[], const int endIndex, const int count)
  {
   double v = low[endIndex - count + 1];
   for(int i = endIndex - count + 1; i <= endIndex; i++)
      v = MathMin(v, low[i]);
   return v;
  }

double CalcATR(const double &high[], const double &low[], const double &close[],
               const int endIndex, const int period)
  {
   // Simple ATR ending at endIndex (needs endIndex-period previous close)
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

void DrawLevels(const datetime t, const MMXMSignal &sig, const int idx)
  {
   if(!InpDrawLevels || !sig.valid)
      return;
   const string p = StringFormat("MMXM_%d_%d_", (int)sig.side, idx);
   const color cEntry = (sig.side == MMXM_BUY) ? clrTeal : clrTomato;
   ObjectDelete(0, p + "E");
   ObjectDelete(0, p + "SL");
   ObjectDelete(0, p + "TP");

   const datetime t2 = t + (datetime)PeriodSeconds() * 8;
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
   // OnCalculate arrays: index 0 = oldest bar
   if(rates_total < InpLookback + InpAtrPeriod + 5)
      return 0;

   ArrayInitialize(BuyBuffer, EMPTY_VALUE);
   ArrayInitialize(SellBuffer, EMPTY_VALUE);
   ObjectsDeleteAll(0, "MMXM_");
   MMXM_ResetState(g_buy, MMXM_BUY);
   MMXM_ResetState(g_sell, MMXM_SELL);

   const int start = MathMax(InpLookback, InpAtrPeriod);
   // Skip the still-forming last bar (rates_total-1)
   for(int i = start; i < rates_total - 1; i++)
     {
      const double atr = CalcATR(high, low, close, i, InpAtrPeriod);
      if(atr <= 0.0)
         continue;

      const double rh = HighestHigh(high, i, InpLookback);
      const double rl = LowestLow(low, i, InpLookback);

      MMXMSignal buySig, sellSig;
      if(InpShowBuy && i >= 2)
        {
         if(MMXM_Step(g_buy, g_cfg, i,
                      open[i], high[i], low[i], close[i],
                      high[i - 2], low[i - 2],
                      atr, rh, rl, buySig))
           {
            BuyBuffer[i] = low[i];
            DrawLevels(time[i], buySig, i);
           }
        }
      if(InpShowSell && i >= 2)
        {
         if(MMXM_Step(g_sell, g_cfg, i,
                      open[i], high[i], low[i], close[i],
                      high[i - 2], low[i - 2],
                      atr, rh, rl, sellSig))
           {
            SellBuffer[i] = high[i];
            DrawLevels(time[i], sellSig, i);
           }
        }
     }
   return rates_total;
  }
//+------------------------------------------------------------------+
