//+------------------------------------------------------------------+
//| AW_Inst_Safety.mqh                                               |
//| Hard safety rails — forbidden techniques                         |
//+------------------------------------------------------------------+
#ifndef AW_INST_SAFETY_MQH
#define AW_INST_SAFETY_MQH

class CAWInstSafety
{
public:
   // Hardcoded policy — not overridable by "AI" or recovery modes
   static bool ForbidMartingale()     { return true; }
   static bool ForbidGrid()            { return true; }
   static bool ForbidRecoveryTrading() { return true; }
   static bool ForbidIncreaseLotAfterLoss() { return true; }
   static bool ForbidMlParamMutation() { return true; }

   // Lot calculation: fixed fractional risk from SL distance ONLY
   // Never scales up after losses; optional riskMult <= 1 from DD protection
   static double CalcLot(const string symbol,
                         const double equity,
                         const double riskPercent,   // e.g. 0.5 means 0.5%
                         const double riskMult,      // from DD module, <= 1
                         const double entry,
                         const double sl)
   {
      if(riskPercent <= 0.0 || riskMult <= 0.0) return 0.0;
      if(ForbidIncreaseLotAfterLoss() && riskMult > 1.0) return 0.0; // safety

      const double dist = MathAbs(entry - sl);
      if(dist <= 0.0) return 0.0;

      const double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      const double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      const double volMin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      const double volMax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      const double volStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      if(tickSize <= 0.0 || tickValue <= 0.0 || volStep <= 0.0) return 0.0;

      const double riskMoney = equity * (riskPercent / 100.0) * MathMin(1.0, riskMult);
      const double moneyPerLot = (dist / tickSize) * tickValue;
      if(moneyPerLot <= 0.0) return 0.0;

      double lots = riskMoney / moneyPerLot;
      lots = MathFloor(lots / volStep) * volStep;
      if(lots < volMin) return 0.0;
      if(lots > volMax) lots = volMax;
      return NormalizeDouble(lots, 2);
   }

   static bool ValidateOrderRequest(const double lots, const double lastLossLots)
   {
      if(lots <= 0.0) return false;
      // Block any attempt to increase size after a losing trade
      if(ForbidIncreaseLotAfterLoss() && lastLossLots > 0.0 && lots > lastLossLots + 1e-8)
      {
         Print("[AW Safety] Blocked lot increase after loss");
         return false;
      }
      return true;
   }
};

#endif
