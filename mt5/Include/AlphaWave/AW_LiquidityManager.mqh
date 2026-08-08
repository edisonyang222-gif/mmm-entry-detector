//+------------------------------------------------------------------+
//| AW_LiquidityManager.mqh                                           |
//| Liquidity sweep: pierce + reclaim                                 |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_LIQUIDITY_MANAGER_MQH
#define AW_LIQUIDITY_MANAGER_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"
#include "AW_SessionManager.mqh"

class CAWLiquidityManager
  {
private:
   string            m_symbol;
   CAWLogger        *m_logger;
   bool              m_enable;
   double            m_pierce_points;   // min pierce beyond level (points)
   double            m_reclaim_points;  // reclaim buffer (points)
   AWSweepState      m_state;
   datetime          m_last_bar;

   // Pierced flags awaiting reclaim
   bool              m_p_pdh,m_p_pdl,m_p_ah,m_p_al,m_p_lh,m_p_ll;

   double PointSize(void) const
     {
      double p=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      if(p<=0.0) p=0.01;
      return p;
     }

   void MarkSweep(const ENUM_AW_SWEEP_TYPE t,const datetime when)
     {
      if(t==AW_SWEEP_PDH) m_state.pdh=true;
      if(t==AW_SWEEP_PDL) m_state.pdl=true;
      if(t==AW_SWEEP_ASIA_HIGH) m_state.asia_high=true;
      if(t==AW_SWEEP_ASIA_LOW) m_state.asia_low=true;
      if(t==AW_SWEEP_LONDON_HIGH) m_state.london_high=true;
      if(t==AW_SWEEP_LONDON_LOW) m_state.london_low=true;
      m_state.last_type=t;
      m_state.last_time=when;
      m_state.last_name=AW_SweepToText(t);
      if(m_logger!=NULL)
         m_logger.Info("Liquidity",m_state.last_name+" @ "+TimeToString(when,TIME_DATE|TIME_MINUTES));
     }

   void CheckHighSweep(const bool already,bool &pierced_flag,
                       const double level,const ENUM_AW_SWEEP_TYPE typ,
                       const double bar_high,const double bar_close,const datetime bar_time)
     {
      if(already || level<=0.0) return;
      const double pierce = m_pierce_points*PointSize();
      const double reclaim = m_reclaim_points*PointSize();
      if(!pierced_flag)
        {
         if(bar_high > level + pierce)
            pierced_flag=true;
         return;
        }
      // Reclaim: close back at or below level (+buffer)
      if(bar_close <= level + reclaim)
        {
         MarkSweep(typ,bar_time);
         pierced_flag=false;
        }
     }

   void CheckLowSweep(const bool already,bool &pierced_flag,
                      const double level,const ENUM_AW_SWEEP_TYPE typ,
                      const double bar_low,const double bar_close,const datetime bar_time)
     {
      if(already || level<=0.0) return;
      const double pierce = m_pierce_points*PointSize();
      const double reclaim = m_reclaim_points*PointSize();
      if(!pierced_flag)
        {
         if(bar_low < level - pierce)
            pierced_flag=true;
         return;
        }
      if(bar_close >= level - reclaim)
        {
         MarkSweep(typ,bar_time);
         pierced_flag=false;
        }
     }

public:
                     CAWLiquidityManager(void)
     {
      m_symbol="";
      m_logger=NULL;
      m_enable=true;
      m_pierce_points=50;
      m_reclaim_points=20;
      ZeroMemory(m_state);
      m_last_bar=0;
      m_p_pdh=m_p_pdl=m_p_ah=m_p_al=m_p_lh=m_p_ll=false;
     }

   bool Init(const string symbol,
             CAWLogger *logger,
             const bool enable,
             const double pierce_points,
             const double reclaim_points)
     {
      m_symbol=symbol;
      m_logger=logger;
      m_enable=enable;
      m_pierce_points=MathMax(0.0,pierce_points);
      m_reclaim_points=MathMax(0.0,reclaim_points);
      if(m_logger!=NULL)
         m_logger.Info("LiquidityManager",
                       StringFormat("initialized pierce=%.1f reclaim=%.1f pts",
                                    m_pierce_points,m_reclaim_points));
      return true;
     }

   void DailyReset(const AWDailyContext &ctx)
     {
      AW_UNUSED(ctx);
      ZeroMemory(m_state);
      m_last_bar=0;
      m_p_pdh=m_p_pdl=m_p_ah=m_p_al=m_p_lh=m_p_ll=false;
      if(m_logger!=NULL)
         m_logger.Debug("LiquidityManager","DailyReset");
     }

   void Update(const AWSessionLevels &sess)
     {
      if(!m_enable) return;

      MqlRates rates[];
      ArraySetAsSeries(rates,true);
      if(CopyRates(m_symbol,PERIOD_M15,0,3,rates)<2)
         return;

      if(rates[1].time==m_last_bar)
         return;
      m_last_bar=rates[1].time;

      const double h=rates[1].high;
      const double l=rates[1].low;
      const double c=rates[1].close;
      const datetime t=rates[1].time;

      CheckHighSweep(m_state.pdh,m_p_pdh,sess.pdh,AW_SWEEP_PDH,h,c,t);
      CheckLowSweep(m_state.pdl,m_p_pdl,sess.pdl,AW_SWEEP_PDL,l,c,t);

      if(sess.asia_ready)
        {
         CheckHighSweep(m_state.asia_high,m_p_ah,sess.asia_high,AW_SWEEP_ASIA_HIGH,h,c,t);
         CheckLowSweep(m_state.asia_low,m_p_al,sess.asia_low,AW_SWEEP_ASIA_LOW,l,c,t);
        }
      if(sess.london_ready)
        {
         CheckHighSweep(m_state.london_high,m_p_lh,sess.london_high,AW_SWEEP_LONDON_HIGH,h,c,t);
         CheckLowSweep(m_state.london_low,m_p_ll,sess.london_low,AW_SWEEP_LONDON_LOW,l,c,t);
        }
     }

   // Legacy stub signature compatibility
   void Update(void) {}

   AWSweepState State(void) const { return m_state; }
   bool AnySweep(void) const
     {
      return(m_state.pdh||m_state.pdl||m_state.asia_high||m_state.asia_low||
             m_state.london_high||m_state.london_low);
     }
   string LastSweepName(void) const { return(m_state.last_name==""?"None":m_state.last_name); }

   bool HasBuySideLiquidity(void) const { return(m_state.pdh||m_state.asia_high||m_state.london_high); }
   bool HasSellSideLiquidity(void) const { return(m_state.pdl||m_state.asia_low||m_state.london_low); }
   bool LastSweepUp(void) const
     {
      return(m_state.last_type==AW_SWEEP_PDH||m_state.last_type==AW_SWEEP_ASIA_HIGH||
             m_state.last_type==AW_SWEEP_LONDON_HIGH);
     }
   bool LastSweepDown(void) const
     {
      return(m_state.last_type==AW_SWEEP_PDL||m_state.last_type==AW_SWEEP_ASIA_LOW||
             m_state.last_type==AW_SWEEP_LONDON_LOW);
     }
  };

#endif
//+------------------------------------------------------------------+
