//+------------------------------------------------------------------+
//| AW_Pro_Liquidity.mqh                                             |
//| Alpha Wave Pro — Liquidity sweep detection (closed-bar only)     |
//+------------------------------------------------------------------+
#ifndef AW_PRO_LIQUIDITY_MQH
#define AW_PRO_LIQUIDITY_MQH
#include "AW_Pro_Defines.mqh"

class CAWProLiquidity
{
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_tf;
   int m_lookback;
   double m_wickMinAtr;

public:
   void Init(const string symbol, const ENUM_TIMEFRAMES tf,
             const int lookback, const double wickMinAtr)
   {
      m_symbol = symbol;
      m_tf = tf;
      m_lookback = MathMax(5, lookback);
      m_wickMinAtr = MathMax(0.0, wickMinAtr);
   }

   // Buy-side liquidity sweep: take prior lows then close back above
   bool SweepBuy(const double atr) const
   {
      if(atr <= 0.0) return false;
      const double priorLow = LowestLow(2, m_lookback);
      const double low1 = iLow(m_symbol, m_tf, 1);
      const double close1 = iClose(m_symbol, m_tf, 1);
      const double open1 = iOpen(m_symbol, m_tf, 1);
      const double wick = MathMin(open1, close1) - low1;
      return (low1 < priorLow && close1 > priorLow && wick >= m_wickMinAtr * atr);
   }

   // Sell-side liquidity sweep: take prior highs then close back below
   bool SweepSell(const double atr) const
   {
      if(atr <= 0.0) return false;
      const double priorHigh = HighestHigh(2, m_lookback);
      const double high1 = iHigh(m_symbol, m_tf, 1);
      const double close1 = iClose(m_symbol, m_tf, 1);
      const double open1 = iOpen(m_symbol, m_tf, 1);
      const double wick = high1 - MathMax(open1, close1);
      return (high1 > priorHigh && close1 < priorHigh && wick >= m_wickMinAtr * atr);
   }

   int SweepQuality(const ENUM_AW_DIR dir, const double atr) const
   {
      // 0-20 points helper for Institutional score
      if(dir == AW_DIR_BUY && SweepBuy(atr))
      {
         const double priorLow = LowestLow(2, m_lookback);
         const double penetration = (priorLow - iLow(m_symbol, m_tf, 1)) / atr;
         return (int)MathMin(20.0, 8.0 + penetration * 6.0);
      }
      if(dir == AW_DIR_SELL && SweepSell(atr))
      {
         const double priorHigh = HighestHigh(2, m_lookback);
         const double penetration = (iHigh(m_symbol, m_tf, 1) - priorHigh) / atr;
         return (int)MathMin(20.0, 8.0 + penetration * 6.0);
      }
      return 0;
   }

private:
   double LowestLow(const int fromShift, const int count) const
   {
      double v = iLow(m_symbol, m_tf, fromShift);
      for(int i = fromShift + 1; i < fromShift + count; ++i)
         v = MathMin(v, iLow(m_symbol, m_tf, i));
      return v;
   }
   double HighestHigh(const int fromShift, const int count) const
   {
      double v = iHigh(m_symbol, m_tf, fromShift);
      for(int i = fromShift + 1; i < fromShift + count; ++i)
         v = MathMax(v, iHigh(m_symbol, m_tf, i));
      return v;
   }
};

#endif
