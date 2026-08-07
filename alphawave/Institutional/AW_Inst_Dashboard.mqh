//+------------------------------------------------------------------+
//| AW_Inst_Dashboard.mqh                                            |
//| Institutional Dashboard (chart comment / label panel)            |
//+------------------------------------------------------------------+
#ifndef AW_INST_DASHBOARD_MQH
#define AW_INST_DASHBOARD_MQH
#include "AW_Inst_Defines.mqh"
#include "AW_Inst_Regime.mqh"
#include "AW_Inst_TradeScore.mqh"
#include "AW_Inst_Drawdown.mqh"
#include "AW_Inst_SetupDB.mqh"

class CAWInstDashboard
{
private:
   string m_prefix;

public:
   CAWInstDashboard(): m_prefix("AW_INST_") {}

   void Render(const AWRegimeState &reg,
               const AWDrawdownState &dd,
               const AWScoreResult &lastScore,
               const string currentSetupPerf,
               const string eaExtra)
   {
      string body = "";
      body += "===== Alpha Wave Institutional =====\n";
      body += "Market Regime : " + AW_RegimeName(reg.regime) + "\n";
      body += StringFormat("ADX=%.1f ATR_ratio=%.2f SessRange/ATR=%.2f\n",
                           reg.adx, reg.atrRatio, reg.sessionRangeAtr);
      body += "EA Status     : " + AW_StatusName(dd.status) + "\n";
      body += "Risk Mode     : " + StringFormat("x%.2f", dd.riskMult) + "\n";
      body += "Trade Score   : " + IntegerToString(lastScore.score) + " (" + AW_GradeName(lastScore.grade) + ")\n";
      body += "Min Required  : " + IntegerToString(lastScore.minRequired) + "\n";
      body += StringFormat("Daily DD      : %.2f%%\n", dd.dailyDdPct);
      body += StringFormat("Weekly DD     : %.2f%%\n", dd.weeklyDdPct);
      body += StringFormat("Monthly DD    : %.2f%%\n", dd.monthlyDdPct);
      body += "Setup Perf    : " + currentSetupPerf + "\n";
      if(StringLen(eaExtra) > 0)
         body += eaExtra + "\n";
      body += "Priority: DD control > Expectancy > PF > Stability > Net profit\n";
      Comment(body);
   }

   void Clear() { Comment(""); }
};

#endif
