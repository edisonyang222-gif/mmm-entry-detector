//+------------------------------------------------------------------+
//| AW_Pro_Structure.mqh                                             |
//| Alpha Wave Pro — M15/H1 swing structure, BOS, CHoCH              |
//| Signals use CLOSED bars only (shift >= 1) — no look-ahead        |
//+------------------------------------------------------------------+
#ifndef AW_PRO_STRUCTURE_MQH
#define AW_PRO_STRUCTURE_MQH
#include "AW_Pro_Defines.mqh"

class CAWProStructure
{
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_tf;
   int m_swingLeft;
   int m_swingRight;
   int m_lookback;

   AWProSwing m_lastHigh;
   AWProSwing m_lastLow;
   AWProSwing m_prevHigh;
   AWProSwing m_prevLow;
   ENUM_AW_DIR m_bias; // last confirmed structure bias

public:
   CAWProStructure(): m_symbol(_Symbol), m_tf(PERIOD_CURRENT),
      m_swingLeft(2), m_swingRight(2), m_lookback(80), m_bias(AW_DIR_NONE)
   {
      ZeroMemory(m_lastHigh); ZeroMemory(m_lastLow);
      ZeroMemory(m_prevHigh); ZeroMemory(m_prevLow);
   }

   void Init(const string symbol, const ENUM_TIMEFRAMES tf,
             const int swingLeft, const int swingRight, const int lookback)
   {
      m_symbol = symbol;
      m_tf = tf;
      m_swingLeft = MathMax(1, swingLeft);
      m_swingRight = MathMax(1, swingRight);
      m_lookback = MathMax(20, lookback);
   }

   ENUM_AW_DIR Bias() const { return m_bias; }
   AWProSwing LastHigh() const { return m_lastHigh; }
   AWProSwing LastLow()  const { return m_lastLow; }

   // Update using only confirmed swings (right side fully closed)
   void Update()
   {
      const int bars = Bars(m_symbol, m_tf);
      if(bars < m_lookback + m_swingLeft + m_swingRight + 5)
         return;

      // Scan from older to newer; pivot at shift i requires i-right >= 1 (closed)
      for(int i = m_lookback; i >= m_swingRight + 1; --i)
      {
         if(IsSwingHigh(i))
         {
            m_prevHigh = m_lastHigh;
            m_lastHigh.bar = i;
            m_lastHigh.price = iHigh(m_symbol, m_tf, i);
            m_lastHigh.time = iTime(m_symbol, m_tf, i);
            m_lastHigh.isHigh = true;
         }
         if(IsSwingLow(i))
         {
            m_prevLow = m_lastLow;
            m_lastLow.bar = i;
            m_lastLow.price = iLow(m_symbol, m_tf, i);
            m_lastLow.time = iTime(m_symbol, m_tf, i);
            m_lastLow.isHigh = false;
         }
      }

      // Structure bias from last closed bar break
      const double c1 = iClose(m_symbol, m_tf, 1);
      if(m_lastHigh.price > 0.0 && c1 > m_lastHigh.price)
         m_bias = AW_DIR_BUY;
      else if(m_lastLow.price > 0.0 && c1 < m_lastLow.price)
         m_bias = AW_DIR_SELL;
   }

   bool IsBos(const ENUM_AW_DIR dir) const
   {
      const double c1 = iClose(m_symbol, m_tf, 1);
      const double c2 = iClose(m_symbol, m_tf, 2);
      if(dir == AW_DIR_BUY)
         return (m_lastHigh.price > 0.0 && c2 <= m_lastHigh.price && c1 > m_lastHigh.price);
      if(dir == AW_DIR_SELL)
         return (m_lastLow.price > 0.0 && c2 >= m_lastLow.price && c1 < m_lastLow.price);
      return false;
   }

   bool IsChoch(const ENUM_AW_DIR dir) const
   {
      // CHoCH: break opposite to previous bias on closed bar
      if(dir == AW_DIR_BUY)
         return (m_bias == AW_DIR_SELL && IsBos(AW_DIR_BUY));
      if(dir == AW_DIR_SELL)
         return (m_bias == AW_DIR_BUY && IsBos(AW_DIR_SELL));
      return false;
   }

private:
   bool IsSwingHigh(const int shift) const
   {
      const double p = iHigh(m_symbol, m_tf, shift);
      for(int k = 1; k <= m_swingLeft; ++k)
         if(iHigh(m_symbol, m_tf, shift + k) >= p) return false;
      for(int k = 1; k <= m_swingRight; ++k)
         if(iHigh(m_symbol, m_tf, shift - k) > p) return false;
      return true;
   }

   bool IsSwingLow(const int shift) const
   {
      const double p = iLow(m_symbol, m_tf, shift);
      for(int k = 1; k <= m_swingLeft; ++k)
         if(iLow(m_symbol, m_tf, shift + k) <= p) return false;
      for(int k = 1; k <= m_swingRight; ++k)
         if(iLow(m_symbol, m_tf, shift - k) < p) return false;
      return true;
   }
};

#endif
