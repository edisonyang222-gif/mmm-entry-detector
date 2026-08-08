//+------------------------------------------------------------------+
//| AW_TradeScore.mqh                                                 |
//| Rule-based bias + 0-100 trade quality score                       |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_TRADE_SCORE_MQH
#define AW_TRADE_SCORE_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"

struct AWScoreWeights
  {
   int w_h4;
   int w_h1;
   int w_m15;
   int w_sweep;
   int w_fib50;
   int w_two_leg_pb;
   int w_m5_conf;
   // Bias component weights (separate small scores)
   int bias_h4;
   int bias_h1;
   int bias_m15;
   int bias_pd_pos;
   int bias_asia;
   int bias_sweep;
  };

class CAWTradeScore
  {
private:
   CAWLogger        *m_logger;
   bool              m_enable;
   AWScoreWeights    m_w;
   int               m_min_alert_score;
   AWScoreState      m_score;
   ENUM_AW_BIAS      m_bias;
   int               m_bias_score; // signed: + bull / - bear
   string            m_bias_breakdown;

public:
                     CAWTradeScore(void)
     {
      m_logger=NULL;
      m_enable=true;
      ZeroMemory(m_w);
      m_w.w_h4=15; m_w.w_h1=15; m_w.w_m15=15;
      m_w.w_sweep=15; m_w.w_fib50=15; m_w.w_two_leg_pb=10; m_w.w_m5_conf=15;
      m_w.bias_h4=20; m_w.bias_h1=20; m_w.bias_m15=20;
      m_w.bias_pd_pos=15; m_w.bias_asia=15; m_w.bias_sweep=10;
      m_min_alert_score=70;
      ZeroMemory(m_score);
      m_bias=AW_BIAS_NEUTRAL;
      m_bias_score=0;
      m_bias_breakdown="";
     }

   bool Init(CAWLogger *logger,
             const bool enable,
             const AWScoreWeights &weights,
             const int min_alert_score)
     {
      m_logger=logger;
      m_enable=enable;
      m_w=weights;
      m_min_alert_score=min_alert_score;
      if(m_logger!=NULL)
         m_logger.Info("TradeScore","initialized");
      return true;
     }

   void DailyReset(const AWDailyContext &ctx)
     {
      AW_UNUSED(ctx);
      ZeroMemory(m_score);
      m_bias=AW_BIAS_NEUTRAL;
      m_bias_score=0;
      m_bias_breakdown="";
      if(m_logger!=NULL)
         m_logger.Debug("TradeScore","DailyReset");
     }

   void UpdateBias(const ENUM_AW_BIAS h4,
                   const ENUM_AW_BIAS h1,
                   const ENUM_AW_BIAS m15,
                   const AWSessionLevels &sess,
                   const AWSweepState &sweep,
                   const double bid)
     {
      int s=0;
      string br="";

      if(h4==AW_BIAS_BULL){ s+=m_w.bias_h4; br+="H4+ "; }
      else if(h4==AW_BIAS_BEAR){ s-=m_w.bias_h4; br+="H4- "; }

      if(h1==AW_BIAS_BULL){ s+=m_w.bias_h1; br+="H1+ "; }
      else if(h1==AW_BIAS_BEAR){ s-=m_w.bias_h1; br+="H1- "; }

      if(m15==AW_BIAS_BULL){ s+=m_w.bias_m15; br+="M15+ "; }
      else if(m15==AW_BIAS_BEAR){ s-=m_w.bias_m15; br+="M15- "; }

      // PDH/PDL position
      if(sess.day_levels_ready && sess.pdh>0 && sess.pdl>0 && bid>0)
        {
         const double mid=0.5*(sess.pdh+sess.pdl);
         if(bid>mid && bid<sess.pdh){ s+=m_w.bias_pd_pos/2; br+="PD_midUp "; }
         else if(bid>=sess.pdh){ s+=m_w.bias_pd_pos; br+="PDH_above "; }
         else if(bid<mid && bid>sess.pdl){ s-=m_w.bias_pd_pos/2; br+="PD_midDn "; }
         else if(bid<=sess.pdl){ s-=m_w.bias_pd_pos; br+="PDL_below "; }
        }

      // Asia range position
      if(sess.asia_ready && sess.asia_high>sess.asia_low && bid>0)
        {
         const double amid=0.5*(sess.asia_high+sess.asia_low);
         if(bid>amid){ s+=m_w.bias_asia/2; br+="AsiaUp "; }
         else if(bid<amid){ s-=m_w.bias_asia/2; br+="AsiaDn "; }
        }

      // Sweep contribution to bias
      if(sweep.pdl || sweep.asia_low || sweep.london_low)
        { s+=m_w.bias_sweep; br+="SweepLow+ "; }
      if(sweep.pdh || sweep.asia_high || sweep.london_high)
        { s-=m_w.bias_sweep; br+="SweepHigh- "; }

      m_bias_score=s;
      m_bias_breakdown=br;

      // Do not hard-force direction: require clear margin
      const int thr=15;
      if(s>=thr) m_bias=AW_BIAS_BULL;
      else if(s<=-thr) m_bias=AW_BIAS_BEAR;
      else m_bias=AW_BIAS_NEUTRAL;
     }

   void UpdateScore(const ENUM_AW_BIAS h4,
                    const ENUM_AW_BIAS h1,
                    const ENUM_AW_BIAS m15,
                    const AWFibSetupState &fib,
                    const AWSweepState &sweep,
                    const AWConfirmState &conf)
     {
      if(!m_enable)
        {
         ZeroMemory(m_score);
         return;
        }

      int sc=0;
      string br="";
      ENUM_AW_SIGNAL_DIR dir=fib.direction;
      if(dir==AW_SIGNAL_NONE)
        {
         if(m_bias==AW_BIAS_BULL) dir=AW_SIGNAL_BUY;
         else if(m_bias==AW_BIAS_BEAR) dir=AW_SIGNAL_SELL;
        }

      const ENUM_AW_BIAS want=(dir==AW_SIGNAL_BUY? AW_BIAS_BULL : (dir==AW_SIGNAL_SELL? AW_BIAS_BEAR : AW_BIAS_NEUTRAL));

      if(want!=AW_BIAS_NEUTRAL)
        {
         if(h4==want){ sc+=m_w.w_h4; br+=StringFormat("H4(+%d) ",m_w.w_h4); }
         if(h1==want){ sc+=m_w.w_h1; br+=StringFormat("H1(+%d) ",m_w.w_h1); }
         if(m15==want){ sc+=m_w.w_m15; br+=StringFormat("M15(+%d) ",m_w.w_m15); }
        }

      bool sweep_ok=false;
      if(dir==AW_SIGNAL_BUY)
         sweep_ok=(sweep.pdl||sweep.asia_low||sweep.london_low);
      else if(dir==AW_SIGNAL_SELL)
         sweep_ok=(sweep.pdh||sweep.asia_high||sweep.london_high);
      if(sweep_ok){ sc+=m_w.w_sweep; br+=StringFormat("Sweep(+%d) ",m_w.w_sweep); }

      if(fib.in_zone){ sc+=m_w.w_fib50; br+=StringFormat("Fib50(+%d) ",m_w.w_fib50); }
      if(fib.two_leg_pullback){ sc+=m_w.w_two_leg_pb; br+=StringFormat("2LegPB(+%d) ",m_w.w_two_leg_pb); }
      if(conf.active && (conf.direction==dir || dir==AW_SIGNAL_NONE))
        { sc+=m_w.w_m5_conf; br+=StringFormat("M5(+%d) ",m_w.w_m5_conf); }

      if(sc>100) sc=100;
      if(sc<0) sc=0;

      m_score.score=sc;
      m_score.band=AW_ScoreToBand(sc);
      m_score.ui_status=AW_BandToUi(m_score.band);
      m_score.direction=dir;
      m_score.breakdown=br;
      m_score.setup_name=(fib.ready? (fib.in_zone? "Fib 0.5 Setup":"Fib Armed"):"None");
     }

   void Update(void) {}

   int LastScore(void) const { return m_score.score; }
   string LastBreakdown(void) const { return m_score.breakdown; }
   AWScoreState ScoreState(void) const { return m_score; }
   ENUM_AW_BIAS IntradayBias(void) const { return m_bias; }
   string BiasBreakdown(void) const { return m_bias_breakdown; }
   int MinAlertScore(void) const { return m_min_alert_score; }
   bool PassesAlert(void) const { return(m_score.score>=m_min_alert_score); }

   bool PassesHintThreshold(void) const { return(m_score.score>=50); }
   bool PassesTradeThreshold(void) const { return(m_score.score>=70); }
  };

#endif
//+------------------------------------------------------------------+
