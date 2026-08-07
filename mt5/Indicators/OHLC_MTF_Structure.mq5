//+------------------------------------------------------------------+
//| OHLC_MTF_Structure.mq5                                            |
//| 多時框結構面版 + 流動性掃除 + 回踩有效S/R 進場（收K確認、訊號不消失）|
//| 複製到: MQL5/Indicators/                                          |
//| 並複製 Include/OHLC/StructureLogic.mqh -> MQL5/Include/OHLC/      |
//+------------------------------------------------------------------+
#property copyright "MMM Entry Detector"
#property version   "1.10"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "買入回踩"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDodgerBlue
#property indicator_width1  3

#property indicator_label2  "賣出回踩"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrOrangeRed
#property indicator_width2  3

#include <OHLC/StructureLogic.mqh>

input group "時框"
input ENUM_TIMEFRAMES InpHTF = PERIOD_H1;   // 高週期（趨勢）
input ENUM_TIMEFRAMES InpMTF = PERIOD_M15;  // 中週期（結構）
input ENUM_TIMEFRAMES InpLTF = PERIOD_M5;   // 低週期（進場參照）

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
input bool   InpRequireHtfAlign  = true;   // 須符合高週期偏向
input bool   InpRequireSweep     = true;   // 須先掃除流動性
input bool   InpOnePerSetup      = true;

input group "顯示"
input bool   InpShowPanel        = true;
input bool   InpShowSRLines      = true;
input bool   InpShowSweepMarks   = true;
input bool   InpShowEntryPlan    = true;
input int    InpPanelX           = 12;
input int    InpPanelY           = 24;
input int    InpPanelFontSize    = 11;

double BuyBuffer[];
double SellBuffer[];

StructureConfig g_cfg;
SweepMemory     g_mem;
BiasSnapshot    g_bias;

string TFNameCN(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "日線";
      case PERIOD_W1:  return "週線";
      default:         return EnumToString(tf);
     }
  }

int OnInit()
  {
   SetIndexBuffer(0, BuyBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SellBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME, "OHLC多時框結構進場");

   Structure_InitConfig(g_cfg, InpSwingLeft, InpSwingRight, InpAtrPeriod,
                        InpSweepLookback, InpStructLookback, InpSweepWickAtr,
                        InpZoneAtr, InpConfirmBody, InpStopBufAtr, InpMinRR, InpTpRR,
                        InpRequireHtfAlign, InpRequireSweep, InpOnePerSetup);
   Structure_ResetSweepMemory(g_mem);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "OHLCST_");
  }

void PanelSet(const string name, const int x, const int y, const string text,
              const color clr, const int fontSize)
  {
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

void DrawPanelBG(const int w, const int h)
  {
   const string n = "OHLCST_PANEL_BG";
   if(!ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0))
     {
      // exists
     }
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, InpPanelX - 8);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, InpPanelY - 8);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clrDimGray);
   ObjectSetInteger(0, n, OBJPROP_BACK, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
  }

color BiasColor(const ENUM_BIAS b)
  {
   if(b == BIAS_BULL)
      return clrLime;
   if(b == BIAS_BEAR)
      return clrTomato;
   return clrSilver;
  }

void UpdatePanel(const BiasSnapshot &bias, const LiquidityState &liqLive,
                 const ValidSR &sr, const StructureSignal &lastSig,
                 const bool setupBuyArmed, const bool setupSellArmed)
  {
   if(!InpShowPanel)
      return;

   const int fs = InpPanelFontSize;
   const int x = InpPanelX;
   int y = InpPanelY;
   const int line = fs + 6;
   DrawPanelBG(320, 16 * line + 20);

   PanelSet("OHLCST_T0", x, y, "══ 多時框結構面版 ══", clrGold, fs + 1);
   y += line;
   PanelSet("OHLCST_T1", x, y, TFNameCN(InpHTF) + " 高週期：" + bias.htfText, BiasColor(bias.htf), fs);
   y += line;
   PanelSet("OHLCST_T2", x, y, TFNameCN(InpMTF) + " 中週期：" + bias.mtfText, BiasColor(bias.mtf), fs);
   y += line;
   PanelSet("OHLCST_T3", x, y, TFNameCN(InpLTF) + " 低週期：" + bias.ltfText, BiasColor(bias.ltf), fs);
   y += line;
   PanelSet("OHLCST_T4", x, y, "綜合偏向：" + bias.consensusText, BiasColor(bias.consensus), fs + 1);
   y += line;
   PanelSet("OHLCST_T5", x, y, bias.reasonText, clrWhite, fs - 1);
   y += line;
   PanelSet("OHLCST_T6", x, y, "──────────────", clrDimGray, fs);
   y += line;

   string liqTxt = "流動性：";
   color liqClr = clrSilver;
   if(liqLive.sweptLow || g_mem.hasLowSweep)
     {
      liqTxt += "已掃除下方 ✓";
      liqClr = clrDodgerBlue;
     }
   else if(liqLive.sweptHigh || g_mem.hasHighSweep)
     {
      liqTxt += "已掃除上方 ✓";
      liqClr = clrOrangeRed;
     }
   else
      liqTxt += "尚未掃除";
   PanelSet("OHLCST_T7", x, y, liqTxt, liqClr, fs);
   y += line;

   string supTxt = "有效支撐：";
   if(sr.hasSupport)
      supTxt += DoubleToString(sr.support, _Digits) + "（" + sr.supportNote + "）";
   else
      supTxt += "無";
   PanelSet("OHLCST_T8", x, y, supTxt, sr.hasSupport ? clrDodgerBlue : clrSilver, fs);
   y += line;

   string resTxt = "有效阻力：";
   if(sr.hasResist)
      resTxt += DoubleToString(sr.resist, _Digits) + "（" + sr.resistNote + "）";
   else
      resTxt += "無";
   PanelSet("OHLCST_T9", x, y, resTxt, sr.hasResist ? clrOrangeRed : clrSilver, fs);
   y += line;

   PanelSet("OHLCST_T10", x, y, "──────────────", clrDimGray, fs);
   y += line;

   string arm = "設置狀態：";
   if(setupBuyArmed && g_mem.lowLeftZone)
      arm += "偏多｜已離開，等待回踩支撐";
   else if(setupBuyArmed)
      arm += "偏多｜已掃除，等待離開後回踩";
   else if(setupSellArmed && g_mem.highLeftZone)
      arm += "偏空｜已離開，等待回踩阻力";
   else if(setupSellArmed)
      arm += "偏空｜已掃除，等待離開後回踩";
   else
      arm += "等待流動性掃除";
   PanelSet("OHLCST_T11", x, y, arm, clrAqua, fs);
   y += line;

   if(lastSig.valid)
     {
      const string sideCN = (lastSig.side == SIDE_BUY) ? "買入" : "賣出";
      PanelSet("OHLCST_T12", x, y,
               "最近訊號：" + sideCN + "｜" + lastSig.patternCN,
               (lastSig.side == SIDE_BUY) ? clrLime : clrTomato, fs);
      y += line;
      PanelSet("OHLCST_T13", x, y,
               StringFormat("進場 %s  SL %s  TP %s  RR %.2f",
                            DoubleToString(lastSig.entry, _Digits),
                            DoubleToString(lastSig.stopLoss, _Digits),
                            DoubleToString(lastSig.takeProfit, _Digits),
                            lastSig.riskReward),
               clrWhite, fs - 1);
      y += line;
      PanelSet("OHLCST_T14", x, y, lastSig.noteCN, clrSilver, fs - 1);
     }
   else
     {
      PanelSet("OHLCST_T12", x, y, "最近訊號：無（收K後才確認）", clrSilver, fs);
      PanelSet("OHLCST_T13", x, y, "", clrSilver, fs);
      PanelSet("OHLCST_T14", x, y, "說明：訊號只在收盤確認，歷史箭頭不消失", clrDimGray, fs - 1);
     }
  }

void DrawHLine(const string name, const double price, const color clr, const ENUM_LINE_STYLE st)
  {
   if(!InpShowSRLines || price <= 0.0)
     {
      ObjectDelete(0, name);
      ObjectDelete(0, name + "_TXT");
      return;
     }
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, st);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

   // S / R 文字標示
   const string tag = name + "_TXT";
   ObjectDelete(0, tag);
   ObjectCreate(0, tag, OBJ_TEXT, 0, TimeCurrent(), price);
   ObjectSetString(0, tag, OBJPROP_TEXT, StringFind(name, "SUP") >= 0 ? "S" : "R");
   ObjectSetInteger(0, tag, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, tag, OBJPROP_FONTSIZE, 12);
   ObjectSetString(0, tag, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, tag, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, tag, OBJPROP_SELECTABLE, false);
  }

void PersistSignalObjects(const StructureSignal &sig)
  {
   // 以 barTime 為鍵，歷史重算時覆寫同鍵，不會「閃爍消失」
   if(!sig.valid)
      return;
   const string key = "OHLCST_SIG_" + IntegerToString((long)sig.signalId);
   const color cArrow = (sig.side == SIDE_BUY) ? clrDodgerBlue : clrOrangeRed;

   if(InpShowEntryPlan)
     {
      ObjectDelete(0, key + "_E");
      ObjectDelete(0, key + "_SL");
      ObjectDelete(0, key + "_TP");
      const datetime t2 = sig.barTime + (datetime)PeriodSeconds() * 12;
      ObjectCreate(0, key + "_E", OBJ_TREND, 0, sig.barTime, sig.entry, t2, sig.entry);
      ObjectSetInteger(0, key + "_E", OBJPROP_COLOR, cArrow);
      ObjectSetInteger(0, key + "_E", OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, key + "_E", OBJPROP_RAY_RIGHT, false);

      ObjectCreate(0, key + "_SL", OBJ_TREND, 0, sig.barTime, sig.stopLoss, t2, sig.stopLoss);
      ObjectSetInteger(0, key + "_SL", OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, key + "_SL", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, key + "_SL", OBJPROP_RAY_RIGHT, false);

      ObjectCreate(0, key + "_TP", OBJ_TREND, 0, sig.barTime, sig.takeProfit, t2, sig.takeProfit);
      ObjectSetInteger(0, key + "_TP", OBJPROP_COLOR, clrLime);
      ObjectSetInteger(0, key + "_TP", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, key + "_TP", OBJPROP_RAY_RIGHT, false);
     }

   ObjectDelete(0, key + "_L");
   ObjectCreate(0, key + "_L", OBJ_TEXT, 0, sig.barTime, sig.entry);
   const string tag = (sig.side == SIDE_BUY) ? ("S " + sig.patternCN) : ("R " + sig.patternCN);
   ObjectSetString(0, key + "_L", OBJPROP_TEXT, tag);
   ObjectSetInteger(0, key + "_L", OBJPROP_COLOR, cArrow);
   ObjectSetInteger(0, key + "_L", OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, key + "_L", OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, key + "_L", OBJPROP_ANCHOR,
                    (sig.side == SIDE_BUY) ? ANCHOR_UPPER : ANCHOR_LOWER);
  }

void MarkSweep(const datetime t, const double price, const bool isLow)
  {
   if(!InpShowSweepMarks)
      return;
   const string n = "OHLCST_SW_" + IntegerToString((long)t) + (isLow ? "L" : "H");
   ObjectDelete(0, n);
   ObjectCreate(0, n, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, n, OBJPROP_ARROWCODE, isLow ? 241 : 242);
   ObjectSetInteger(0, n, OBJPROP_COLOR, isLow ? clrAqua : clrMagenta);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
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
   const int need = InpStructLookback + InpAtrPeriod + InpSwingLeft + InpSwingRight + 10;
   if(rates_total < need)
      return 0;

   // 緩衝：歷史已收盤訊號用確定性重算寫入 → 收K後不會因重繪而消失
   // 僅在全量重算或新K時更新；對已收盤 index 結果穩定
   int start;
   if(prev_calculated <= 0)
     {
      ArrayInitialize(BuyBuffer, EMPTY_VALUE);
      ArrayInitialize(SellBuffer, EMPTY_VALUE);
      ObjectsDeleteAll(0, "OHLCST_SIG_");
      ObjectsDeleteAll(0, "OHLCST_SW_");
      Structure_ResetSweepMemory(g_mem);
      start = InpAtrPeriod + InpSwingLeft + InpSwingRight + 2;
     }
   else
     {
      // 從上一根已處理附近繼續（重算最後數根以銜接掃除記憶）
      start = MathMax(InpAtrPeriod + InpSwingLeft + InpSwingRight + 2, prev_calculated - 3);
      Structure_ResetSweepMemory(g_mem);
      // 為保持掃除記憶正確，仍從較早位置重建 mem（不清除已畫歷史物件）
      start = InpAtrPeriod + InpSwingLeft + InpSwingRight + 2;
      // 增量時先清空緩衝再全量填（訊號確定性）
      ArrayInitialize(BuyBuffer, EMPTY_VALUE);
      ArrayInitialize(SellBuffer, EMPTY_VALUE);
     }

   // 面版用即時多時框；歷史進場用「該K當時」圖表結構偏向，避免HTF變化造成重繪
   Structure_BuildBias(_Symbol, InpHTF, InpMTF, InpLTF, g_cfg, g_bias);

   StructureSignal lastSig;
   ZeroMemory(lastSig);
   LiquidityState lastLiq;
   ZeroMemory(lastLiq);

   // 只做到 rates_total-2（最後已收盤）；rates_total-1 為未收盤，不給訊號
   const int lastClosed = rates_total - 2;
   for(int i = start; i <= lastClosed; i++)
     {
      BiasSnapshot barBias;
      ZeroMemory(barBias);
      barBias.ltf = Structure_BiasFromSwings(high, low, close, i, InpSwingLeft, InpSwingRight,
                                             rates_total, MathMin(40, InpStructLookback));
      // 歷史對齊：用當時圖表結構；最新幾根才套用即時 HTF/MTF 綜合偏向
      if(i >= lastClosed - 2)
         barBias = g_bias;
      else
        {
         barBias.htf = barBias.ltf;
         barBias.mtf = barBias.ltf;
         barBias.consensus = barBias.ltf;
        }

      StructureSignal sig;
      const bool hit = Structure_EvaluateEntry(open, high, low, close, time, i, rates_total,
                                               g_cfg, barBias, g_mem, sig);

      // 掃除標記（同根偵測）
      const double atr = Structure_ATR(high, low, close, i, InpAtrPeriod);
      LiquidityState liq;
      Structure_DetectLiquidity(open, high, low, close, time, i, rates_total, g_cfg, atr, liq);
      if(liq.sweptLow)
        {
         MarkSweep(time[i], low[i], true);
         lastLiq = liq;
        }
      if(liq.sweptHigh)
        {
         MarkSweep(time[i], high[i], false);
         lastLiq = liq;
        }

      if(hit && sig.valid)
        {
         if(sig.side == SIDE_BUY)
            BuyBuffer[i] = low[i];
         else
            SellBuffer[i] = high[i];
         PersistSignalObjects(sig);
         lastSig = sig;
        }
     }

   // 當前面版用最新已收盤狀態
   ValidSR srNow;
   LiquidityState liqMem;
   ZeroMemory(liqMem);
   if(g_mem.hasLowSweep)
     {
      liqMem.sweptLow = true;
      liqMem.sweptLowLevel = g_mem.lowLevel;
     }
   if(g_mem.hasHighSweep)
     {
      liqMem.sweptHigh = true;
      liqMem.sweptHighLevel = g_mem.highLevel;
     }
   Structure_BuildValidSR(high, low, close, time, lastClosed, rates_total, g_cfg, liqMem, srNow);
   DrawHLine("OHLCST_SUP", srNow.hasSupport ? srNow.support : 0.0, clrDodgerBlue, STYLE_SOLID);
   DrawHLine("OHLCST_RES", srNow.hasResist ? srNow.resist : 0.0, clrOrangeRed, STYLE_SOLID);

   const bool buyArmed = g_mem.hasLowSweep && !g_mem.lowConsumed &&
                         (g_bias.consensus == BIAS_BULL || g_bias.htf == BIAS_BULL || !InpRequireHtfAlign);
   const bool sellArmed = g_mem.hasHighSweep && !g_mem.highConsumed &&
                          (g_bias.consensus == BIAS_BEAR || g_bias.htf == BIAS_BEAR || !InpRequireHtfAlign);

   UpdatePanel(g_bias, liqMem, srNow, lastSig, buyArmed, sellArmed);
   return rates_total;
  }
//+------------------------------------------------------------------+
