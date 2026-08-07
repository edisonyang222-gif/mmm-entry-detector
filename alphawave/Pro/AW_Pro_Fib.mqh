//+------------------------------------------------------------------+
//| AW_Pro_Fib.mqh                                                   |
//| Alpha Wave Pro — Fib retracement zone (closed-bar OTE style)     |
//+------------------------------------------------------------------+
#ifndef AW_PRO_FIB_MQH
#define AW_PRO_FIB_MQH
#include "AW_Pro_Defines.mqh"
#include "AW_Pro_Structure.mqh"

class CAWProFib
{
private:
   double m_fibLow;   // e.g. 0.618
   double m_fibHigh;  // e.g. 0.786

public:
   void Init(const double fibLow, const double fibHigh)
   {
      m_fibLow = MathMin(fibLow, fibHigh);
      m_fibHigh = MathMax(fibLow, fibHigh);
   }

   bool InBuyZone(const CAWProStructure &st, double &outLevel) const
   {
      const AWProSwing hi = st.LastHigh();
      const AWProSwing lo = st.LastLow();
      if(hi.price <= 0.0 || lo.price <= 0.0 || hi.price <= lo.price)
         return false;
      // For buy OTE: impulse up then pullback — use last low->high range if high is more recent
      double legLow = lo.price;
      double legHigh = hi.price;
      const double range = legHigh - legLow;
      if(range <= 0.0) return false;
      const double zLow = legHigh - range * m_fibHigh;
      const double zHigh = legHigh - range * m_fibLow;
      const double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
      const double l1 = iLow(_Symbol, PERIOD_CURRENT, 1);
      outLevel = (zLow + zHigh) * 0.5;
      return (l1 <= zHigh && c1 >= zLow);
   }

   bool InSellZone(const CAWProStructure &st, double &outLevel) const
   {
      const AWProSwing hi = st.LastHigh();
      const AWProSwing lo = st.LastLow();
      if(hi.price <= 0.0 || lo.price <= 0.0 || hi.price <= lo.price)
         return false;
      double legLow = lo.price;
      double legHigh = hi.price;
      const double range = legHigh - legLow;
      if(range <= 0.0) return false;
      const double zLow = legLow + range * m_fibLow;
      const double zHigh = legLow + range * m_fibHigh;
      const double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
      const double h1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
      outLevel = (zLow + zHigh) * 0.5;
      return (h1 >= zLow && c1 <= zHigh);
   }
};

#endif
