//+------------------------------------------------------------------+
//| AW_Statistics.mqh                                                 |
//| Performance / quality statistics scaffolding                      |
//| Mainly for Institutional edition later                            |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_STATISTICS_MQH
#define AW_STATISTICS_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"

class CAWStatistics
  {
private:
   CAWLogger        *m_logger;
   bool              m_enable;
   int               m_signals_seen;
   int               m_signals_hinted;
   int               m_trades_taken;
   int               m_trades_rejected;
   int               m_daily_resets;

public:
                     CAWStatistics(void)
     {
      m_logger=NULL;
      m_enable=true;
      m_signals_seen=0;
      m_signals_hinted=0;
      m_trades_taken=0;
      m_trades_rejected=0;
      m_daily_resets=0;
     }

   bool              Init(CAWLogger *logger,const bool enable)
     {
      m_logger=logger;
      m_enable=enable;
      if(m_logger!=NULL)
         m_logger.Info("Statistics","initialized");
      return true;
     }

   void              DailyReset(const AWDailyContext &ctx)
     {
      AW_UNUSED(ctx);
      // Keep cumulative counters; optionally snapshot daily later.
      m_daily_resets++;
      if(m_logger!=NULL)
         m_logger.Debug("Statistics",
                        StringFormat("DailyReset count=%d",m_daily_resets));
     }

   void              Update(void)
     {
      // TODO: compute winrate, expectancy, quality distribution (Institutional).
      if(!m_enable)
         return;
     }

   void              OnSignalSeen(void) { if(m_enable) m_signals_seen++; }
   void              OnSignalHinted(void) { if(m_enable) m_signals_hinted++; }
   void              OnTradeTaken(void) { if(m_enable) m_trades_taken++; }
   void              OnTradeRejected(void) { if(m_enable) m_trades_rejected++; }

   int               SignalsSeen(void) const { return m_signals_seen; }
   int               SignalsHinted(void) const { return m_signals_hinted; }
   int               TradesTaken(void) const { return m_trades_taken; }
   int               TradesRejected(void) const { return m_trades_rejected; }
   int               DailyResets(void) const { return m_daily_resets; }

   string            Snapshot(void) const
     {
      return StringFormat("seen=%d hinted=%d taken=%d rejected=%d resets=%d",
                          m_signals_seen,m_signals_hinted,m_trades_taken,
                          m_trades_rejected,m_daily_resets);
     }
  };

#endif
//+------------------------------------------------------------------+
