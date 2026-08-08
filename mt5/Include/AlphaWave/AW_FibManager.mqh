//+------------------------------------------------------------------+
//| AW_FibManager.mqh                                                 |
//| Core Fib setup: two-leg trend + two-leg pullback into 0.5         |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_FIB_MANAGER_MQH
#define AW_FIB_MANAGER_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"
#include "AW_MarketStructure.mqh"

class CAWFibManager
  {
private:
   string            m_symbol;
   CAWLogger        *m_logger;
   bool              m_enable;
   double            m_tol_50_points;     // 0.5 zone tolerance in points
   int               m_min_impulse_points; // min size of impulse leg
   AWFibSetupState   m_state;
   datetime          m_last_bar;
   datetime          m_last_signal_bar;   // anti-duplicate
   string            m_last_signal_id;

   // Pullback swing tracking after fib created
   int               m_pb_leg_count;
   double            m_pb_last_ext;       // last extreme in pullback direction
   ENUM_AW_SWING_TYPE m_pb_expect;       // next expected swing type
   bool              m_pb_tracking;

   double PointSize(void) const
     {
      double p=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      if(p<=0.0) p=0.01;
      return p;
     }

   void ResetPullbackTrack(void)
     {
      m_pb_leg_count=0;
      m_pb_last_ext=0;
      m_pb_expect=AW_SWING_NONE;
      m_pb_tracking=false;
      m_state.two_leg_pullback=false;
      m_state.in_zone=false;
     }

   void SetFib(const ENUM_AW_SIGNAL_DIR dir,const double p0,const double p1,const datetime when,const string reason)
     {
      m_state.active=true;
      m_state.ready=true;
      m_state.direction=dir;
      m_state.anchor0=p0;
      m_state.anchor1=p1;
      m_state.created_time=when;
      m_state.reason=reason;

      // dir BUY: 0=low, 1=high; SELL: 0=high, 1=low
      const double span=p1-p0;
      m_state.lvl_0   = p0;
      m_state.lvl_25  = p0+0.25*span;
      m_state.lvl_50  = p0+0.50*span;
      m_state.lvl_618 = p0+0.618*span;
      m_state.lvl_75  = p0+0.75*span;
      m_state.lvl_100 = p1;

      ResetPullbackTrack();
      m_pb_tracking=true;
      m_pb_expect=(dir==AW_SIGNAL_BUY? AW_SWING_HIGH : AW_SWING_LOW);
      // First pullback extreme starts at anchor1
      m_pb_last_ext=p1;

      if(m_logger!=NULL)
         m_logger.Info("Fib",
                       StringFormat("Main Fib %s 0=%.2f 1=%.2f 0.5=%.2f | %s",
                                    AW_SignalDirToText(dir),p0,p1,m_state.lvl_50,reason));
     }

   bool DetectTwoLegTrend(CAWMarketStructure *ms)
     {
      if(ms==NULL) return false;
      AWSwingPoint sw[];
      if(!ms.GetM15Swings(12,sw))
         return false;
      const int n=ArraySize(sw);
      if(n<5) return false;

      const double min_impulse=m_min_impulse_points*PointSize();

      // Search newest patterns:
      // Bull two-leg: ... L1, H1, L2(HL), H2(HH)
      // Bear two-leg: ... H1, L1, H2(LH), L2(LL)
      for(int i=n-1;i>=4;i--)
        {
         // try ending at i as final swing
         AWSwingPoint a=sw[i-3];
         AWSwingPoint b=sw[i-2];
         AWSwingPoint c=sw[i-1];
         AWSwingPoint d=sw[i];

         // Bull: L H L H
         if(a.type==AW_SWING_LOW && b.type==AW_SWING_HIGH &&
            c.type==AW_SWING_LOW && d.type==AW_SWING_HIGH)
           {
            if(c.price>a.price && d.price>b.price)
              {
               if((b.price-a.price)>=min_impulse && (d.price-c.price)>=min_impulse*0.5)
                 {
                  // Major low = a (start), major high = d
                  if(!m_state.ready || m_state.direction!=AW_SIGNAL_BUY ||
                     MathAbs(m_state.anchor1-d.price)>PointSize())
                     SetFib(AW_SIGNAL_BUY,a.price,d.price,d.time,"two_leg_bull_LHLH");
                  return true;
                 }
              }
           }

         // Bear: H L H L
         if(a.type==AW_SWING_HIGH && b.type==AW_SWING_LOW &&
            c.type==AW_SWING_HIGH && d.type==AW_SWING_LOW)
           {
            if(c.price<a.price && d.price<b.price)
              {
               if((a.price-b.price)>=min_impulse && (c.price-d.price)>=min_impulse*0.5)
                 {
                  // Major high=a, major low=d  => fib 0=high, 1=low
                  if(!m_state.ready || m_state.direction!=AW_SIGNAL_SELL ||
                     MathAbs(m_state.anchor1-d.price)>PointSize())
                     SetFib(AW_SIGNAL_SELL,a.price,d.price,d.time,"two_leg_bear_HLHL");
                  return true;
                 }
              }
           }
        }
      return m_state.ready;
     }

   void UpdatePullback(CAWMarketStructure *ms,const MqlRates &bar)
     {
      if(!m_state.ready || !m_pb_tracking) return;

      AWSwingPoint sw[];
      if(!ms.GetM15Swings(8,sw)) return;
      const int n=ArraySize(sw);
      if(n<1) return;

      // Count pullback legs via alternating swings after fib creation time
      int legs=0;
      double last_ext=m_state.anchor1;
      ENUM_AW_SWING_TYPE expect=(m_state.direction==AW_SIGNAL_BUY? AW_SWING_HIGH:AW_SWING_LOW);

      for(int i=0;i<n;i++)
        {
         if(sw[i].time < m_state.created_time) continue;
         if(sw[i].type!=expect && expect!=AW_SWING_NONE)
           {
            // allow first matching after creation
           }
         if(m_state.direction==AW_SIGNAL_BUY)
           {
            // pullback down: after high at anchor, want HL swings... count each new swing low after a swing high
            if(sw[i].type==AW_SWING_HIGH && sw[i].price<=m_state.anchor1+PointSize()*10)
              {
               expect=AW_SWING_LOW;
              }
            else if(sw[i].type==AW_SWING_LOW && expect==AW_SWING_LOW)
              {
               legs++;
               last_ext=sw[i].price;
               expect=AW_SWING_HIGH;
              }
            else if(sw[i].type==AW_SWING_HIGH && expect==AW_SWING_HIGH)
              {
               expect=AW_SWING_LOW;
              }
           }
         else
           {
            if(sw[i].type==AW_SWING_LOW && sw[i].price>=m_state.anchor1-PointSize()*10)
              {
               expect=AW_SWING_HIGH;
              }
            else if(sw[i].type==AW_SWING_HIGH && expect==AW_SWING_HIGH)
              {
               legs++;
               last_ext=sw[i].price;
               expect=AW_SWING_LOW;
              }
            else if(sw[i].type==AW_SWING_LOW && expect==AW_SWING_LOW)
              {
               expect=AW_SWING_HIGH;
              }
           }
        }

      m_pb_leg_count=legs;
      m_pb_last_ext=last_ext;
      m_state.two_leg_pullback=(legs>=2);

      // 0.5 zone
      const double tol=m_tol_50_points*PointSize();
      const double zlo=MathMin(m_state.lvl_50-tol,m_state.lvl_50+tol);
      const double zhi=MathMax(m_state.lvl_50-tol,m_state.lvl_50+tol);
      // For BUY fib, 0.5 is between low and high; zone is around lvl_50
      const bool touched = (bar.low<=zhi && bar.high>=zlo);

      // Reject single-bar spike: require either two-leg pullback already, OR
      // bar range not covering from near-1 to 0.5 in one candle
      bool spike=false;
      if(m_state.direction==AW_SIGNAL_BUY)
        {
         const double near1=m_state.lvl_100 - 0.15*(m_state.lvl_100-m_state.lvl_0);
         if(bar.high>=near1 && bar.low<=zhi && !m_state.two_leg_pullback)
            spike=true;
        }
      else
        {
         const double near1=m_state.lvl_100 + 0.15*(m_state.lvl_0-m_state.lvl_100);
         // sell fib: lvl_0=high, lvl_100=low, span negative
         const double span=m_state.lvl_100-m_state.lvl_0; // negative
         AW_UNUSED(span);
         const double near1b=m_state.anchor1 + 0.15*(m_state.anchor0-m_state.anchor1);
         if(bar.low<=near1b && bar.high>=zlo && !m_state.two_leg_pullback)
            spike=true;
        }

      m_state.in_zone = touched && m_state.two_leg_pullback && !spike;

      if(m_state.in_zone)
        {
         const string sid=StringFormat("FIB50_%s_%s",
                                       AW_SignalDirToText(m_state.direction),
                                       TimeToString(bar.time,TIME_DATE|TIME_MINUTES));
         if(sid!=m_last_signal_id || bar.time!=m_last_signal_bar)
           {
            m_last_signal_id=sid;
            m_last_signal_bar=bar.time;
            if(m_logger!=NULL)
               m_logger.LogEntryReason(sid,
                                       StringFormat("Fib0.5 zone dir=%s twoLegPB=%d",
                                                    AW_SignalDirToText(m_state.direction),
                                                    (int)m_state.two_leg_pullback));
           }
        }
     }

public:
                     CAWFibManager(void)
     {
      m_symbol="";
      m_logger=NULL;
      m_enable=true;
      m_tol_50_points=150;
      m_min_impulse_points=300;
      ZeroMemory(m_state);
      m_last_bar=0;
      m_last_signal_bar=0;
      m_last_signal_id="";
      ResetPullbackTrack();
     }

   bool Init(const string symbol,
             CAWLogger *logger,
             const bool enable,
             const double tol_50_points,
             const int min_impulse_points)
     {
      m_symbol=symbol;
      m_logger=logger;
      m_enable=enable;
      m_tol_50_points=MathMax(1.0,tol_50_points);
      m_min_impulse_points=MathMax(1,min_impulse_points);
      if(m_logger!=NULL)
         m_logger.Info("FibManager","initialized");
      return true;
     }

   void DailyReset(const AWDailyContext &ctx)
     {
      AW_UNUSED(ctx);
      ZeroMemory(m_state);
      ResetPullbackTrack();
      m_last_bar=0;
      m_last_signal_bar=0;
      m_last_signal_id="";
      if(m_logger!=NULL)
         m_logger.Info("FibManager","DailyReset — rebuild Fib from 04:45");
     }

   void Update(CAWMarketStructure *ms)
     {
      if(!m_enable || ms==NULL) return;

      MqlRates rates[];
      ArraySetAsSeries(rates,true);
      if(CopyRates(m_symbol,PERIOD_M15,0,5,rates)<3)
         return;
      if(rates[1].time==m_last_bar)
        {
         // still update zone with forming data lightly? use closed only
         return;
        }
      m_last_bar=rates[1].time;

      DetectTwoLegTrend(ms);
      if(m_state.ready)
         UpdatePullback(ms,rates[1]);
     }

   void Update(void) {} // unused

   AWFibSetupState State(void) const { return m_state; }
   bool IsValid(void) const { return m_state.ready; }
   bool InSetupZone(void) const { return m_state.in_zone; }
   bool HasTwoLegPullback(void) const { return m_state.two_leg_pullback; }
   ENUM_AW_SIGNAL_DIR Direction(void) const { return m_state.direction; }

   double Level0(void) const { return m_state.lvl_0; }
   double Level25(void) const { return m_state.lvl_25; }
   double Level50(void) const { return m_state.lvl_50; }
   double Level618(void) const { return m_state.lvl_618; }
   double Level75(void) const { return m_state.lvl_75; }
   double Level100(void) const { return m_state.lvl_100; }

   // Compat aliases
   double Level382(void) const { return m_state.lvl_25; }
   double Level500(void) const { return m_state.lvl_50; }
   double Level705(void) const { return m_state.lvl_75; }
  };

#endif
//+------------------------------------------------------------------+
