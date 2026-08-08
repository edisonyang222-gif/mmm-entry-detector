//+------------------------------------------------------------------+
//| AW_MarketStructure.mqh                                            |
//| H4 / H1 / M15 swing structure: HH HL LH LL BOS CHoCH              |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_MARKET_STRUCTURE_MQH
#define AW_MARKET_STRUCTURE_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"
#include "AW_TimeManager.mqh"

#define AW_MS_MAX_SWINGS 64

class CAWTfStructureEngine
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_swing_left;   // bars left of pivot
   int               m_swing_right;  // bars right of pivot (confirmation)
   int               m_lookback;

   AWSwingPoint      m_swings[];
   int               m_swing_count;
   AWTfStructureState m_state;
   datetime          m_last_processed_bar;

   void ClearSwings(void)
     {
      ArrayResize(m_swings,0);
      m_swing_count=0;
     }

   void PushSwing(const AWSwingPoint &s)
     {
      const int n=ArraySize(m_swings);
      ArrayResize(m_swings,n+1);
      m_swings[n]=s;
      m_swing_count=n+1;
      if(m_swing_count>AW_MS_MAX_SWINGS)
        {
         for(int i=0;i<AW_MS_MAX_SWINGS;i++)
            m_swings[i]=m_swings[i+(m_swing_count-AW_MS_MAX_SWINGS)];
         ArrayResize(m_swings,AW_MS_MAX_SWINGS);
         m_swing_count=AW_MS_MAX_SWINGS;
        }
     }

   bool IsSwingHigh(const MqlRates &rates[],const int i,const int total) const
     {
      // rates is series: index 0 = current forming
      // pivot at i must have m_swing_right bars to the right (more recent = lower index)
      if(i<m_swing_right || i+m_swing_left>=total)
         return false;
      const double p=rates[i].high;
      for(int k=1;k<=m_swing_left;k++)
         if(rates[i+k].high>=p) return false;
      for(int k=1;k<=m_swing_right;k++)
         if(rates[i-k].high>p) return false;
      return true;
     }

   bool IsSwingLow(const MqlRates &rates[],const int i,const int total) const
     {
      if(i<m_swing_right || i+m_swing_left>=total)
         return false;
      const double p=rates[i].low;
      for(int k=1;k<=m_swing_left;k++)
         if(rates[i+k].low<=p) return false;
      for(int k=1;k<=m_swing_right;k++)
         if(rates[i-k].low<p) return false;
      return true;
     }

   AWSwingPoint LastSwingOfType(const ENUM_AW_SWING_TYPE t,const int skip=0) const
     {
      AWSwingPoint empty;
      ZeroMemory(empty);
      int skipped=0;
      for(int i=m_swing_count-1;i>=0;i--)
        {
         if(m_swings[i].type!=t) continue;
         if(skipped<skip){ skipped++; continue; }
         return m_swings[i];
        }
      return empty;
     }

   void ClassifyAndEvents(const MqlRates &closed_bar)
     {
      m_state.last_event=AW_EVT_NONE;
      m_state.bos_bull=false;
      m_state.bos_bear=false;
      m_state.choch_bull=false;
      m_state.choch_bear=false;

      const AWSwingPoint sh0=LastSwingOfType(AW_SWING_HIGH,0);
      const AWSwingPoint sh1=LastSwingOfType(AW_SWING_HIGH,1);
      const AWSwingPoint sl0=LastSwingOfType(AW_SWING_LOW,0);
      const AWSwingPoint sl1=LastSwingOfType(AW_SWING_LOW,1);

      if(sh0.valid)
        {
         m_state.last_swing_high=sh0.price;
         m_state.last_swing_high_time=sh0.time;
         if(sh1.valid)
           {
            if(sh0.price>sh1.price) m_state.last_event=AW_EVT_HH;
            else if(sh0.price<sh1.price) m_state.last_event=AW_EVT_LH;
           }
        }
      if(sl0.valid)
        {
         m_state.last_swing_low=sl0.price;
         m_state.last_swing_low_time=sl0.time;
         if(sl1.valid)
           {
            if(sl0.price>sl1.price)
               m_state.last_event=(m_state.last_event==AW_EVT_NONE?AW_EVT_HL:m_state.last_event);
            else if(sl0.price<sl1.price)
               m_state.last_event=(m_state.last_event==AW_EVT_NONE?AW_EVT_LL:m_state.last_event);
           }
        }

      // Structure bias from recent swing pairs — do not force if mixed
      bool bull_struct=false;
      bool bear_struct=false;
      if(sh0.valid && sh1.valid && sl0.valid && sl1.valid)
        {
         bull_struct=(sh0.price>sh1.price && sl0.price>sl1.price);
         bear_struct=(sh0.price<sh1.price && sl0.price<sl1.price);
        }
      else if(sh0.valid && sh1.valid && sl0.valid)
        {
         // partial: HH with rising low vs LH with falling low
         if(sh0.price>sh1.price && sl1.valid && sl0.price>=sl1.price) bull_struct=true;
         if(sh0.price<sh1.price && sl1.valid && sl0.price<=sl1.price) bear_struct=true;
        }

      if(bull_struct && !bear_struct) m_state.bias=AW_BIAS_BULL;
      else if(bear_struct && !bull_struct) m_state.bias=AW_BIAS_BEAR;
      else m_state.bias=AW_BIAS_NEUTRAL;

      // BOS / CHoCH on closed bar close
      const double c=closed_bar.close;
      if(sh0.valid && c>sh0.price)
        {
         if(m_state.bias==AW_BIAS_BEAR || m_state.bias==AW_BIAS_NEUTRAL)
           {
            // break upward against bearish / unclear -> CHoCH bullish or BOS if already bullish building
            if(m_state.bias==AW_BIAS_BEAR)
              {
               m_state.choch_bull=true;
               m_state.last_event=AW_EVT_CHOCH;
               m_state.bias=AW_BIAS_BULL;
              }
            else
              {
               m_state.bos_bull=true;
               m_state.last_event=AW_EVT_BOS;
              }
           }
         else if(m_state.bias==AW_BIAS_BULL)
           {
            m_state.bos_bull=true;
            m_state.last_event=AW_EVT_BOS;
           }
         m_state.last_event_time=closed_bar.time;
        }
      else if(sl0.valid && c<sl0.price)
        {
         if(m_state.bias==AW_BIAS_BULL)
           {
            m_state.choch_bear=true;
            m_state.last_event=AW_EVT_CHOCH;
            m_state.bias=AW_BIAS_BEAR;
           }
         else
           {
            m_state.bos_bear=true;
            m_state.last_event=AW_EVT_BOS;
            if(m_state.bias==AW_BIAS_NEUTRAL)
               m_state.bias=AW_BIAS_BEAR;
           }
         m_state.last_event_time=closed_bar.time;
        }
     }

public:
                     CAWTfStructureEngine(void)
     {
      m_symbol="";
      m_tf=PERIOD_M15;
      m_swing_left=2;
      m_swing_right=2;
      m_lookback=300;
      ClearSwings();
      ZeroMemory(m_state);
      m_last_processed_bar=0;
     }

   void Configure(const string symbol,const ENUM_TIMEFRAMES tf,
                  const int swing_left,const int swing_right,const int lookback)
     {
      m_symbol=symbol;
      m_tf=tf;
      m_swing_left=MathMax(1,swing_left);
      m_swing_right=MathMax(1,swing_right);
      m_lookback=MathMax(50,lookback);
     }

   void Reset(void)
     {
      ClearSwings();
      ZeroMemory(m_state);
      m_last_processed_bar=0;
     }

   void Rebuild(void)
     {
      ClearSwings();
      ZeroMemory(m_state);
      MqlRates rates[];
      ArraySetAsSeries(rates,true);
      const int need=m_lookback;
      const int got=CopyRates(m_symbol,m_tf,0,need,rates);
      if(got<m_swing_left+m_swing_right+5)
         return;

      // Scan from oldest confirmed pivot to newest
      for(int i=got-1-m_swing_left;i>=m_swing_right;i--)
        {
         if(IsSwingHigh(rates,i,got))
           {
            AWSwingPoint s;
            ZeroMemory(s);
            s.valid=true;
            s.type=AW_SWING_HIGH;
            s.price=rates[i].high;
            s.time=rates[i].time;
            s.bar_index=i;
            PushSwing(s);
           }
         if(IsSwingLow(rates,i,got))
           {
            AWSwingPoint s;
            ZeroMemory(s);
            s.valid=true;
            s.type=AW_SWING_LOW;
            s.price=rates[i].low;
            s.time=rates[i].time;
            s.bar_index=i;
            PushSwing(s);
           }
        }

      if(got>=2)
        {
         ClassifyAndEvents(rates[1]);
         m_last_processed_bar=rates[1].time;
        }
     }

   void Update(void)
     {
      MqlRates rates[];
      ArraySetAsSeries(rates,true);
      const int got=CopyRates(m_symbol,m_tf,0,m_lookback,rates);
      if(got<m_swing_left+m_swing_right+5)
         return;

      if(m_swing_count==0)
         Rebuild();

      if(rates[1].time==m_last_processed_bar)
         return;
      m_last_processed_bar=rates[1].time;

      // Check newly confirmed pivot at index = m_swing_right (just confirmed)
      const int pivot=m_swing_right;
      if(IsSwingHigh(rates,pivot,got))
        {
         AWSwingPoint s;
         ZeroMemory(s);
         s.valid=true;
         s.type=AW_SWING_HIGH;
         s.price=rates[pivot].high;
         s.time=rates[pivot].time;
         s.bar_index=pivot;
         // avoid duplicate same time
         if(m_swing_count==0 || m_swings[m_swing_count-1].time!=s.time || m_swings[m_swing_count-1].type!=s.type)
            PushSwing(s);
        }
      if(IsSwingLow(rates,pivot,got))
        {
         AWSwingPoint s;
         ZeroMemory(s);
         s.valid=true;
         s.type=AW_SWING_LOW;
         s.price=rates[pivot].low;
         s.time=rates[pivot].time;
         s.bar_index=pivot;
         if(m_swing_count==0 || m_swings[m_swing_count-1].time!=s.time || m_swings[m_swing_count-1].type!=s.type)
            PushSwing(s);
        }

      ClassifyAndEvents(rates[1]);
     }

   AWTfStructureState State(void) const { return m_state; }
   int SwingCount(void) const { return m_swing_count; }

   bool GetSwing(const int from_end,AWSwingPoint &out) const
     {
      if(from_end<0 || from_end>=m_swing_count) return false;
      out=m_swings[m_swing_count-1-from_end];
      return out.valid;
     }

   bool GetLastNSwings(const int n,AWSwingPoint &out[]) const
     {
      const int take=MathMin(n,m_swing_count);
      ArrayResize(out,take);
      for(int i=0;i<take;i++)
         out[i]=m_swings[m_swing_count-take+i];
      return(take>0);
     }
  };

class CAWMarketStructure
  {
private:
   string            m_symbol;
   CAWLogger        *m_logger;
   bool              m_enable_h4;
   bool              m_enable_h1;
   bool              m_enable_m15;
   int               m_swing_left;
   int               m_swing_right;
   int               m_lookback;

   CAWTfStructureEngine m_h4;
   CAWTfStructureEngine m_h1;
   CAWTfStructureEngine m_m15;

public:
                     CAWMarketStructure(void)
     {
      m_symbol="";
      m_logger=NULL;
      m_enable_h4=true;
      m_enable_h1=true;
      m_enable_m15=true;
      m_swing_left=2;
      m_swing_right=2;
      m_lookback=300;
     }

   bool Init(const string symbol,
             CAWLogger *logger,
             const bool enable_h4,
             const bool enable_h1,
             const bool enable_m15,
             const int swing_left,
             const int swing_right,
             const int lookback)
     {
      m_symbol=symbol;
      m_logger=logger;
      m_enable_h4=enable_h4;
      m_enable_h1=enable_h1;
      m_enable_m15=enable_m15;
      m_swing_left=MathMax(1,swing_left);
      m_swing_right=MathMax(1,swing_right);
      m_lookback=MathMax(50,lookback);

      m_h4.Configure(symbol,PERIOD_H4,m_swing_left,m_swing_right,m_lookback);
      m_h1.Configure(symbol,PERIOD_H1,m_swing_left,m_swing_right,m_lookback);
      m_m15.Configure(symbol,PERIOD_M15,m_swing_left,m_swing_right,m_lookback);

      if(m_logger!=NULL)
         m_logger.Info("MarketStructure",
                       StringFormat("initialized L=%d R=%d lookback=%d",
                                    m_swing_left,m_swing_right,m_lookback));
      return true;
     }

   void DailyReset(const AWDailyContext &ctx)
     {
      AW_UNUSED(ctx);
      // Structure is multi-day; rebuild from history rather than wipe bias blindly.
      if(m_enable_h4) m_h4.Rebuild();
      if(m_enable_h1) m_h1.Rebuild();
      if(m_enable_m15) m_m15.Rebuild();
      if(m_logger!=NULL)
         m_logger.Debug("MarketStructure","DailyReset rebuild");
     }

   void Update(void)
     {
      if(m_enable_h4) m_h4.Update();
      if(m_enable_h1) m_h1.Update();
      if(m_enable_m15) m_m15.Update();
     }

   ENUM_AW_BIAS GetH4Bias(void) const { return(m_enable_h4? m_h4.State().bias : AW_BIAS_NEUTRAL); }
   ENUM_AW_BIAS GetH1Bias(void) const { return(m_enable_h1? m_h1.State().bias : AW_BIAS_NEUTRAL); }
   ENUM_AW_BIAS GetM15Bias(void) const { return(m_enable_m15? m_m15.State().bias : AW_BIAS_NEUTRAL); }

   AWTfStructureState H4State(void) const { return m_h4.State(); }
   AWTfStructureState H1State(void) const { return m_h1.State(); }
   AWTfStructureState M15State(void) const { return m_m15.State(); }

   CAWTfStructureEngine *M15Engine(void) { return &m_m15; }
   CAWTfStructureEngine *M5EngineProxy(void) { return NULL; } // M5 handled in Confirmation

   bool GetM15Swings(const int n,AWSwingPoint &out[]) const
     {
      return m_m15.GetLastNSwings(n,out);
     }
  };

#endif
//+------------------------------------------------------------------+
