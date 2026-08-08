//+------------------------------------------------------------------+
//| AW_ConfirmationManager.mqh                                        |
//| M5 confirmation once price is in M15 setup zone                   |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_CONFIRMATION_MANAGER_MQH
#define AW_CONFIRMATION_MANAGER_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"

class CAWConfirmationManager
  {
private:
   string            m_symbol;
   CAWLogger        *m_logger;
   bool              m_enable;
   bool              m_en_engulf;
   bool              m_en_pin;
   bool              m_en_reject;
   bool              m_en_bos;
   bool              m_en_choch;
   double            m_pin_wick_body_ratio; // default 2.0
   double            m_reject_wick_body_ratio;
   int               m_swing_left;
   int               m_swing_right;

   AWConfirmState    m_state;
   datetime          m_last_bar;
   datetime          m_last_signal_bar;
   string            m_last_signal_id;

   // simple M5 swing memory for BOS/CHoCH
   double            m_last_sh;
   double            m_last_sl;
   ENUM_AW_BIAS      m_m5_bias;

   bool IsBullEngulf(const MqlRates &prev,const MqlRates &cur) const
     {
      const bool prev_bear=prev.close<prev.open;
      const bool cur_bull=cur.close>cur.open;
      return(prev_bear && cur_bull && cur.close>=prev.open && cur.open<=prev.close);
     }

   bool IsBearEngulf(const MqlRates &prev,const MqlRates &cur) const
     {
      const bool prev_bull=prev.close>prev.open;
      const bool cur_bear=cur.close<cur.open;
      return(prev_bull && cur_bear && cur.close<=prev.open && cur.open>=prev.close);
     }

   bool IsPin(const MqlRates &cur,const ENUM_AW_SIGNAL_DIR want,string &name) const
     {
      const double body=MathAbs(cur.close-cur.open);
      if(body<=0.0) return false;
      const double upper=cur.high-MathMax(cur.open,cur.close);
      const double lower=MathMin(cur.open,cur.close)-cur.low;
      if(want==AW_SIGNAL_BUY)
        {
         if(lower>=body*m_pin_wick_body_ratio && upper<=body)
           { name="PinBar"; return true; }
        }
      else if(want==AW_SIGNAL_SELL)
        {
         if(upper>=body*m_pin_wick_body_ratio && lower<=body)
           { name="PinBar"; return true; }
        }
      return false;
     }

   bool IsRejection(const MqlRates &cur,const ENUM_AW_SIGNAL_DIR want,string &name) const
     {
      const double body=MathMax(MathAbs(cur.close-cur.open),_Point);
      const double upper=cur.high-MathMax(cur.open,cur.close);
      const double lower=MathMin(cur.open,cur.close)-cur.low;
      if(want==AW_SIGNAL_BUY && lower>=body*m_reject_wick_body_ratio && cur.close>=cur.open)
        { name="Rejection"; return true; }
      if(want==AW_SIGNAL_SELL && upper>=body*m_reject_wick_body_ratio && cur.close<=cur.open)
        { name="Rejection"; return true; }
      return false;
     }

   void UpdateM5Swings(const MqlRates &rates[],const int got)
     {
      if(got<m_swing_left+m_swing_right+3) return;
      const int i=m_swing_right;
      // swing high?
      bool sh=true,sl=true;
      for(int k=1;k<=m_swing_left;k++)
        {
         if(rates[i+k].high>=rates[i].high) sh=false;
         if(rates[i+k].low<=rates[i].low) sl=false;
        }
      for(int k=1;k<=m_swing_right;k++)
        {
         if(rates[i-k].high>rates[i].high) sh=false;
         if(rates[i-k].low<rates[i].low) sl=false;
        }
      if(sh) m_last_sh=rates[i].high;
      if(sl) m_last_sl=rates[i].low;
     }

   void Emit(const ENUM_AW_CONFIRM_TYPE typ,const ENUM_AW_SIGNAL_DIR dir,
             const datetime bar_time,const string name)
     {
      const string sid=StringFormat("M5_%s_%s",name,TimeToString(bar_time,TIME_DATE|TIME_MINUTES));
      if(sid==m_last_signal_id && bar_time==m_last_signal_bar)
         return;
      m_last_signal_id=sid;
      m_last_signal_bar=bar_time;

      m_state.active=true;
      m_state.type=typ;
      m_state.direction=dir;
      m_state.bar_time=bar_time;
      m_state.name=name;

      if(m_logger!=NULL)
         m_logger.LogEntryReason(sid,"M5 confirmation "+name+" dir="+AW_SignalDirToText(dir));
     }

public:
                     CAWConfirmationManager(void)
     {
      m_symbol="";
      m_logger=NULL;
      m_enable=true;
      m_en_engulf=true;
      m_en_pin=true;
      m_en_reject=true;
      m_en_bos=true;
      m_en_choch=true;
      m_pin_wick_body_ratio=2.0;
      m_reject_wick_body_ratio=1.5;
      m_swing_left=2;
      m_swing_right=2;
      ZeroMemory(m_state);
      m_last_bar=0;
      m_last_signal_bar=0;
      m_last_signal_id="";
      m_last_sh=0;
      m_last_sl=0;
      m_m5_bias=AW_BIAS_NEUTRAL;
     }

   bool Init(const string symbol,
             CAWLogger *logger,
             const bool enable,
             const bool en_engulf,
             const bool en_pin,
             const bool en_reject,
             const bool en_bos,
             const bool en_choch,
             const double pin_ratio,
             const double reject_ratio,
             const int swing_left,
             const int swing_right)
     {
      m_symbol=symbol;
      m_logger=logger;
      m_enable=enable;
      m_en_engulf=en_engulf;
      m_en_pin=en_pin;
      m_en_reject=en_reject;
      m_en_bos=en_bos;
      m_en_choch=en_choch;
      m_pin_wick_body_ratio=MathMax(1.0,pin_ratio);
      m_reject_wick_body_ratio=MathMax(1.0,reject_ratio);
      m_swing_left=MathMax(1,swing_left);
      m_swing_right=MathMax(1,swing_right);
      if(m_logger!=NULL)
         m_logger.Info("ConfirmationManager","initialized");
      return true;
     }

   void DailyReset(const AWDailyContext &ctx)
     {
      AW_UNUSED(ctx);
      ZeroMemory(m_state);
      m_last_bar=0;
      m_last_signal_bar=0;
      m_last_signal_id="";
      m_last_sh=0;
      m_last_sl=0;
      m_m5_bias=AW_BIAS_NEUTRAL;
      if(m_logger!=NULL)
         m_logger.Debug("ConfirmationManager","DailyReset");
     }

   void Update(const bool in_setup_zone,const ENUM_AW_SIGNAL_DIR setup_dir)
     {
      if(!m_enable)
        {
         m_state.active=false;
         return;
        }

      MqlRates rates[];
      ArraySetAsSeries(rates,true);
      const int got=CopyRates(m_symbol,PERIOD_M5,0,80,rates);
      if(got<m_swing_left+m_swing_right+5)
         return;

      if(rates[1].time==m_last_bar)
         return;
      m_last_bar=rates[1].time;

      UpdateM5Swings(rates,got);

      // Only confirm when in M15 setup zone
      if(!in_setup_zone || setup_dir==AW_SIGNAL_NONE)
        {
         // keep last confirmation display briefly? clear if left zone
         if(!in_setup_zone)
            m_state.active=false;
         return;
        }

      const MqlRates cur=rates[1];
      const MqlRates prev=rates[2];
      string name="";

      if(m_en_engulf)
        {
         if(setup_dir==AW_SIGNAL_BUY && IsBullEngulf(prev,cur))
           { Emit(AW_CONF_ENGULFING,AW_SIGNAL_BUY,cur.time,"Engulfing"); return; }
         if(setup_dir==AW_SIGNAL_SELL && IsBearEngulf(prev,cur))
           { Emit(AW_CONF_ENGULFING,AW_SIGNAL_SELL,cur.time,"Engulfing"); return; }
        }

      if(m_en_pin && IsPin(cur,setup_dir,name))
        { Emit(AW_CONF_PINBAR,setup_dir,cur.time,name); return; }

      if(m_en_reject && IsRejection(cur,setup_dir,name))
        { Emit(AW_CONF_REJECTION,setup_dir,cur.time,name); return; }

      // BOS / CHoCH on M5
      if(m_last_sh>0.0 && m_en_bos && setup_dir==AW_SIGNAL_BUY && cur.close>m_last_sh)
        {
         if(m_m5_bias==AW_BIAS_BEAR && m_en_choch)
           { m_m5_bias=AW_BIAS_BULL; Emit(AW_CONF_CHOCH,AW_SIGNAL_BUY,cur.time,"CHoCH"); return; }
         m_m5_bias=AW_BIAS_BULL;
         Emit(AW_CONF_BOS,AW_SIGNAL_BUY,cur.time,"BOS");
         return;
        }
      if(m_last_sl>0.0 && m_en_bos && setup_dir==AW_SIGNAL_SELL && cur.close<m_last_sl)
        {
         if(m_m5_bias==AW_BIAS_BULL && m_en_choch)
           { m_m5_bias=AW_BIAS_BEAR; Emit(AW_CONF_CHOCH,AW_SIGNAL_SELL,cur.time,"CHoCH"); return; }
         m_m5_bias=AW_BIAS_BEAR;
         Emit(AW_CONF_BOS,AW_SIGNAL_SELL,cur.time,"BOS");
         return;
        }
     }

   void Update(void) {}

   bool IsConfirmed(void) const { return m_state.active; }
   string Reason(void) const { return(m_state.name==""?"None":m_state.name); }
   AWConfirmState State(void) const { return m_state; }
  };

#endif
//+------------------------------------------------------------------+
