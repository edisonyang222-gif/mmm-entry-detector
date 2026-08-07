//+------------------------------------------------------------------+
//| AW_Pro_Confirmations.mqh                                         |
//| Alpha Wave Pro — candle confirmations (closed bar only)          |
//+------------------------------------------------------------------+
#ifndef AW_PRO_CONFIRMATIONS_MQH
#define AW_PRO_CONFIRMATIONS_MQH

class CAWProConfirmations
{
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_tf;

public:
   void Init(const string symbol, const ENUM_TIMEFRAMES tf)
   {
      m_symbol = symbol;
      m_tf = tf;
   }

   bool BullEngulfing() const
   {
      const double o1 = iOpen(m_symbol, m_tf, 1);
      const double c1 = iClose(m_symbol, m_tf, 1);
      const double o2 = iOpen(m_symbol, m_tf, 2);
      const double c2 = iClose(m_symbol, m_tf, 2);
      return (c2 < o2 && c1 > o1 && c1 >= o2 && o1 <= c2);
   }

   bool BearEngulfing() const
   {
      const double o1 = iOpen(m_symbol, m_tf, 1);
      const double c1 = iClose(m_symbol, m_tf, 1);
      const double o2 = iOpen(m_symbol, m_tf, 2);
      const double c2 = iClose(m_symbol, m_tf, 2);
      return (c2 > o2 && c1 < o1 && c1 <= o2 && o1 >= c2);
   }

   int StrengthBuy() const
   {
      int s = 0;
      if(BullEngulfing()) s += 3;
      const double o1 = iOpen(m_symbol, m_tf, 1);
      const double c1 = iClose(m_symbol, m_tf, 1);
      const double h1 = iHigh(m_symbol, m_tf, 1);
      const double l1 = iLow(m_symbol, m_tf, 1);
      const double range = h1 - l1;
      if(range > 0.0 && (c1 - l1) / range >= 0.7) s += 1;
      if(c1 > iClose(m_symbol, m_tf, 2)) s += 1;
      return MathMin(5, s);
   }

   int StrengthSell() const
   {
      int s = 0;
      if(BearEngulfing()) s += 3;
      const double o1 = iOpen(m_symbol, m_tf, 1);
      const double c1 = iClose(m_symbol, m_tf, 1);
      const double h1 = iHigh(m_symbol, m_tf, 1);
      const double l1 = iLow(m_symbol, m_tf, 1);
      const double range = h1 - l1;
      if(range > 0.0 && (h1 - c1) / range >= 0.7) s += 1;
      if(c1 < iClose(m_symbol, m_tf, 2)) s += 1;
      return MathMin(5, s);
   }
};

#endif
