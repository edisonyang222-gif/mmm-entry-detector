//+------------------------------------------------------------------+
//| AW_TradeManager.mqh                                               |
//| Order execution scaffolding                                       |
//| Lite edition: permanently disabled (analysis only)                |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_TRADE_MANAGER_MQH
#define AW_TRADE_MANAGER_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"
#include "AW_RiskManager.mqh"

class CAWTradeManager
  {
private:
   string            m_symbol;
   CAWLogger        *m_logger;
   CAWRiskManager   *m_risk;
   ENUM_AW_EDITION   m_edition;
   bool              m_enable_auto_trade;
   ulong             m_magic;
   int               m_slippage_points;

public:
                     CAWTradeManager(void)
     {
      m_symbol="";
      m_logger=NULL;
      m_risk=NULL;
      m_edition=AW_EDITION_LITE;
      m_enable_auto_trade=false;
      m_magic=20260807;
      m_slippage_points=30;
     }

   bool              Init(const string symbol,
                          CAWLogger *logger,
                          CAWRiskManager *risk,
                          const ENUM_AW_EDITION edition,
                          const bool enable_auto_trade,
                          const ulong magic,
                          const int slippage_points)
     {
      m_symbol=symbol;
      m_logger=logger;
      m_risk=risk;
      m_edition=edition;
      m_enable_auto_trade=enable_auto_trade;
      m_magic=magic;
      m_slippage_points=slippage_points;

      // Lite hard-lock: never auto-trade.
      if(m_edition==AW_EDITION_LITE)
         m_enable_auto_trade=false;

      if(m_logger!=NULL)
         m_logger.Info("TradeManager",
                       StringFormat("initialized edition=%s auto=%s",
                                    AW_EditionToText(m_edition),
                                    (m_enable_auto_trade ? "ON" : "OFF")));
      return true;
     }

   void              DailyReset(const AWDailyContext &ctx)
     {
      AW_UNUSED(ctx);
      if(m_logger!=NULL)
         m_logger.Debug("TradeManager","DailyReset");
     }

   void              Update(void)
     {
      // No execution in scaffold phase.
     }

   bool              CanTrade(string &reject_reason) const
     {
      reject_reason="";
      if(m_edition==AW_EDITION_LITE || !m_enable_auto_trade)
        {
         reject_reason="auto_trade_disabled_for_edition";
         return false;
        }
      if(m_risk==NULL)
        {
         reject_reason="risk_manager_missing";
         return false;
        }
      return m_risk.AllowNewTrade(reject_reason);
     }

   bool              OpenTrade(void)
     {
      // TODO: Pro/Institutional — place market/limit with mandatory SL/TP.
      // Must log entry reason via Logger.LogEntryReason.
      // Must never remove/hide SL to inflate winrate.
      string reject="";
      if(!CanTrade(reject))
        {
         if(m_logger!=NULL)
            m_logger.LogRejectReason("OpenTrade",reject);
         return false;
        }
      AW_UNUSED(m_symbol);
      AW_UNUSED(m_magic);
      AW_UNUSED(m_slippage_points);
      if(m_logger!=NULL)
         m_logger.Warn("TradeManager","OpenTrade called but strategy not implemented yet");
      return false;
     }

   bool              IsAutoTradeEnabled(void) const { return m_enable_auto_trade; }
  };

#endif
//+------------------------------------------------------------------+
