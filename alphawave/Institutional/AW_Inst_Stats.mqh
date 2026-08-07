//+------------------------------------------------------------------+
//| AW_Inst_Stats.mqh                                                |
//| Performance Statistics — overall + breakdown dimensions          |
//| Updated ONLY on trade close (no floating PnL lookahead)          |
//+------------------------------------------------------------------+
#ifndef AW_INST_STATS_MQH
#define AW_INST_STATS_MQH
#include "AW_Inst_Defines.mqh"
#include "../Pro/AW_Pro_Defines.mqh"

struct AWTradeRecord
{
   ulong            ticket;
   datetime         openTime;
   datetime         closeTime;
   ENUM_AW_DIR      direction;
   ENUM_AW_SETUP_ID setupId;
   ENUM_AW_GRADE    grade;
   ENUM_AW_REGIME   regime;
   int              score;
   int              confirmStrength;
   string           sessionName;
   int              dayOfWeek; // 0=Sun
   int              hour;
   double           riskMoney;
   double           pnl;
   double           rMultiple; // pnl / riskMoney
};

struct AWPerfSlice
{
   string name;
   int    trades;
   int    wins;
   int    losses;
   double grossWin;
   double grossLoss; // absolute
   double sumR;
   int    maxConsecWin;
   int    maxConsecLoss;
   int    curConsecWin;
   int    curConsecLoss;
   double maxDd;
   double equityCurve; // relative from 0
   double peak;

   double WinRate() const { return trades > 0 ? 100.0 * wins / trades : 0.0; }
   double ProfitFactor() const { return grossLoss > 0.0 ? grossWin / grossLoss : (grossWin > 0.0 ? 99.0 : 0.0); }
   double Expectancy() const { return trades > 0 ? (grossWin - grossLoss) / trades : 0.0; }
   double AvgR() const { return trades > 0 ? sumR / trades : 0.0; }
};

class CAWInstStats
{
private:
   AWTradeRecord m_trades[];
   AWPerfSlice   m_overall;

public:
   CAWInstStats() { ResetSlice(m_overall, "ALL"); }

   void Reset()
   {
      ArrayResize(m_trades, 0);
      ResetSlice(m_overall, "ALL");
   }

   AWPerfSlice Overall() const { return m_overall; }
   int TradeCount() const { return ArraySize(m_trades); }

   void OnTradeClosed(const AWTradeRecord &rec)
   {
      const int n = ArraySize(m_trades);
      ArrayResize(m_trades, n + 1);
      m_trades[n] = rec;
      Apply(m_overall, rec);
   }

   AWPerfSlice BySession(const string sessionName)
   {
      AWPerfSlice s; ResetSlice(s, sessionName);
      for(int i = 0; i < ArraySize(m_trades); ++i)
         if(m_trades[i].sessionName == sessionName) Apply(s, m_trades[i]);
      return s;
   }

   AWPerfSlice ByDirection(const ENUM_AW_DIR dir)
   {
      AWPerfSlice s; ResetSlice(s, dir == AW_DIR_BUY ? "BUY" : "SELL");
      for(int i = 0; i < ArraySize(m_trades); ++i)
         if(m_trades[i].direction == dir) Apply(s, m_trades[i]);
      return s;
   }

   AWPerfSlice BySetup(const ENUM_AW_SETUP_ID id)
   {
      AWPerfSlice s; ResetSlice(s, AW_Pro_SetupName(id));
      for(int i = 0; i < ArraySize(m_trades); ++i)
         if(m_trades[i].setupId == id) Apply(s, m_trades[i]);
      return s;
   }

   AWPerfSlice ByGrade(const ENUM_AW_GRADE g)
   {
      AWPerfSlice s; ResetSlice(s, AW_GradeName(g));
      for(int i = 0; i < ArraySize(m_trades); ++i)
         if(m_trades[i].grade == g) Apply(s, m_trades[i]);
      return s;
   }

   AWPerfSlice ByRegime(const ENUM_AW_REGIME r)
   {
      AWPerfSlice s; ResetSlice(s, AW_RegimeName(r));
      for(int i = 0; i < ArraySize(m_trades); ++i)
         if(m_trades[i].regime == r) Apply(s, m_trades[i]);
      return s;
   }

   AWPerfSlice ByDayOfWeek(const int dow)
   {
      AWPerfSlice s; ResetSlice(s, StringFormat("DOW%d", dow));
      for(int i = 0; i < ArraySize(m_trades); ++i)
         if(m_trades[i].dayOfWeek == dow) Apply(s, m_trades[i]);
      return s;
   }

   AWPerfSlice ByHour(const int hour)
   {
      AWPerfSlice s; ResetSlice(s, StringFormat("H%02d", hour));
      for(int i = 0; i < ArraySize(m_trades); ++i)
         if(m_trades[i].hour == hour) Apply(s, m_trades[i]);
      return s;
   }

   AWPerfSlice ByConfirmStrength(const int strength)
   {
      AWPerfSlice s; ResetSlice(s, StringFormat("CONF%d", strength));
      for(int i = 0; i < ArraySize(m_trades); ++i)
         if(m_trades[i].confirmStrength == strength) Apply(s, m_trades[i]);
      return s;
   }

   string SummaryLine() const
   {
      return StringFormat("n=%d WR=%.1f%% PF=%.2f Exp=%.2f AvgR=%.2f MaxDD=%.2f CW=%d CL=%d",
                          m_overall.trades, m_overall.WinRate(), m_overall.ProfitFactor(),
                          m_overall.Expectancy(), m_overall.AvgR(), m_overall.maxDd,
                          m_overall.maxConsecWin, m_overall.maxConsecLoss);
   }

private:
   void ResetSlice(AWPerfSlice &s, const string name) const
   {
      ZeroMemory(s);
      s.name = name;
   }

   void Apply(AWPerfSlice &s, const AWTradeRecord &rec)
   {
      s.trades++;
      s.sumR += rec.rMultiple;
      s.equityCurve += rec.pnl;
      if(s.equityCurve > s.peak) s.peak = s.equityCurve;
      const double dd = s.peak - s.equityCurve;
      if(dd > s.maxDd) s.maxDd = dd;

      if(rec.pnl > 0.0)
      {
         s.wins++;
         s.grossWin += rec.pnl;
         s.curConsecWin++;
         s.curConsecLoss = 0;
         if(s.curConsecWin > s.maxConsecWin) s.maxConsecWin = s.curConsecWin;
      }
      else
      {
         s.losses++;
         s.grossLoss += MathAbs(rec.pnl);
         s.curConsecLoss++;
         s.curConsecWin = 0;
         if(s.curConsecLoss > s.maxConsecLoss) s.maxConsecLoss = s.curConsecLoss;
      }
   }
};

#endif
