//+------------------------------------------------------------------+
//| IntradayOHLCLogic.mqh                                             |
//| Shared intraday OHLC entry logic for Indicator / EA               |
//+------------------------------------------------------------------+
#property copyright "MMM Entry Detector"
#property strict

#ifndef INTRADAY_OHLC_LOGIC_MQH
#define INTRADAY_OHLC_LOGIC_MQH

enum ENUM_OHLC_SIDE
  {
   OHLC_BUY  = 1,
   OHLC_SELL = -1
  };

enum ENUM_OHLC_SIGNAL_TYPE
  {
   OHLC_SIG_NONE           = 0,
   OHLC_SIG_PDH_BREAKOUT   = 1,  // Close breaks above Previous Day High
   OHLC_SIG_PDL_BREAKOUT   = 2,  // Close breaks below Previous Day Low
   OHLC_SIG_OPEN_BREAK_BUY = 3,  // Close crosses above Day Open
   OHLC_SIG_OPEN_BREAK_SELL= 4,  // Close crosses below Day Open
   OHLC_SIG_PDH_REJECTION  = 5,  // Wick rejects PDH → sell
   OHLC_SIG_PDL_REJECTION  = 6,  // Wick rejects PDL → buy
   OHLC_SIG_ORB_BREAK_BUY  = 7,  // Opening range high breakout
   OHLC_SIG_ORB_BREAK_SELL = 8   // Opening range low breakout
  };

enum ENUM_OHLC_MODE
  {
   OHLC_MODE_BREAKOUT  = 0,  // PDH/PDL + ORB breakouts
   OHLC_MODE_REJECTION = 1,  // PDH/PDL rejections only
   OHLC_MODE_OPEN      = 2,  // Day Open cross only
   OHLC_MODE_ALL       = 3   // All enabled signal types
  };

struct OHLCConfig
  {
   ENUM_OHLC_MODE mode;
   int            sessionStartHour;   // Trading-day rollover hour (server time)
   int            orbBars;            // Opening-range bars after session start
   double         touchTolAtr;        // Touch tolerance in ATR multiples
   double         minBreakAtr;        // Min break distance beyond level (ATR)
   double         rejectBodyRatio;    // Min body/range for rejection candle
   double         stopAtrMult;        // SL distance in ATR
   double         minRR;              // Minimum reward:risk
   double         tpRR;               // Take-profit RR multiple
   bool           useLevelTP;         // Prefer next OHLC level as TP when RR ok
   bool           onePerDayPerSide;   // Cap signals per day / side
   bool           enableBreakout;
   bool           enableRejection;
   bool           enableOpenCross;
   bool           enableORB;
  };

struct OHLCDayLevels
  {
   datetime dayKey;       // Session day start timestamp
   double   pdh;          // Previous day high
   double   pdl;          // Previous day low
   double   pdo;          // Previous day open
   double   pdc;          // Previous day close
   double   dayOpen;      // Current session open
   double   mid;          // (pdh+pdl)/2
   double   orbHigh;      // Opening range high
   double   orbLow;       // Opening range low
   bool     orbReady;     // True after orbBars completed
   bool     valid;        // Levels ready to trade
  };

struct OHLCDayTracker
  {
   datetime curDayKey;
   double   curOpen;
   double   curHigh;
   double   curLow;
   double   curClose;
   int      barsInDay;
   // previous completed day
   double   prevOpen;
   double   prevHigh;
   double   prevLow;
   double   prevClose;
   bool     prevReady;
   // opening range of current day
   double   orbHigh;
   double   orbLow;
   bool     orbReady;
   // signal caps
   datetime lastBuyDay;
   datetime lastSellDay;
  };

struct OHLCSignal
  {
   bool                 valid;
   ENUM_OHLC_SIDE       side;
   ENUM_OHLC_SIGNAL_TYPE type;
   double               entry;
   double               stopLoss;
   double               takeProfit;
   double               riskReward;
   double               level;      // Reference level used
   datetime             dayKey;
  };

void OHLC_InitConfig(OHLCConfig &cfg,
                     const ENUM_OHLC_MODE mode = OHLC_MODE_ALL,
                     const int sessionStartHour = 0,
                     const int orbBars = 4,
                     const double touchTolAtr = 0.05,
                     const double minBreakAtr = 0.02,
                     const double rejectBodyRatio = 0.45,
                     const double stopAtrMult = 0.8,
                     const double minRR = 1.5,
                     const double tpRR = 2.0,
                     const bool useLevelTP = true,
                     const bool onePerDayPerSide = true)
  {
   cfg.mode = mode;
   cfg.sessionStartHour = sessionStartHour;
   cfg.orbBars = MathMax(1, orbBars);
   cfg.touchTolAtr = touchTolAtr;
   cfg.minBreakAtr = minBreakAtr;
   cfg.rejectBodyRatio = rejectBodyRatio;
   cfg.stopAtrMult = stopAtrMult;
   cfg.minRR = minRR;
   cfg.tpRR = tpRR;
   cfg.useLevelTP = useLevelTP;
   cfg.onePerDayPerSide = onePerDayPerSide;
   cfg.enableBreakout  = (mode == OHLC_MODE_BREAKOUT || mode == OHLC_MODE_ALL);
   cfg.enableRejection = (mode == OHLC_MODE_REJECTION || mode == OHLC_MODE_ALL);
   cfg.enableOpenCross = (mode == OHLC_MODE_OPEN || mode == OHLC_MODE_ALL);
   cfg.enableORB       = (mode == OHLC_MODE_BREAKOUT || mode == OHLC_MODE_ALL);
  }

void OHLC_ResetTracker(OHLCDayTracker &tr)
  {
   ZeroMemory(tr);
  }

datetime OHLC_SessionDayKey(const datetime barTime, const int sessionStartHour)
  {
   MqlDateTime dt;
   TimeToStruct(barTime, dt);
   // Shift backward if before session start so bars belong to previous session day
   datetime key = barTime - (datetime)(dt.hour * 3600 + dt.min * 60 + dt.sec);
   if(dt.hour < sessionStartHour)
      key -= 86400;
   key += (datetime)(sessionStartHour * 3600);
   return key;
  }

string OHLC_SignalTypeName(const ENUM_OHLC_SIGNAL_TYPE t)
  {
   switch(t)
     {
      case OHLC_SIG_PDH_BREAKOUT:    return "PDH_BO";
      case OHLC_SIG_PDL_BREAKOUT:    return "PDL_BO";
      case OHLC_SIG_OPEN_BREAK_BUY:  return "OPEN_BUY";
      case OHLC_SIG_OPEN_BREAK_SELL: return "OPEN_SELL";
      case OHLC_SIG_PDH_REJECTION:   return "PDH_REJ";
      case OHLC_SIG_PDL_REJECTION:   return "PDL_REJ";
      case OHLC_SIG_ORB_BREAK_BUY:   return "ORB_BUY";
      case OHLC_SIG_ORB_BREAK_SELL:  return "ORB_SELL";
      default:                       return "NONE";
     }
  }

bool OHLC_UpdateDay(OHLCDayTracker &tr,
                    const OHLCConfig &cfg,
                    const datetime barTime,
                    const double open_,
                    const double high,
                    const double low,
                    const double close,
                    OHLCDayLevels &levels)
  {
   ZeroMemory(levels);
   const datetime dayKey = OHLC_SessionDayKey(barTime, cfg.sessionStartHour);

   if(tr.curDayKey == 0)
     {
      tr.curDayKey = dayKey;
      tr.curOpen = open_;
      tr.curHigh = high;
      tr.curLow = low;
      tr.curClose = close;
      tr.barsInDay = 1;
      tr.orbHigh = high;
      tr.orbLow = low;
      tr.orbReady = (cfg.orbBars <= 1);
     }
   else if(dayKey != tr.curDayKey)
     {
      // Roll previous day
      tr.prevOpen = tr.curOpen;
      tr.prevHigh = tr.curHigh;
      tr.prevLow = tr.curLow;
      tr.prevClose = tr.curClose;
      tr.prevReady = (tr.prevHigh > 0.0 && tr.prevLow > 0.0);

      tr.curDayKey = dayKey;
      tr.curOpen = open_;
      tr.curHigh = high;
      tr.curLow = low;
      tr.curClose = close;
      tr.barsInDay = 1;
      tr.orbHigh = high;
      tr.orbLow = low;
      tr.orbReady = (cfg.orbBars <= 1);
     }
   else
     {
      tr.curHigh = MathMax(tr.curHigh, high);
      tr.curLow = MathMin(tr.curLow, low);
      tr.curClose = close;
      tr.barsInDay++;
      if(!tr.orbReady)
        {
         tr.orbHigh = MathMax(tr.orbHigh, high);
         tr.orbLow = MathMin(tr.orbLow, low);
         if(tr.barsInDay >= cfg.orbBars)
            tr.orbReady = true;
        }
     }

   levels.dayKey = tr.curDayKey;
   levels.dayOpen = tr.curOpen;
   levels.orbHigh = tr.orbHigh;
   levels.orbLow = tr.orbLow;
   levels.orbReady = tr.orbReady;

   if(tr.prevReady)
     {
      levels.pdh = tr.prevHigh;
      levels.pdl = tr.prevLow;
      levels.pdo = tr.prevOpen;
      levels.pdc = tr.prevClose;
      levels.mid = 0.5 * (levels.pdh + levels.pdl);
      levels.valid = true;
     }
   return levels.valid;
  }

bool OHLC_BuildTradePlan(const ENUM_OHLC_SIDE side,
                         const ENUM_OHLC_SIGNAL_TYPE type,
                         const double entry,
                         const double level,
                         const double atr,
                         const OHLCConfig &cfg,
                         const OHLCDayLevels &lv,
                         const datetime dayKey,
                         OHLCSignal &sig)
  {
   ZeroMemory(sig);
   if(atr <= 0.0 || entry <= 0.0)
      return false;

   const double stopDist = cfg.stopAtrMult * atr;
   double stop = 0.0;
   double tp = 0.0;

   if(side == OHLC_BUY)
     {
      stop = entry - stopDist;
      // Prefer structural TP toward mid / PDH / ORB high
      double structural = 0.0;
      if(cfg.useLevelTP)
        {
         if(type == OHLC_SIG_PDL_REJECTION || type == OHLC_SIG_OPEN_BREAK_BUY)
            structural = (lv.mid > entry) ? lv.mid : lv.pdh;
         else if(type == OHLC_SIG_ORB_BREAK_BUY)
            structural = lv.pdh;
         else if(type == OHLC_SIG_PDH_BREAKOUT)
            structural = entry + (lv.pdh - lv.pdl); // measured move
         if(structural > entry)
            tp = structural;
        }
      if(tp <= entry)
         tp = entry + cfg.tpRR * (entry - stop);
     }
   else
     {
      stop = entry + stopDist;
      double structural = 0.0;
      if(cfg.useLevelTP)
        {
         if(type == OHLC_SIG_PDH_REJECTION || type == OHLC_SIG_OPEN_BREAK_SELL)
            structural = (lv.mid < entry) ? lv.mid : lv.pdl;
         else if(type == OHLC_SIG_ORB_BREAK_SELL)
            structural = lv.pdl;
         else if(type == OHLC_SIG_PDL_BREAKOUT)
            structural = entry - (lv.pdh - lv.pdl);
         if(structural > 0.0 && structural < entry)
            tp = structural;
        }
      if(tp <= 0.0 || tp >= entry)
         tp = entry - cfg.tpRR * (stop - entry);
     }

   const double risk = MathAbs(entry - stop);
   const double reward = MathAbs(tp - entry);
   if(risk <= 0.0)
      return false;
   const double rr = reward / risk;
   if(rr < cfg.minRR)
     {
      // Force RR-based TP if structural target too close
      if(side == OHLC_BUY)
         tp = entry + cfg.tpRR * risk;
      else
         tp = entry - cfg.tpRR * risk;
     }

   const double rrFinal = MathAbs(tp - entry) / risk;
   if(rrFinal < cfg.minRR)
      return false;

   sig.valid = true;
   sig.side = side;
   sig.type = type;
   sig.entry = entry;
   sig.stopLoss = stop;
   sig.takeProfit = tp;
   sig.riskReward = rrFinal;
   sig.level = level;
   sig.dayKey = dayKey;
   return true;
  }

bool OHLC_AllowSide(OHLCDayTracker &tr,
                    const OHLCConfig &cfg,
                    const ENUM_OHLC_SIDE side,
                    const datetime dayKey)
  {
   if(!cfg.onePerDayPerSide)
      return true;
   if(side == OHLC_BUY)
      return (tr.lastBuyDay != dayKey);
   return (tr.lastSellDay != dayKey);
  }

void OHLC_MarkSide(OHLCDayTracker &tr, const ENUM_OHLC_SIDE side, const datetime dayKey)
  {
   if(side == OHLC_BUY)
      tr.lastBuyDay = dayKey;
   else
      tr.lastSellDay = dayKey;
  }

bool OHLC_EvaluateBar(OHLCDayTracker &tr,
                      const OHLCConfig &cfg,
                      const datetime barTime,
                      const double open_,
                      const double high,
                      const double low,
                      const double close,
                      const double prevClose,
                      const double atr,
                      OHLCSignal &sig)
  {
   ZeroMemory(sig);
   OHLCDayLevels lv;
   if(!OHLC_UpdateDay(tr, cfg, barTime, open_, high, low, close, lv))
      return false;
   if(atr <= 0.0)
      return false;

   // Skip first bar of day for open-cross / breakout noise (still builds ORB)
   const bool earlyBar = (tr.barsInDay <= 1);
   const double tol = cfg.touchTolAtr * atr;
   const double brk = cfg.minBreakAtr * atr;
   const double rng = high - low;
   const double body = MathAbs(close - open_);

   // --- PDH breakout (buy) ---
   if(cfg.enableBreakout && !earlyBar && OHLC_AllowSide(tr, cfg, OHLC_BUY, lv.dayKey))
     {
      if(prevClose <= lv.pdh + tol && close > lv.pdh + brk)
        {
         if(OHLC_BuildTradePlan(OHLC_BUY, OHLC_SIG_PDH_BREAKOUT, close, lv.pdh, atr, cfg, lv, lv.dayKey, sig))
           {
            OHLC_MarkSide(tr, OHLC_BUY, lv.dayKey);
            return true;
           }
        }
     }

   // --- PDL breakout (sell) ---
   if(cfg.enableBreakout && !earlyBar && OHLC_AllowSide(tr, cfg, OHLC_SELL, lv.dayKey))
     {
      if(prevClose >= lv.pdl - tol && close < lv.pdl - brk)
        {
         if(OHLC_BuildTradePlan(OHLC_SELL, OHLC_SIG_PDL_BREAKOUT, close, lv.pdl, atr, cfg, lv, lv.dayKey, sig))
           {
            OHLC_MarkSide(tr, OHLC_SELL, lv.dayKey);
            return true;
           }
        }
     }

   // --- Day Open cross ---
   if(cfg.enableOpenCross && !earlyBar)
     {
      if(OHLC_AllowSide(tr, cfg, OHLC_BUY, lv.dayKey) &&
         prevClose <= lv.dayOpen + tol && close > lv.dayOpen + brk)
        {
         if(OHLC_BuildTradePlan(OHLC_BUY, OHLC_SIG_OPEN_BREAK_BUY, close, lv.dayOpen, atr, cfg, lv, lv.dayKey, sig))
           {
            OHLC_MarkSide(tr, OHLC_BUY, lv.dayKey);
            return true;
           }
        }
      if(OHLC_AllowSide(tr, cfg, OHLC_SELL, lv.dayKey) &&
         prevClose >= lv.dayOpen - tol && close < lv.dayOpen - brk)
        {
         if(OHLC_BuildTradePlan(OHLC_SELL, OHLC_SIG_OPEN_BREAK_SELL, close, lv.dayOpen, atr, cfg, lv, lv.dayKey, sig))
           {
            OHLC_MarkSide(tr, OHLC_SELL, lv.dayKey);
            return true;
           }
        }
     }

   // --- PDH / PDL rejection ---
   if(cfg.enableRejection && !earlyBar && rng > 0.0 && (body / rng) >= cfg.rejectBodyRatio)
     {
      // Sell rejection at PDH: pierce then close back below
      if(OHLC_AllowSide(tr, cfg, OHLC_SELL, lv.dayKey) &&
         high >= lv.pdh - tol && close < lv.pdh - brk && close < open_)
        {
         if(OHLC_BuildTradePlan(OHLC_SELL, OHLC_SIG_PDH_REJECTION, close, lv.pdh, atr, cfg, lv, lv.dayKey, sig))
           {
            OHLC_MarkSide(tr, OHLC_SELL, lv.dayKey);
            return true;
           }
        }
      // Buy rejection at PDL
      if(OHLC_AllowSide(tr, cfg, OHLC_BUY, lv.dayKey) &&
         low <= lv.pdl + tol && close > lv.pdl + brk && close > open_)
        {
         if(OHLC_BuildTradePlan(OHLC_BUY, OHLC_SIG_PDL_REJECTION, close, lv.pdl, atr, cfg, lv, lv.dayKey, sig))
           {
            OHLC_MarkSide(tr, OHLC_BUY, lv.dayKey);
            return true;
           }
        }
     }

   // --- Opening Range breakout (only after ORB formed, on later bars) ---
   if(cfg.enableORB && lv.orbReady && tr.barsInDay > cfg.orbBars)
     {
      if(OHLC_AllowSide(tr, cfg, OHLC_BUY, lv.dayKey) &&
         prevClose <= lv.orbHigh + tol && close > lv.orbHigh + brk)
        {
         if(OHLC_BuildTradePlan(OHLC_BUY, OHLC_SIG_ORB_BREAK_BUY, close, lv.orbHigh, atr, cfg, lv, lv.dayKey, sig))
           {
            OHLC_MarkSide(tr, OHLC_BUY, lv.dayKey);
            return true;
           }
        }
      if(OHLC_AllowSide(tr, cfg, OHLC_SELL, lv.dayKey) &&
         prevClose >= lv.orbLow - tol && close < lv.orbLow - brk)
        {
         if(OHLC_BuildTradePlan(OHLC_SELL, OHLC_SIG_ORB_BREAK_SELL, close, lv.orbLow, atr, cfg, lv, lv.dayKey, sig))
           {
            OHLC_MarkSide(tr, OHLC_SELL, lv.dayKey);
            return true;
           }
        }
     }

   return false;
  }

#endif // INTRADAY_OHLC_LOGIC_MQH
//+------------------------------------------------------------------+
