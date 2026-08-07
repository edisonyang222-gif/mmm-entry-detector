//+------------------------------------------------------------------+
//| AW_Inst_Drawdown.mqh                                             |
//| Drawdown Protection — Daily / Weekly / Monthly                   |
//| Level1: reduce risk | Level2: A+ only | Level3: stop auto        |
//| Equity peaks tracked WITHOUT look-ahead; resets by calendar TZ   |
//+------------------------------------------------------------------+
#ifndef AW_INST_DRAWDOWN_MQH
#define AW_INST_DRAWDOWN_MQH
#include "AW_Inst_Defines.mqh"

struct AWDrawdownConfig
{
   double dailyDdLevel1Pct;
   double dailyDdLevel2Pct;
   double dailyDdLevel3Pct;
   double weeklyDdLevel1Pct;
   double weeklyDdLevel2Pct;
   double weeklyDdLevel3Pct;
   double monthlyDdLevel1Pct;
   double monthlyDdLevel2Pct;
   double monthlyDdLevel3Pct;
   double riskMultLevel1;     // e.g. 0.5
   int    gmtOffsetHours;     // session/day reset timezone offset from GMT
};

struct AWDrawdownState
{
   double dayStartEquity;
   double weekStartEquity;
   double monthStartEquity;
   double dailyDdPct;
   double weeklyDdPct;
   double monthlyDdPct;
   ENUM_AW_DD_LEVEL level;
   ENUM_AW_EA_STATUS status;
   double riskMult;
   int dayKey, weekKey, monthKey;
};

class CAWInstDrawdown
{
private:
   AWDrawdownConfig m_cfg;
   AWDrawdownState  m_st;

public:
   CAWInstDrawdown() { ZeroMemory(m_st); m_st.riskMult = 1.0; m_st.status = AW_STATUS_NORMAL; }

   void Init(const AWDrawdownConfig &cfg, const double equityNow)
   {
      m_cfg = cfg;
      int keys[3];
      ComputeKeys(keys);
      m_st.dayKey = keys[0];
      m_st.weekKey = keys[1];
      m_st.monthKey = keys[2];
      m_st.dayStartEquity = equityNow;
      m_st.weekStartEquity = equityNow;
      m_st.monthStartEquity = equityNow;
      m_st.riskMult = 1.0;
      m_st.level = AW_DD_OK;
      m_st.status = AW_STATUS_NORMAL;
   }

   AWDrawdownState State() const { return m_st; }

   void Update(const double equityNow)
   {
      int keys[3];
      ComputeKeys(keys);
      // Daily reset bug prevention: compare date keys in configured TZ, not server rollover alone
      if(keys[0] != m_st.dayKey)
      {
         m_st.dayKey = keys[0];
         m_st.dayStartEquity = equityNow;
      }
      if(keys[1] != m_st.weekKey)
      {
         m_st.weekKey = keys[1];
         m_st.weekStartEquity = equityNow;
      }
      if(keys[2] != m_st.monthKey)
      {
         m_st.monthKey = keys[2];
         m_st.monthStartEquity = equityNow;
      }

      m_st.dailyDdPct = DdPct(m_st.dayStartEquity, equityNow);
      m_st.weeklyDdPct = DdPct(m_st.weekStartEquity, equityNow);
      m_st.monthlyDdPct = DdPct(m_st.monthStartEquity, equityNow);

      ENUM_AW_DD_LEVEL lvl = AW_DD_OK;
      if(Hit(m_st.dailyDdPct, m_cfg.dailyDdLevel3Pct) ||
         Hit(m_st.weeklyDdPct, m_cfg.weeklyDdLevel3Pct) ||
         Hit(m_st.monthlyDdPct, m_cfg.monthlyDdLevel3Pct))
         lvl = AW_DD_LEVEL3;
      else if(Hit(m_st.dailyDdPct, m_cfg.dailyDdLevel2Pct) ||
              Hit(m_st.weeklyDdPct, m_cfg.weeklyDdLevel2Pct) ||
              Hit(m_st.monthlyDdPct, m_cfg.monthlyDdLevel2Pct))
         lvl = AW_DD_LEVEL2;
      else if(Hit(m_st.dailyDdPct, m_cfg.dailyDdLevel1Pct) ||
              Hit(m_st.weeklyDdPct, m_cfg.weeklyDdLevel1Pct) ||
              Hit(m_st.monthlyDdPct, m_cfg.monthlyDdLevel1Pct))
         lvl = AW_DD_LEVEL1;

      m_st.level = lvl;
      switch(lvl)
      {
         case AW_DD_LEVEL1:
            m_st.status = AW_STATUS_REDUCED_RISK;
            m_st.riskMult = m_cfg.riskMultLevel1;
            break;
         case AW_DD_LEVEL2:
            m_st.status = AW_STATUS_A_PLUS_ONLY;
            m_st.riskMult = m_cfg.riskMultLevel1;
            break;
         case AW_DD_LEVEL3:
            m_st.status = AW_STATUS_STOPPED;
            m_st.riskMult = 0.0;
            break;
         default:
            m_st.status = AW_STATUS_NORMAL;
            m_st.riskMult = 1.0;
            break;
      }
   }

private:
   bool Hit(const double dd, const double thr) const { return (thr > 0.0 && dd >= thr); }

   double DdPct(const double startEq, const double now) const
   {
      if(startEq <= 0.0) return 0.0;
      if(now >= startEq) return 0.0;
      return 100.0 * (startEq - now) / startEq;
   }

   void ComputeKeys(int &keys[])
   {
      // keys[0]=YYYYMMDD, keys[1]=YYYYWW, keys[2]=YYYYMM in configured GMT offset
      const datetime adjusted = TimeGMT() + m_cfg.gmtOffsetHours * 3600;
      MqlDateTime dt;
      TimeToStruct(adjusted, dt);
      keys[0] = dt.year * 10000 + dt.mon * 100 + dt.day;
      // ISO-like week number approximation
      const int week = (dt.day_of_year - 1) / 7 + 1;
      keys[1] = dt.year * 100 + week;
      keys[2] = dt.year * 100 + dt.mon;
   }
};

#endif
