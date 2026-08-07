//+------------------------------------------------------------------+
//| AW_RiskManager.mqh                                                |
//| Risk / drawdown / kill-switch scaffolding                         |
//| Priority: max drawdown control over max profit                    |
//| Forbidden: martingale, grid, averaging down, stealth SL removal   |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_RISK_MANAGER_MQH
#define AW_RISK_MANAGER_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"

class CAWRiskManager
  {
private:
   CAWLogger        *m_logger;
   bool              m_enable;
   double            m_risk_percent_per_trade;
   double            m_max_daily_loss_percent;
   double            m_max_drawdown_percent;
   int               m_max_open_trades;
   bool              m_kill_switch;
   string            m_kill_reason;
   double            m_day_start_equity;
   double            m_peak_equity;

public:
                     CAWRiskManager(void)
     {
      m_logger=NULL;
      m_enable=true;
      m_risk_percent_per_trade=0.5;
      m_max_daily_loss_percent=2.0;
      m_max_drawdown_percent=5.0;
      m_max_open_trades=1;
      m_kill_switch=false;
      m_kill_reason="";
      m_day_start_equity=0.0;
      m_peak_equity=0.0;
     }

   bool              Init(CAWLogger *logger,
                          const bool enable,
                          const double risk_percent_per_trade,
                          const double max_daily_loss_percent,
                          const double max_drawdown_percent,
                          const int max_open_trades)
     {
      m_logger=logger;
      m_enable=enable;
      m_risk_percent_per_trade=risk_percent_per_trade;
      m_max_daily_loss_percent=max_daily_loss_percent;
      m_max_drawdown_percent=max_drawdown_percent;
      m_max_open_trades=MathMax(1,max_open_trades);
      m_kill_switch=false;
      m_kill_reason="";
      m_day_start_equity=AccountInfoDouble(ACCOUNT_EQUITY);
      m_peak_equity=m_day_start_equity;
      if(m_logger!=NULL)
         m_logger.Info("RiskManager",
                       StringFormat("initialized risk=%.2f%% ddMax=%.2f%%",
                                    m_risk_percent_per_trade,m_max_drawdown_percent));
      return true;
     }

   void              DailyReset(const AWDailyContext &ctx)
     {
      AW_UNUSED(ctx);
      m_day_start_equity=AccountInfoDouble(ACCOUNT_EQUITY);
      // Peak is not fully reset: drawdown priority is account-level.
      // TODO: confirm whether peak should reset daily for Institutional version.
      if(m_peak_equity<=0.0)
         m_peak_equity=m_day_start_equity;
      if(m_logger!=NULL)
         m_logger.Debug("RiskManager","DailyReset");
     }

   void              Update(void)
     {
      if(!m_enable)
         return;

      const double equity=AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity>m_peak_equity)
         m_peak_equity=equity;

      // Soft monitoring only in Lite — no auto trading yet.
      if(m_day_start_equity>0.0)
        {
         const double day_dd_pct=(m_day_start_equity-equity)/m_day_start_equity*100.0;
         if(day_dd_pct>=m_max_daily_loss_percent)
            ArmKillSwitch("max_daily_loss");
        }

      if(m_peak_equity>0.0)
        {
         const double dd_pct=(m_peak_equity-equity)/m_peak_equity*100.0;
         if(dd_pct>=m_max_drawdown_percent)
            ArmKillSwitch("max_drawdown");
        }
     }

   bool              AllowNewTrade(string &reject_reason) const
     {
      reject_reason="";
      if(!m_enable)
        {
         reject_reason="risk_disabled";
         return false;
        }
      if(m_kill_switch)
        {
         reject_reason="kill_switch:"+m_kill_reason;
         return false;
        }
      // Hard policy placeholders for Pro+:
      // - No martingale
      // - No grid
      // - No averaging down
      // - Never secretly modify/remove SL to inflate winrate
      return true;
     }

   void              ArmKillSwitch(const string reason)
     {
      if(m_kill_switch)
         return;
      m_kill_switch=true;
      m_kill_reason=reason;
      if(m_logger!=NULL)
         m_logger.Warn("RiskManager","KillSwitch ARMED: "+reason);
     }

   void              ClearKillSwitch(void)
     {
      m_kill_switch=false;
      m_kill_reason="";
      if(m_logger!=NULL)
         m_logger.Info("RiskManager","KillSwitch CLEARED");
     }

   bool              KillSwitchArmed(void) const { return m_kill_switch; }
   string            KillReason(void) const { return m_kill_reason; }
   double            RiskPercentPerTrade(void) const { return m_risk_percent_per_trade; }
   int               MaxOpenTrades(void) const { return m_max_open_trades; }

   // Explicitly forbidden strategies — keep as named APIs so callers cannot "forget".
   bool              AllowMartingale(void) const { return false; }
   bool              AllowGrid(void) const { return false; }
   bool              AllowAveragingDown(void) const { return false; }
   bool              AllowStealthSlRemoval(void) const { return false; }
  };

#endif
//+------------------------------------------------------------------+
