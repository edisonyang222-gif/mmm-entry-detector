//+------------------------------------------------------------------+
//| MMXMLogic.mqh                                                     |
//| Shared ICT Market Maker Model detection logic for Indicator / EA  |
//+------------------------------------------------------------------+
#property copyright "MMM Entry Detector"
#property strict

#ifndef MMXM_LOGIC_MQH
#define MMXM_LOGIC_MQH

enum ENUM_MMXM_PHASE
  {
   MMXM_IDLE = 0,
   MMXM_ACCUMULATION = 1,
   MMXM_MANIPULATION = 2,
   MMXM_EXPANSION = 3,
   MMXM_ENTRY = 4,
   MMXM_INVALIDATED = 5
  };

enum ENUM_MMXM_SIDE
  {
   MMXM_BUY = 1,
   MMXM_SELL = -1
  };

enum ENUM_MMXM_FILL
  {
   MMXM_FILL_MIDPOINT = 0,
   MMXM_FILL_PROXIMAL = 1,
   MMXM_FILL_DISTAL = 2
  };

struct MMXMConfig
  {
   int               lookback;
   int               atrPeriod;
   double            maxRangeAtrMult;
   double            manipAtrMult;
   double            dispBodyRatio;
   double            dispAtrMult;
   double            minRR;
   double            stopBufAtrMult;
   ENUM_MMXM_FILL    entryFill;
  };

struct MMXMState
  {
   ENUM_MMXM_SIDE    side;
   ENUM_MMXM_PHASE   phase;
   double            accHigh;
   double            accLow;
   double            manipExtreme;
   int               expansionIndex;
   double            fvgTop;
   double            fvgBottom;
   bool              hasFvg;
  };

struct MMXMSignal
  {
   bool              valid;
   ENUM_MMXM_SIDE    side;
   double            entry;
   double            stopLoss;
   double            takeProfit;
   double            riskReward;
   double            fvgTop;
   double            fvgBottom;
   double            accHigh;
   double            accLow;
   double            manipExtreme;
  };

void MMXM_InitConfig(MMXMConfig &cfg,
                     const int lookback = 20,
                     const int atrPeriod = 14,
                     const double maxRangeAtrMult = 3.5,
                     const double manipAtrMult = 0.3,
                     const double dispBodyRatio = 0.65,
                     const double dispAtrMult = 0.8,
                     const double minRR = 1.5,
                     const double stopBufAtrMult = 0.05,
                     const ENUM_MMXM_FILL entryFill = MMXM_FILL_MIDPOINT)
  {
   cfg.lookback = lookback;
   cfg.atrPeriod = atrPeriod;
   cfg.maxRangeAtrMult = maxRangeAtrMult;
   cfg.manipAtrMult = manipAtrMult;
   cfg.dispBodyRatio = dispBodyRatio;
   cfg.dispAtrMult = dispAtrMult;
   cfg.minRR = minRR;
   cfg.stopBufAtrMult = stopBufAtrMult;
   cfg.entryFill = entryFill;
  }

void MMXM_ResetState(MMXMState &st, const ENUM_MMXM_SIDE side)
  {
   st.side = side;
   st.phase = MMXM_IDLE;
   st.accHigh = 0.0;
   st.accLow = 0.0;
   st.manipExtreme = 0.0;
   st.expansionIndex = -1;
   st.fvgTop = 0.0;
   st.fvgBottom = 0.0;
   st.hasFvg = false;
  }

bool MMXM_IsDisplacement(const double open_,
                         const double high,
                         const double low,
                         const double close,
                         const double atr,
                         const bool bullish,
                         const MMXMConfig &cfg)
  {
   const double rng = high - low;
   if(rng <= 0.0 || atr <= 0.0)
      return false;
   const double body = MathAbs(close - open_);
   if(body / rng < cfg.dispBodyRatio)
      return false;
   if(rng < cfg.dispAtrMult * atr)
      return false;
   return bullish ? (close > open_) : (close < open_);
  }

bool MMXM_DetectFVG(const double high2,
                    const double low2,
                    const double high0,
                    const double low0,
                    const ENUM_MMXM_SIDE side,
                    double &top,
                    double &bottom)
  {
   if(side == MMXM_BUY)
     {
      if(low0 > high2)
        {
         top = low0;
         bottom = high2;
         return true;
        }
     }
   else
     {
      if(high0 < low2)
        {
         top = low2;
         bottom = high0;
         return true;
        }
     }
   return false;
  }

double MMXM_EntryPrice(const MMXMState &st, const ENUM_MMXM_FILL fill)
  {
   const double proximal = (st.side == MMXM_BUY) ? st.fvgBottom : st.fvgTop;
   const double distal   = (st.side == MMXM_BUY) ? st.fvgTop : st.fvgBottom;
   const double mid      = 0.5 * (st.fvgTop + st.fvgBottom);
   if(fill == MMXM_FILL_PROXIMAL)
      return proximal;
   if(fill == MMXM_FILL_DISTAL)
      return distal;
   return mid;
  }

bool MMXM_BuildSignal(const MMXMState &st,
                      const MMXMConfig &cfg,
                      const double atr,
                      MMXMSignal &sig)
  {
   ZeroMemory(sig);
   if(!st.hasFvg)
      return false;

   ENUM_MMXM_FILL fills[2];
   fills[0] = cfg.entryFill;
   fills[1] = MMXM_FILL_PROXIMAL;

   const int n = (cfg.entryFill == MMXM_FILL_PROXIMAL) ? 1 : 2;
   for(int i = 0; i < n; i++)
     {
      const double entry = MMXM_EntryPrice(st, fills[i]);
      const double buffer = (atr > 0.0) ? cfg.stopBufAtrMult * atr : 0.0;
      double stop = 0.0;
      double tp = 0.0;
      double risk = 0.0;
      double reward = 0.0;

      if(st.side == MMXM_BUY)
        {
         stop = st.manipExtreme - buffer;
         const double depth = st.accHigh - st.manipExtreme;
         const double measured = st.accHigh + depth;
         const double rangeProj = st.accHigh + (st.accHigh - st.accLow);
         tp = MathMax(measured, rangeProj);
         risk = entry - stop;
         reward = tp - entry;
        }
      else
        {
         stop = st.manipExtreme + buffer;
         const double depth = st.manipExtreme - st.accLow;
         const double measured = st.accLow - depth;
         const double rangeProj = st.accLow - (st.accHigh - st.accLow);
         tp = MathMin(measured, rangeProj);
         risk = stop - entry;
         reward = entry - tp;
        }

      if(risk <= 0.0 || reward <= 0.0)
         continue;
      const double rr = reward / risk;
      if(rr >= cfg.minRR)
        {
         sig.valid = true;
         sig.side = st.side;
         sig.entry = entry;
         sig.stopLoss = stop;
         sig.takeProfit = tp;
         sig.riskReward = rr;
         sig.fvgTop = st.fvgTop;
         sig.fvgBottom = st.fvgBottom;
         sig.accHigh = st.accHigh;
         sig.accLow = st.accLow;
         sig.manipExtreme = st.manipExtreme;
         return true;
        }
     }
   return false;
  }

// Process one completed bar for one model side.
// Arrays are series-style: index 0 = current/latest bar.
bool MMXM_Step(MMXMState &st,
               const MMXMConfig &cfg,
               const int barIndex,
               const double open0,
               const double high0,
               const double low0,
               const double close0,
               const double high2,
               const double low2,
               const double atr,
               const double rangeHigh,
               const double rangeLow,
               MMXMSignal &outSignal)
  {
   ZeroMemory(outSignal);
   outSignal.valid = false;

   if(atr <= 0.0 || rangeHigh <= rangeLow)
      return false;

   if(st.phase == MMXM_ENTRY || st.phase == MMXM_INVALIDATED)
      MMXM_ResetState(st, st.side);

   const double width = rangeHigh - rangeLow;
   const bool isTight = (width <= cfg.maxRangeAtrMult * atr);
   const double frozenHi = st.accHigh;
   const double frozenLo = st.accLow;
   const bool hasFrozen = (st.phase == MMXM_ACCUMULATION && frozenHi > frozenLo);

   if(st.phase == MMXM_IDLE || st.phase == MMXM_ACCUMULATION)
     {
      bool manip = false;
      if(hasFrozen)
        {
         const double thr = cfg.manipAtrMult * atr;
         manip = (st.side == MMXM_BUY) ? (low0 < frozenLo - thr)
                                       : (high0 > frozenHi + thr);
        }

      if(manip)
        {
         st.phase = MMXM_MANIPULATION;
         st.accHigh = frozenHi;
         st.accLow = frozenLo;
         st.manipExtreme = (st.side == MMXM_BUY) ? low0 : high0;
         st.hasFvg = false;
         return false;
        }

      if(isTight)
        {
         st.phase = MMXM_ACCUMULATION;
         st.accHigh = rangeHigh;
         st.accLow = rangeLow;
        }
      else
        {
         MMXM_ResetState(st, st.side);
        }
      return false;
     }

   if(st.phase == MMXM_MANIPULATION)
     {
      if(st.side == MMXM_BUY)
        {
         if(low0 < st.manipExtreme)
            st.manipExtreme = low0;
        }
      else
        {
         if(high0 > st.manipExtreme)
            st.manipExtreme = high0;
        }

      const bool bullish = (st.side == MMXM_BUY);
      const bool disp = MMXM_IsDisplacement(open0, high0, low0, close0, atr, bullish, cfg);
      const bool through = bullish ? (close0 > st.accHigh) : (close0 < st.accLow);

      if(disp && through)
        {
         st.phase = MMXM_EXPANSION;
         st.expansionIndex = barIndex;
         double top, bottom;
         if(MMXM_DetectFVG(high2, low2, high0, low0, st.side, top, bottom))
           {
            st.fvgTop = top;
            st.fvgBottom = bottom;
            st.hasFvg = true;
            if(MMXM_BuildSignal(st, cfg, atr, outSignal))
              {
               st.phase = MMXM_ENTRY;
               return true;
              }
            st.phase = MMXM_INVALIDATED;
           }
         return false;
        }

      const double thr3 = cfg.manipAtrMult * atr * 3.0;
      if(st.side == MMXM_BUY && close0 < st.accLow - thr3)
         st.phase = MMXM_INVALIDATED;
      if(st.side == MMXM_SELL && close0 > st.accHigh + thr3)
         st.phase = MMXM_INVALIDATED;
      return false;
     }

   if(st.phase == MMXM_EXPANSION)
     {
      if(!st.hasFvg)
        {
         double top, bottom;
         if(MMXM_DetectFVG(high2, low2, high0, low0, st.side, top, bottom))
           {
            st.fvgTop = top;
            st.fvgBottom = bottom;
            st.hasFvg = true;
            if(MMXM_BuildSignal(st, cfg, atr, outSignal))
              {
               st.phase = MMXM_ENTRY;
               return true;
              }
            st.phase = MMXM_INVALIDATED;
            return false;
           }
         if(st.expansionIndex >= 0 && (barIndex - st.expansionIndex) >= 3)
            st.phase = MMXM_INVALIDATED;
        }
     }
   return false;
  }

#endif // MMXM_LOGIC_MQH
