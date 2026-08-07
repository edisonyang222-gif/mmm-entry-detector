//+------------------------------------------------------------------+
//| StructureLogic.mqh                                                |
//| 多時框偏向 / 流動性掃除 / 有效支撐阻力 / 回踩進場（指標與EA共用）   |
//+------------------------------------------------------------------+
#property copyright "MMM Entry Detector"
#property strict

#ifndef STRUCTURE_LOGIC_MQH
#define STRUCTURE_LOGIC_MQH

enum ENUM_BIAS
  {
   BIAS_NEUTRAL = 0,
   BIAS_BULL    = 1,
   BIAS_BEAR    = -1
  };

enum ENUM_SIDE
  {
   SIDE_BUY  = 1,
   SIDE_SELL = -1
  };

enum ENUM_ENTRY_KIND
  {
   ENTRY_NONE              = 0,
   ENTRY_PULLBACK_SUPPORT  = 1,  // 偏多：掃除低點流動性後回踩有效支撐
   ENTRY_PULLBACK_RESIST   = 2,  // 偏空：掃除高點流動性後回踩有效阻力
   ENTRY_RECLAIM_SUPPORT   = 3,  // 失而復得支撐（收復）
   ENTRY_RECLAIM_RESIST    = 4   // 失而復得阻力（跌破收回）
  };

struct StructureConfig
  {
   int      swingLeft;          // 樞軸左側K數
   int      swingRight;         // 樞軸右側K數
   int      atrPeriod;
   int      sweepLookback;      // 流動性掃除有效窗口（K數）
   int      structureLookback;  // 掃描擺盪點範圍
   double   sweepWickAtr;       // 影線穿越最小ATR倍數
   double   zoneAtr;            // 回踩區寬度（ATR）
   double   confirmBodyRatio;   // 確認K實體占比
   double   stopBufAtr;
   double   minRR;
   double   tpRR;
   bool     requireHtfAlign;    // 必須與高週期偏向一致
   bool     requireSweep;       // 必須先有流動性掃除
   bool     oneSignalPerSetup;  // 同一掃除事件僅一次進場
  };

struct SwingPoint
  {
   bool     valid;
   double   price;
   datetime time;
   int      barIndex;           // OnCalculate: 0=最舊；EA shift 模式另述
   bool     isHigh;             // true=擺盪高(阻力候選) false=擺盪低(支撐候選)
   bool     broken;             // 實體收盤穿越則視為失效
   int      touches;
  };

struct LiquidityState
  {
   bool     sweptLow;           // 已掃除下方流動性（偏多前置）
   bool     sweptHigh;          // 已掃除上方流動性（偏空前置）
   double   sweptLowLevel;
   double   sweptHighLevel;
   datetime sweptLowTime;
   datetime sweptHighTime;
   int      sweptLowBar;
   int      sweptHighBar;
  };

struct ValidSR
  {
   bool     hasSupport;
   bool     hasResist;
   double   support;
   double   resist;
   string   supportNote;        // 中文說明
   string   resistNote;
  };

struct BiasSnapshot
  {
   ENUM_BIAS htf;
   ENUM_BIAS mtf;
   ENUM_BIAS ltf;
   ENUM_BIAS consensus;         // 綜合偏向預判
   string    htfText;
   string    mtfText;
   string    ltfText;
   string    consensusText;     // 大概率走向
   string    reasonText;        // 理由
  };

struct StructureSignal
  {
   bool            valid;
   ENUM_SIDE       side;
   ENUM_ENTRY_KIND kind;
   double          entry;
   double          stopLoss;
   double          takeProfit;
   double          riskReward;
   double          zoneTop;
   double          zoneBottom;
   double          refLevel;       // 回踩的有效S/R
   datetime        barTime;        // 收K時間（訊號錨點，不消失）
   int             barIndex;
   string          patternCN;      // 型態中文名
   string          noteCN;         // 補充說明
   ulong           signalId;       // barTime 衍生，持久化鍵
  };

void Structure_InitConfig(StructureConfig &cfg,
                          const int swingLeft = 2,
                          const int swingRight = 2,
                          const int atrPeriod = 14,
                          const int sweepLookback = 30,
                          const int structureLookback = 80,
                          const double sweepWickAtr = 0.05,
                          const double zoneAtr = 0.35,
                          const double confirmBodyRatio = 0.45,
                          const double stopBufAtr = 0.15,
                          const double minRR = 1.5,
                          const double tpRR = 2.0,
                          const bool requireHtfAlign = true,
                          const bool requireSweep = true,
                          const bool oneSignalPerSetup = true)
  {
   cfg.swingLeft = MathMax(1, swingLeft);
   cfg.swingRight = MathMax(1, swingRight);
   cfg.atrPeriod = atrPeriod;
   cfg.sweepLookback = sweepLookback;
   cfg.structureLookback = structureLookback;
   cfg.sweepWickAtr = sweepWickAtr;
   cfg.zoneAtr = zoneAtr;
   cfg.confirmBodyRatio = confirmBodyRatio;
   cfg.stopBufAtr = stopBufAtr;
   cfg.minRR = minRR;
   cfg.tpRR = tpRR;
   cfg.requireHtfAlign = requireHtfAlign;
   cfg.requireSweep = requireSweep;
   cfg.oneSignalPerSetup = oneSignalPerSetup;
  }

string BiasToCN(const ENUM_BIAS b)
  {
   if(b == BIAS_BULL)
      return "偏多 ▲";
   if(b == BIAS_BEAR)
      return "偏空 ▼";
   return "盤整 ─";
  }

string EntryKindCN(const ENUM_ENTRY_KIND k)
  {
   switch(k)
     {
      case ENTRY_PULLBACK_SUPPORT: return "回踩有效支撐";
      case ENTRY_PULLBACK_RESIST:  return "回踩有效阻力";
      case ENTRY_RECLAIM_SUPPORT:  return "收復有效支撐";
      case ENTRY_RECLAIM_RESIST:   return "跌破收回阻力";
      default:                     return "無";
     }
  }

string ConsensusCN(const ENUM_BIAS b)
  {
   if(b == BIAS_BULL)
      return "大概率向上";
   if(b == BIAS_BEAR)
      return "大概率向下";
   return "方向不明，觀望";
  }

//--- ATR（OnCalculate 陣列：index 0 = 最舊）
double Structure_ATR(const double &high[], const double &low[], const double &close[],
                     const int endIndex, const int period)
  {
   if(endIndex - period < 0 || period <= 0)
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

//--- 擺盪高/低（需左右各 N 根確認 → 收K後才成立，不重繪）
bool Structure_IsSwingHigh(const double &high[], const int i,
                           const int left, const int right, const int rates_total)
  {
   if(i - left < 0 || i + right >= rates_total)
      return false;
   for(int k = 1; k <= left; k++)
      if(high[i - k] >= high[i])
         return false;
   for(int k = 1; k <= right; k++)
      if(high[i + k] > high[i])
         return false;
   return true;
  }

bool Structure_IsSwingLow(const double &low[], const int i,
                          const int left, const int right, const int rates_total)
  {
   if(i - left < 0 || i + right >= rates_total)
      return false;
   for(int k = 1; k <= left; k++)
      if(low[i - k] <= low[i])
         return false;
   for(int k = 1; k <= right; k++)
      if(low[i + k] < low[i])
         return false;
   return true;
  }

ENUM_BIAS Structure_BiasFromSwings(const double &high[], const double &low[], const double &close[],
                                   const int endIndex, const int left, const int right,
                                   const int rates_total, const int lookback)
  {
   // 找最近兩個已確認擺盪高/低，比較結構
   double sh1 = 0, sh2 = 0, sl1 = 0, sl2 = 0;
   int nH = 0, nL = 0;
   const int from = MathMax(left, endIndex - lookback);
   // 從新到舊掃描已確認樞軸（樞軸中心需 +right 才確認，故中心 <= endIndex-right）
   for(int i = endIndex - right; i >= from + left && (nH < 2 || nL < 2); i--)
     {
      if(nH < 2 && Structure_IsSwingHigh(high, i, left, right, rates_total))
        {
         if(nH == 0)
            sh1 = high[i];
         else
            sh2 = high[i];
         nH++;
        }
      if(nL < 2 && Structure_IsSwingLow(low, i, left, right, rates_total))
        {
         if(nL == 0)
            sl1 = low[i];
         else
            sl2 = low[i];
         nL++;
        }
     }
   if(nH >= 2 && nL >= 2)
     {
      const bool hh = sh1 > sh2;
      const bool hl = sl1 > sl2;
      const bool lh = sh1 < sh2;
      const bool ll = sl1 < sl2;
      if(hh && hl)
         return BIAS_BULL;
      if(lh && ll)
         return BIAS_BEAR;
     }
   // 退化：用收盤相對中段
   if(endIndex >= lookback)
     {
      double hi = high[endIndex - lookback + 1];
      double lo = low[endIndex - lookback + 1];
      for(int i = endIndex - lookback + 1; i <= endIndex; i++)
        {
         hi = MathMax(hi, high[i]);
         lo = MathMin(lo, low[i]);
        }
      const double mid = 0.5 * (hi + lo);
      if(close[endIndex] > mid)
         return BIAS_BULL;
      if(close[endIndex] < mid)
         return BIAS_BEAR;
     }
   return BIAS_NEUTRAL;
  }

ENUM_BIAS Structure_BiasFromSymbolTF(const string symbol, const ENUM_TIMEFRAMES tf,
                                     const int swingLeft, const int swingRight, const int lookback)
  {
   const int bars = Bars(symbol, tf);
   if(bars < lookback + swingLeft + swingRight + 5)
      return BIAS_NEUTRAL;

   // 複製足夠K線（AsSeries=true → index 0 = 當前）
   double high[], low[], close[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   const int need = lookback + swingLeft + swingRight + 5;
   if(CopyHigh(symbol, tf, 0, need, high) < need)
      return BIAS_NEUTRAL;
   if(CopyLow(symbol, tf, 0, need, low) < need)
      return BIAS_NEUTRAL;
   if(CopyClose(symbol, tf, 0, need, close) < need)
      return BIAS_NEUTRAL;

   // 轉成 oldest-first 以重用 BiasFromSwings
   double h2[], l2[], c2[];
   ArrayResize(h2, need);
   ArrayResize(l2, need);
   ArrayResize(c2, need);
   for(int i = 0; i < need; i++)
     {
      h2[i] = high[need - 1 - i];
      l2[i] = low[need - 1 - i];
      c2[i] = close[need - 1 - i];
     }
   // 用已收盤最後一根（need-2，跳過當前未收盤 need-1）
   const int endIndex = need - 2;
   return Structure_BiasFromSwings(h2, l2, c2, endIndex, swingLeft, swingRight, need, lookback);
  }

void Structure_BuildBias(const string symbol,
                         const ENUM_TIMEFRAMES htf,
                         const ENUM_TIMEFRAMES mtf,
                         const ENUM_TIMEFRAMES ltf,
                         const StructureConfig &cfg,
                         BiasSnapshot &out)
  {
   ZeroMemory(out);
   out.htf = Structure_BiasFromSymbolTF(symbol, htf, cfg.swingLeft, cfg.swingRight, cfg.structureLookback);
   out.mtf = Structure_BiasFromSymbolTF(symbol, mtf, cfg.swingLeft, cfg.swingRight, cfg.structureLookback);
   out.ltf = Structure_BiasFromSymbolTF(symbol, ltf, cfg.swingLeft, cfg.swingRight, MathMin(40, cfg.structureLookback));
   out.htfText = BiasToCN(out.htf);
   out.mtfText = BiasToCN(out.mtf);
   out.ltfText = BiasToCN(out.ltf);

   // 綜合：HTF 權重最高；MTF 同向則確立；衝突則中性偏 HTF
   if(out.htf == out.mtf && out.htf != BIAS_NEUTRAL)
      out.consensus = out.htf;
   else if(out.htf != BIAS_NEUTRAL && out.mtf == BIAS_NEUTRAL)
      out.consensus = out.htf;
   else if(out.htf == BIAS_NEUTRAL && out.mtf != BIAS_NEUTRAL)
      out.consensus = out.mtf;
   else if(out.htf != BIAS_NEUTRAL && out.ltf == out.htf)
      out.consensus = out.htf;
   else
      out.consensus = BIAS_NEUTRAL;

   out.consensusText = ConsensusCN(out.consensus);
   if(out.consensus == BIAS_BULL)
      out.reasonText = "高週期與中週期結構偏多，優先找回踩做多";
   else if(out.consensus == BIAS_BEAR)
      out.reasonText = "高週期與中週期結構偏空，優先找回踩做空";
   else
      out.reasonText = "多時框未對齊，等待結構轉折或流動性掃除";
  }

//--- 找最近有效擺盪低/高（尚未被收盤有效跌破/升破）
bool Structure_FindNearestSwingLow(const double &low[], const double &close[], const datetime &time[],
                                   const int endIndex, const int left, const int right,
                                   const int rates_total, const int lookback, SwingPoint &sw)
  {
   ZeroMemory(sw);
   const int from = MathMax(left, endIndex - lookback);
   for(int i = endIndex - right; i >= from + left; i--)
     {
      if(!Structure_IsSwingLow(low, i, left, right, rates_total))
         continue;
      // 之後是否被收盤跌破
      bool broken = false;
      for(int j = i + right + 1; j <= endIndex; j++)
        {
         if(close[j] < low[i])
           {
            broken = true;
            break;
           }
        }
      sw.valid = true;
      sw.price = low[i];
      sw.time = time[i];
      sw.barIndex = i;
      sw.isHigh = false;
      sw.broken = broken;
      return true; // 最近一個（含已破，呼叫端可篩）
     }
   return false;
  }

bool Structure_FindNearestSwingHigh(const double &high[], const double &close[], const datetime &time[],
                                    const int endIndex, const int left, const int right,
                                    const int rates_total, const int lookback, SwingPoint &sw)
  {
   ZeroMemory(sw);
   const int from = MathMax(left, endIndex - lookback);
   for(int i = endIndex - right; i >= from + left; i--)
     {
      if(!Structure_IsSwingHigh(high, i, left, right, rates_total))
         continue;
      bool broken = false;
      for(int j = i + right + 1; j <= endIndex; j++)
        {
         if(close[j] > high[i])
           {
            broken = true;
            break;
           }
        }
      sw.valid = true;
      sw.price = high[i];
      sw.time = time[i];
      sw.barIndex = i;
      sw.isHigh = true;
      sw.broken = broken;
      return true;
     }
   return false;
  }

//--- 流動性掃除：影線穿越最近擺盪極值，收盤收回結構內
void Structure_DetectLiquidity(const double &open[], const double &high[], const double &low[],
                               const double &close[], const datetime &time[],
                               const int endIndex, const int rates_total,
                               const StructureConfig &cfg, const double atr,
                               LiquidityState &liq)
  {
   ZeroMemory(liq);
   if(atr <= 0.0 || endIndex < cfg.swingLeft + cfg.swingRight + 2)
      return;

   SwingPoint nearestLow, nearestHigh;
   // 掃除發生在 endIndex 這根K：找 endIndex 之前已確認的擺盪
   const int pivotEnd = endIndex - 1;
   Structure_FindNearestSwingLow(low, close, time, pivotEnd, cfg.swingLeft, cfg.swingRight,
                                 rates_total, cfg.structureLookback, nearestLow);
   Structure_FindNearestSwingHigh(high, close, time, pivotEnd, cfg.swingLeft, cfg.swingRight,
                                  rates_total, cfg.structureLookback, nearestHigh);

   const double wickMin = cfg.sweepWickAtr * atr;
   const double o = open[endIndex];
   const double h = high[endIndex];
   const double l = low[endIndex];
   const double c = close[endIndex];

   // 下方流動性：刺破擺盪低，收盤回到其上方
   if(nearestLow.valid && !nearestLow.broken)
     {
      if(l < nearestLow.price - wickMin && c > nearestLow.price && c > o)
        {
         liq.sweptLow = true;
         liq.sweptLowLevel = nearestLow.price;
         liq.sweptLowTime = time[endIndex];
         liq.sweptLowBar = endIndex;
        }
     }
   // 上方流動性
   if(nearestHigh.valid && !nearestHigh.broken)
     {
      if(h > nearestHigh.price + wickMin && c < nearestHigh.price && c < o)
        {
         liq.sweptHigh = true;
         liq.sweptHighLevel = nearestHigh.price;
         liq.sweptHighTime = time[endIndex];
         liq.sweptHighBar = endIndex;
        }
     }
  }

//--- 有效支撐/阻力：最近未失效擺盪 + 可選掃除水位
void Structure_BuildValidSR(const double &high[], const double &low[], const double &close[],
                            const datetime &time[], const int endIndex, const int rates_total,
                            const StructureConfig &cfg, const LiquidityState &liqActive,
                            ValidSR &sr)
  {
   ZeroMemory(sr);
   sr.supportNote = "無";
   sr.resistNote = "無";

   SwingPoint sl, sh;
   Structure_FindNearestSwingLow(low, close, time, endIndex, cfg.swingLeft, cfg.swingRight,
                                 rates_total, cfg.structureLookback, sl);
   Structure_FindNearestSwingHigh(high, close, time, endIndex, cfg.swingLeft, cfg.swingRight,
                                  rates_total, cfg.structureLookback, sh);

   if(sl.valid && !sl.broken && close[endIndex] > sl.price)
     {
      sr.hasSupport = true;
      sr.support = sl.price;
      sr.supportNote = "擺盪低點支撐";
     }
   if(liqActive.sweptLow && close[endIndex] > liqActive.sweptLowLevel)
     {
      sr.hasSupport = true;
      sr.support = liqActive.sweptLowLevel;
      sr.supportNote = "掃除後有效支撐";
     }

   if(sh.valid && !sh.broken && close[endIndex] < sh.price)
     {
      sr.hasResist = true;
      sr.resist = sh.price;
      sr.resistNote = "擺盪高點阻力";
     }
   if(liqActive.sweptHigh && close[endIndex] < liqActive.sweptHighLevel)
     {
      sr.hasResist = true;
      sr.resist = liqActive.sweptHighLevel;
      sr.resistNote = "掃除後有效阻力";
     }
  }

bool Structure_BuildTradePlan(const ENUM_SIDE side, const ENUM_ENTRY_KIND kind,
                              const double entry, const double refLevel,
                              const double zoneTop, const double zoneBottom,
                              const double atr, const StructureConfig &cfg,
                              const datetime barTime, const int barIndex,
                              const string noteCN, StructureSignal &sig)
  {
   ZeroMemory(sig);
   if(atr <= 0.0 || entry <= 0.0)
      return false;

   double sl = 0.0;
   double tp = 0.0;
   if(side == SIDE_BUY)
     {
      sl = MathMin(zoneBottom, refLevel) - cfg.stopBufAtr * atr;
      tp = entry + cfg.tpRR * (entry - sl);
     }
   else
     {
      sl = MathMax(zoneTop, refLevel) + cfg.stopBufAtr * atr;
      tp = entry - cfg.tpRR * (sl - entry);
     }
   const double risk = MathAbs(entry - sl);
   if(risk <= 0.0)
      return false;
   const double rr = MathAbs(tp - entry) / risk;
   if(rr < cfg.minRR)
      return false;

   sig.valid = true;
   sig.side = side;
   sig.kind = kind;
   sig.entry = entry;
   sig.stopLoss = sl;
   sig.takeProfit = tp;
   sig.riskReward = rr;
   sig.zoneTop = zoneTop;
   sig.zoneBottom = zoneBottom;
   sig.refLevel = refLevel;
   sig.barTime = barTime;
   sig.barIndex = barIndex;
   sig.patternCN = EntryKindCN(kind);
   sig.noteCN = noteCN;
   sig.signalId = (ulong)barTime;
   return true;
  }

//--- 追蹤最近一次掃除（跨K保留，供回踩使用）
struct SweepMemory
  {
   bool     hasLowSweep;
   bool     hasHighSweep;
   double   lowLevel;
   double   highLevel;
   int      lowBar;
   int      highBar;
   datetime lowTime;
   datetime highTime;
   bool     lowConsumed;   // 已產生進場
   bool     highConsumed;
   bool     lowLeftZone;   // 掃除後曾離開支撐區（才算回踩）
   bool     highLeftZone;  // 掃除後曾離開阻力區
  };

void Structure_ResetSweepMemory(SweepMemory &m)
  {
   ZeroMemory(m);
  }

void Structure_RememberSweep(SweepMemory &mem, const LiquidityState &liq,
                             const int endIndex, const StructureConfig &cfg)
  {
   // 過期清理
   if(mem.hasLowSweep && (endIndex - mem.lowBar) > cfg.sweepLookback)
     {
      mem.hasLowSweep = false;
      mem.lowConsumed = false;
     }
   if(mem.hasHighSweep && (endIndex - mem.highBar) > cfg.sweepLookback)
     {
      mem.hasHighSweep = false;
      mem.highConsumed = false;
     }
   if(liq.sweptLow)
     {
      mem.hasLowSweep = true;
      mem.lowLevel = liq.sweptLowLevel;
      mem.lowBar = liq.sweptLowBar;
      mem.lowTime = liq.sweptLowTime;
      mem.lowConsumed = false;
      mem.lowLeftZone = false;
     }
   if(liq.sweptHigh)
     {
      mem.hasHighSweep = true;
      mem.highLevel = liq.sweptHighLevel;
      mem.highBar = liq.sweptHighBar;
      mem.highTime = liq.sweptHighTime;
      mem.highConsumed = false;
      mem.highLeftZone = false;
     }
  }

//--- 核心：在「已收盤」K上評估精準回踩進場（不重繪）
bool Structure_EvaluateEntry(const double &open[], const double &high[], const double &low[],
                             const double &close[], const datetime &time[],
                             const int i, const int rates_total,
                             const StructureConfig &cfg, const BiasSnapshot &bias,
                             SweepMemory &mem, StructureSignal &sig)
  {
   ZeroMemory(sig);
   if(i <= 0 || i >= rates_total - 1)
      return false; // 不評估最舊與未收盤

   const double atr = Structure_ATR(high, low, close, i, cfg.atrPeriod);
   if(atr <= 0.0)
      return false;

   LiquidityState liqNow;
   Structure_DetectLiquidity(open, high, low, close, time, i, rates_total, cfg, atr, liqNow);
   Structure_RememberSweep(mem, liqNow, i, cfg);

   ValidSR sr;
   // 用記憶中的掃除水位強化有效S/R
   LiquidityState liqForSR;
   ZeroMemory(liqForSR);
   if(mem.hasLowSweep)
     {
      liqForSR.sweptLow = true;
      liqForSR.sweptLowLevel = mem.lowLevel;
     }
   if(mem.hasHighSweep)
     {
      liqForSR.sweptHigh = true;
      liqForSR.sweptHighLevel = mem.highLevel;
     }
   Structure_BuildValidSR(high, low, close, time, i, rates_total, cfg, liqForSR, sr);

   const double o = open[i];
   const double h = high[i];
   const double l = low[i];
   const double c = close[i];
   const double rng = h - l;
   if(rng <= 0.0)
      return false;
   const double bodyRatio = MathAbs(c - o) / rng;
   const bool bullConfirm = (c > o) && (bodyRatio >= cfg.confirmBodyRatio);
   const bool bearConfirm = (c < o) && (bodyRatio >= cfg.confirmBodyRatio);

   // 追蹤是否已離開區域（回踩前提）
   if(mem.hasLowSweep && !mem.lowConsumed)
     {
      const double leave = mem.lowLevel + cfg.zoneAtr * atr;
      if(c > leave)
         mem.lowLeftZone = true;
     }
   if(mem.hasHighSweep && !mem.highConsumed)
     {
      const double leave = mem.highLevel - cfg.zoneAtr * atr;
      if(c < leave)
         mem.highLeftZone = true;
     }

   // ===== 偏多：掃除下方流動性 → 回踩有效支撐 → 陽線確認 =====
   const bool bullBiasOk = (!cfg.requireHtfAlign) || (bias.consensus == BIAS_BULL) || (bias.htf == BIAS_BULL);
   if(bullBiasOk && sr.hasSupport)
     {
      const bool sweepOk = (!cfg.requireSweep) || mem.hasLowSweep;
      const bool notUsed = (!cfg.oneSignalPerSetup) || !mem.lowConsumed;
      const bool pulledBack = (!cfg.requireSweep) || mem.lowLeftZone;
      if(sweepOk && notUsed && pulledBack)
        {
         const double ref = sr.support;
         const double zoneBot = ref - cfg.zoneAtr * atr;
         const double zoneTop = ref + cfg.zoneAtr * atr;
         const bool touched = (l <= zoneTop && l >= zoneBot) || (l <= ref && c >= ref);
         // 回踩：本K進入支撐區且收在區內上方，且非掃除當根（至少隔1根）
         const bool afterSweep = (!mem.hasLowSweep) || (i > mem.lowBar);
         if(touched && afterSweep && bullConfirm && c >= ref)
           {
            const string note = StringFormat("流動性:%s | 支撐:%s",
                                             mem.hasLowSweep ? "已掃除下方" : "未要求",
                                             sr.supportNote);
            if(Structure_BuildTradePlan(SIDE_BUY, ENTRY_PULLBACK_SUPPORT, c, ref,
                                        zoneTop, zoneBot, atr, cfg, time[i], i, note, sig))
              {
               if(cfg.oneSignalPerSetup)
                  mem.lowConsumed = true;
               return true;
              }
           }
        }
     }

   // ===== 偏空：掃除上方流動性 → 回踩有效阻力 → 陰線確認 =====
   const bool bearBiasOk = (!cfg.requireHtfAlign) || (bias.consensus == BIAS_BEAR) || (bias.htf == BIAS_BEAR);
   if(bearBiasOk && sr.hasResist)
     {
      const bool sweepOk = (!cfg.requireSweep) || mem.hasHighSweep;
      const bool notUsed = (!cfg.oneSignalPerSetup) || !mem.highConsumed;
      const bool pulledBack = (!cfg.requireSweep) || mem.highLeftZone;
      if(sweepOk && notUsed && pulledBack)
        {
         const double ref = sr.resist;
         const double zoneTop = ref + cfg.zoneAtr * atr;
         const double zoneBot = ref - cfg.zoneAtr * atr;
         const bool touched = (h >= zoneBot && h <= zoneTop) || (h >= ref && c <= ref);
         const bool afterSweep = (!mem.hasHighSweep) || (i > mem.highBar);
         if(touched && afterSweep && bearConfirm && c <= ref)
           {
            const string note = StringFormat("流動性:%s | 阻力:%s",
                                             mem.hasHighSweep ? "已掃除上方" : "未要求",
                                             sr.resistNote);
            if(Structure_BuildTradePlan(SIDE_SELL, ENTRY_PULLBACK_RESIST, c, ref,
                                        zoneTop, zoneBot, atr, cfg, time[i], i, note, sig))
              {
               if(cfg.oneSignalPerSetup)
                  mem.highConsumed = true;
               return true;
              }
           }
        }
     }

   return false;
  }

#endif // STRUCTURE_LOGIC_MQH
//+------------------------------------------------------------------+
