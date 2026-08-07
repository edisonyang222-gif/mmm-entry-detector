//+------------------------------------------------------------------+
//| AW_LiquidityManager.mqh                                           |
//| Liquidity pools / sweep scaffolding                               |
//| TODO: detect equal highs/lows, pools, and sweep confirmation      |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_LIQUIDITY_MANAGER_MQH
#define AW_LIQUIDITY_MANAGER_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"

class CAWLiquidityManager
  {
private:
   string            m_symbol;
   CAWLogger        *m_logger;
   bool              m_enable;
   int               m_lookback_bars;
   bool              m_buy_side_liquidity;
   bool              m_sell_side_liquidity;
   bool              m_last_sweep_up;
   bool              m_last_sweep_down;

public:
                     CAWLiquidityManager(void)
     {
      m_symbol="";
      m_logger=NULL;
      m_enable=true;
      m_lookback_bars=50;
      m_buy_side_liquidity=false;
      m_sell_side_liquidity=false;
      m_last_sweep_up=false;
      m_last_sweep_down=false;
     }

   bool              Init(const string symbol,
                          CAWLogger *logger,
                          const bool enable,
                          const int lookback_bars)
     {
      m_symbol=symbol;
      m_logger=logger;
      m_enable=enable;
      m_lookback_bars=MathMax(5,lookback_bars);
      if(m_logger!=NULL)
         m_logger.Info("LiquidityManager","initialized");
      return true;
     }

   void              DailyReset(const AWDailyContext &ctx)
     {
      AW_UNUSED(ctx);
      m_buy_side_liquidity=false;
      m_sell_side_liquidity=false;
      m_last_sweep_up=false;
      m_last_sweep_down=false;
      if(m_logger!=NULL)
         m_logger.Debug("LiquidityManager","DailyReset");
     }

   void              Update(void)
     {
      if(!m_enable)
        {
         m_buy_side_liquidity=false;
         m_sell_side_liquidity=false;
         m_last_sweep_up=false;
         m_last_sweep_down=false;
         return;
        }
      // TODO: scan M15/M5 for liquidity pools and mark sweep events.
      AW_UNUSED(m_lookback_bars);
      AW_UNUSED(m_symbol);
     }

   bool              HasBuySideLiquidity(void) const { return m_buy_side_liquidity; }
   bool              HasSellSideLiquidity(void) const { return m_sell_side_liquidity; }
   bool              LastSweepUp(void) const { return m_last_sweep_up; }
   bool              LastSweepDown(void) const { return m_last_sweep_down; }
  };

#endif
//+------------------------------------------------------------------+
