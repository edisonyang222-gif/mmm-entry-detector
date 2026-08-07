#property copyright "Alpha Wave"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

// Alpha Wave Institutional — Chart Dashboard (read-only companion)
// Does NOT trade. Does NOT overturn Pro.
// Shows regime-oriented status placeholders; full logic lives in the EA.

#include <AlphaWave/Institutional/AW_Inst_Defines.mqh>

input int InpAdxPeriod = 14;
input int InpAtrPeriod = 14;
input int InpAtrMaPeriod = 50;
input double InpAdxTrendMin = 22.0;
input double InpAdxRangeMax = 18.0;
input double InpAtrHighMult = 1.6;
input double InpAtrLowMult = 0.7;
input int InpGmtOffset = 8;

int g_adx = INVALID_HANDLE;
int g_atr = INVALID_HANDLE;

int OnInit()
{
   g_adx = iADX(_Symbol, PERIOD_H1, InpAdxPeriod);
   g_atr = iATR(_Symbol, PERIOD_H1, InpAtrPeriod);
   return (g_adx != INVALID_HANDLE && g_atr != INVALID_HANDLE) ? INIT_SUCCEEDED : INIT_FAILED;
}

void OnDeinit(const int reason) { Comment(""); }

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
   double adx[], atr[];
   if(CopyBuffer(g_adx, 0, 1, 1, adx) < 1) return rates_total;
   if(CopyBuffer(g_atr, 0, 1, InpAtrMaPeriod + 1, atr) < InpAtrMaPeriod + 1) return rates_total;

   double sum = 0.0;
   for(int i = 0; i < InpAtrMaPeriod; ++i) sum += atr[i];
   const double atrMa = sum / InpAtrMaPeriod;
   const double ratio = atrMa > 0.0 ? atr[0] / atrMa : 1.0;

   string regime = "UNSTABLE";
   if(ratio >= InpAtrHighMult) regime = "HIGH VOLATILITY";
   else if(ratio <= InpAtrLowMult) regime = "LOW VOLATILITY";
   else if(adx[0] >= InpAdxTrendMin) regime = "TRENDING";
   else if(adx[0] <= InpAdxRangeMax) regime = "RANGING";

   Comment("Alpha Wave Institutional Dashboard (indicator)\n",
           "Regime: ", regime, "\n",
           "ADX: ", DoubleToString(adx[0], 1),
           "  ATR ratio: ", DoubleToString(ratio, 2), "\n",
           "Full score/DD/setup DB → use AlphaWave_Institutional EA");
   return rates_total;
}
