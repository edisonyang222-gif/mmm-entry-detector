//+------------------------------------------------------------------+
//| AW_TradeScore.mqh                                                 |
//| Signal / trade quality scoring scaffolding                        |
//| Lite: analysis score only. Institutional later: reject low score. |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_TRADE_SCORE_MQH
#define AW_TRADE_SCORE_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"

class CAWTradeScore
  {
private:
   CAWLogger        *m_logger;
   bool              m_enable;
   int               m_min_score_to_hint;   // Lite: display threshold
   int               m_min_score_to_trade;  // Pro/Inst later
   int               m_last_score;
   string            m_last_breakdown;

public:
                     CAWTradeScore(void)
     {
      m_logger=NULL;
      m_enable=true;
      m_min_score_to_hint=60;
      m_min_score_to_trade=70;
      m_last_score=0;
      m_last_breakdown="";
     }

   bool              Init(CAWLogger *logger,
                          const bool enable,
                          const int min_score_to_hint,
                          const int min_score_to_trade)
     {
      m_logger=logger;
      m_enable=enable;
      m_min_score_to_hint=min_score_to_hint;
      m_min_score_to_trade=min_score_to_trade;
      if(m_logger!=NULL)
         m_logger.Info("TradeScore","initialized");
      return true;
     }

   void              DailyReset(const AWDailyContext &ctx)
     {
      AW_UNUSED(ctx);
      m_last_score=0;
      m_last_breakdown="";
      if(m_logger!=NULL)
         m_logger.Debug("TradeScore","DailyReset");
     }

   void              Update(void)
     {
      if(!m_enable)
        {
         m_last_score=0;
         m_last_breakdown="scoring_disabled";
         return;
        }
      // TODO: weight bias alignment, liquidity, fib location, session, confirmation.
      m_last_score=0;
      m_last_breakdown="awaiting_strategy_rules";
     }

   int               LastScore(void) const { return m_last_score; }
   string            LastBreakdown(void) const { return m_last_breakdown; }
   bool              PassesHintThreshold(void) const { return(m_last_score>=m_min_score_to_hint); }
   bool              PassesTradeThreshold(void) const { return(m_last_score>=m_min_score_to_trade); }
  };

#endif
//+------------------------------------------------------------------+
