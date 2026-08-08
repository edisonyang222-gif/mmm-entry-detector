//+------------------------------------------------------------------+
//| AW_SessionManager.mqh                                             |
//| UTC+8 sessions, PDH/PDL, day/session opens & ranges               |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_SESSION_MANAGER_MQH
#define AW_SESSION_MANAGER_MQH

#include "AW_Common.mqh"
#include "AW_Logger.mqh"
#include "AW_TimeManager.mqh"

class CAWSessionManager
  {
private:
   string            m_symbol;
   CAWLogger        *m_logger;
   CAWTimeManager   *m_time;

   bool              m_enable_asia;
   bool              m_enable_london;
   bool              m_enable_ny;
   int               m_asia_start_min;
   int               m_asia_end_min;
   int               m_london_start_min;
   int               m_london_end_min;
   int               m_ny_start_min;
   int               m_ny_end_min;

   AWSessionLevels   m_levels;
   datetime          m_day_key;
   datetime          m_last_m5_bar;

   bool              InWindow(const int mins,const int start_min,const int end_min) const
     {
      if(start_min==end_min) return false;
      if(start_min<end_min) return(mins>=start_min && mins<end_min);
      return(mins>=start_min || mins<end_min);
     }

   ENUM_AW_SESSION_ID DetectActive(const int mins) const
     {
      // Priority when overlapping: NY > London > Asia (display only)
      if(m_enable_ny && InWindow(mins,m_ny_start_min,m_ny_end_min))
         return AW_SESS_NY;
      if(m_enable_london && InWindow(mins,m_london_start_min,m_london_end_min))
         return AW_SESS_LONDON;
      if(m_enable_asia && InWindow(mins,m_asia_start_min,m_asia_end_min))
         return AW_SESS_ASIA;
      return AW_SESS_NONE;
     }

   bool CopyM5Range(const datetime from_server,const datetime to_server,
                    double &out_high,double &out_low,double &out_open,bool &ok)
     {
      ok=false;
      out_high=0.0;
      out_low=0.0;
      out_open=0.0;
      if(from_server<=0 || to_server<=from_server)
         return false;

      MqlRates rates[];
      ArraySetAsSeries(rates,true);
      const int need = (int)MathMax(10, (to_server-from_server)/300 + 5);
      const int got = CopyRates(m_symbol,PERIOD_M5,from_server,to_server,rates);
      if(got<=0)
        {
         // fallback: copy by count from current
         const int n = CopyRates(m_symbol,PERIOD_M5,0,MathMin(need,500),rates);
         if(n<=0) return false;
         bool any=false;
         double hi=-DBL_MAX, lo=DBL_MAX;
         double opn=0.0;
         datetime first_t=0;
         for(int i=n-1;i>=0;i--)
           {
            if(rates[i].time<from_server || rates[i].time>=to_server)
               continue;
            if(!any)
              {
               opn=rates[i].open;
               first_t=rates[i].time;
               any=true;
              }
            if(rates[i].time<=first_t)
              {
               first_t=rates[i].time;
               opn=rates[i].open;
              }
            if(rates[i].high>hi) hi=rates[i].high;
            if(rates[i].low<lo) lo=rates[i].low;
           }
         if(!any) return false;
         out_high=hi;
         out_low=lo;
         out_open=opn;
         ok=true;
         return true;
        }

      double hi=-DBL_MAX, lo=DBL_MAX;
      double opn=rates[got-1].open;
      datetime earliest=rates[got-1].time;
      for(int i=0;i<got;i++)
        {
         if(rates[i].time<from_server || rates[i].time>=to_server)
            continue;
         if(rates[i].time<=earliest)
           {
            earliest=rates[i].time;
            opn=rates[i].open;
           }
         if(rates[i].high>hi) hi=rates[i].high;
         if(rates[i].low<lo) lo=rates[i].low;
        }
      if(hi==-DBL_MAX) return false;
      out_high=hi;
      out_low=lo;
      out_open=opn;
      ok=true;
      return true;
     }

   void UpdateLiveSessionHL(const ENUM_AW_SESSION_ID sess,const double bid_high,const double bid_low,const double bid)
     {
      if(sess==AW_SESS_ASIA && m_enable_asia)
        {
         if(!m_levels.asia_ready)
           {
            m_levels.asia_open=bid;
            m_levels.asia_high=bid_high;
            m_levels.asia_low=bid_low;
            m_levels.asia_ready=true;
           }
         else
           {
            if(bid_high>m_levels.asia_high) m_levels.asia_high=bid_high;
            if(bid_low<m_levels.asia_low) m_levels.asia_low=bid_low;
           }
        }
      else if(sess==AW_SESS_LONDON && m_enable_london)
        {
         if(!m_levels.london_ready)
           {
            m_levels.london_open=bid;
            m_levels.london_high=bid_high;
            m_levels.london_low=bid_low;
            m_levels.london_ready=true;
           }
         else
           {
            if(bid_high>m_levels.london_high) m_levels.london_high=bid_high;
            if(bid_low<m_levels.london_low) m_levels.london_low=bid_low;
           }
        }
      else if(sess==AW_SESS_NY && m_enable_ny)
        {
         if(!m_levels.ny_ready)
           {
            m_levels.ny_open=bid;
            m_levels.ny_high=bid_high;
            m_levels.ny_low=bid_low;
            m_levels.ny_ready=true;
           }
         else
           {
            if(bid_high>m_levels.ny_high) m_levels.ny_high=bid_high;
            if(bid_low<m_levels.ny_low) m_levels.ny_low=bid_low;
           }
        }
     }

   void RebuildDayLevels(const datetime day_key_trade)
     {
      // day_key_trade is UTC+8 04:45 of current session day
      const datetime cur_start_server = m_time.TradeTzToServer(day_key_trade);
      const datetime prev_start_server = m_time.TradeTzToServer(day_key_trade-86400);
      const datetime now_server = m_time.NowServer();

      double hi,lo,opn;
      bool ok=false;

      // Previous day range -> PDH/PDL/PDO
      if(CopyM5Range(prev_start_server,cur_start_server,hi,lo,opn,ok) && ok)
        {
         m_levels.pdh=hi;
         m_levels.pdl=lo;
         m_levels.prev_day_open=opn;
         m_levels.day_levels_ready=true;
        }

      // Current day open
      if(CopyM5Range(cur_start_server,MathMax(cur_start_server+300,now_server+1),hi,lo,opn,ok) && ok)
         m_levels.curr_day_open=opn;
      else
        {
         MqlRates r[];
         if(CopyRates(m_symbol,PERIOD_M5,cur_start_server,1,r)==1)
            m_levels.curr_day_open=r[0].open;
        }

      // Seed session ranges from history for current day windows
      SeedSessionFromHistory(AW_SESS_ASIA,m_asia_start_min,m_asia_end_min,day_key_trade);
      SeedSessionFromHistory(AW_SESS_LONDON,m_london_start_min,m_london_end_min,day_key_trade);
      SeedSessionFromHistory(AW_SESS_NY,m_ny_start_min,m_ny_end_min,day_key_trade);
     }

   datetime WindowStartServer(const datetime day_key_trade,const int start_min) const
     {
      // Map session window minutes-of-UTC+8-calendar-day into server time.
      // Sessions may start before/after 04:45; we bind them to the calendar date
      // of (day_key) unless start_min < session start minutes, then next calendar day.
      MqlDateTime dt;
      TimeToStruct(day_key_trade,dt);
      const int day_start_min = dt.hour*60+dt.min; // typically 4*60+45
      datetime base_midnight = day_key_trade - day_start_min*60;
      datetime win = base_midnight + start_min*60;
      // If window start is before the trading day key and not overnight-style wrap,
      // keep as-is (Asia can start at 04:45). Overnight NY end handled by InWindow.
      if(start_min < day_start_min && start_min+24*60 > day_start_min)
        {
         // e.g. NY ending after midnight: start still on same/previous logic via caller
        }
      return m_time.TradeTzToServer(win);
     }

   void SeedSessionFromHistory(const ENUM_AW_SESSION_ID id,const int start_min,const int end_min,const datetime day_key_trade)
     {
      if(id==AW_SESS_ASIA && !m_enable_asia) return;
      if(id==AW_SESS_LONDON && !m_enable_london) return;
      if(id==AW_SESS_NY && !m_enable_ny) return;

      const datetime now_server=m_time.NowServer();
      datetime from_s = WindowStartServer(day_key_trade,start_min);
      datetime to_s;
      if(start_min<end_min)
         to_s = WindowStartServer(day_key_trade,end_min);
      else
         to_s = WindowStartServer(day_key_trade,end_min)+86400;

      if(now_server<=from_s)
         return;
      if(to_s>now_server) to_s=now_server+1;

      double hi,lo,opn;
      bool ok=false;
      if(!CopyM5Range(from_s,to_s,hi,lo,opn,ok) || !ok)
         return;

      if(id==AW_SESS_ASIA)
        {
         m_levels.asia_high=hi; m_levels.asia_low=lo; m_levels.asia_open=opn; m_levels.asia_ready=true;
        }
      else if(id==AW_SESS_LONDON)
        {
         m_levels.london_high=hi; m_levels.london_low=lo; m_levels.london_open=opn; m_levels.london_ready=true;
        }
      else if(id==AW_SESS_NY)
        {
         m_levels.ny_high=hi; m_levels.ny_low=lo; m_levels.ny_open=opn; m_levels.ny_ready=true;
        }
     }

   void ResetSessionTracks(void)
     {
      m_levels.asia_high=0; m_levels.asia_low=0; m_levels.asia_open=0; m_levels.asia_ready=false;
      m_levels.london_high=0; m_levels.london_low=0; m_levels.london_open=0; m_levels.london_ready=false;
      m_levels.ny_high=0; m_levels.ny_low=0; m_levels.ny_open=0; m_levels.ny_ready=false;
      m_levels.active=AW_SESS_NONE;
     }

public:
                     CAWSessionManager(void)
     {
      m_symbol="";
      m_logger=NULL;
      m_time=NULL;
      m_enable_asia=true;
      m_enable_london=true;
      m_enable_ny=true;
      m_asia_start_min=285;   // 04:45
      m_asia_end_min=720;     // 12:00
      m_london_start_min=900; // 15:00
      m_london_end_min=1260;  // 21:00
      m_ny_start_min=1200;   // 20:00
      m_ny_end_min=150;      // 02:30 next day
      ZeroMemory(m_levels);
      m_day_key=0;
      m_last_m5_bar=0;
     }

   bool Init(const string symbol,
             CAWLogger *logger,
             CAWTimeManager *time_mgr,
             const bool enable_asia,
             const bool enable_london,
             const bool enable_ny,
             const int asia_start_min,
             const int asia_end_min,
             const int london_start_min,
             const int london_end_min,
             const int ny_start_min,
             const int ny_end_min)
     {
      m_symbol=symbol;
      m_logger=logger;
      m_time=time_mgr;
      m_enable_asia=enable_asia;
      m_enable_london=enable_london;
      m_enable_ny=enable_ny;
      m_asia_start_min=asia_start_min;
      m_asia_end_min=asia_end_min;
      m_london_start_min=london_start_min;
      m_london_end_min=london_end_min;
      m_ny_start_min=ny_start_min;
      m_ny_end_min=ny_end_min;
      if(m_logger!=NULL)
         m_logger.Info("SessionManager","initialized");
      return true;
     }

   void DailyReset(const AWDailyContext &ctx)
     {
      m_day_key=ctx.sessionDayKey;
      ResetSessionTracks();
      m_levels.pdh=0; m_levels.pdl=0;
      m_levels.prev_day_open=0; m_levels.curr_day_open=0;
      m_levels.day_levels_ready=false;
      if(m_time!=NULL && m_day_key>0)
         RebuildDayLevels(m_day_key);
      if(m_logger!=NULL)
         m_logger.Info("SessionManager",
                       StringFormat("DailyReset dayKey=%s PDH=%s PDL=%s CDO=%s",
                                    TimeToString(m_day_key,TIME_DATE|TIME_MINUTES),
                                    AW_PriceOrNA(m_levels.pdh,(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS)),
                                    AW_PriceOrNA(m_levels.pdl,(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS)),
                                    AW_PriceOrNA(m_levels.curr_day_open,(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS))));
     }

   void Update(void)
     {
      if(m_time==NULL) return;

      const datetime now=m_time.NowServer();
      const int mins=m_time.Utc8MinutesOfDay(now);
      m_levels.active=DetectActive(mins);

      MqlRates rates[];
      ArraySetAsSeries(rates,true);
      if(CopyRates(m_symbol,PERIOD_M5,0,3,rates)<2)
         return;

      // Use latest closed M5 for HL updates to reduce noise; also tick bid for open seed
      const double bid = SymbolInfoDouble(m_symbol,SYMBOL_BID);
      const double bar_high = rates[1].high;
      const double bar_low  = rates[1].low;

      if(rates[1].time!=m_last_m5_bar)
        {
         m_last_m5_bar=rates[1].time;
         // Map closed bar session by its own UTC+8 time
         const int bar_mins=m_time.Utc8MinutesOfDay(rates[1].time);
         const ENUM_AW_SESSION_ID bar_sess=DetectActive(bar_mins);
         UpdateLiveSessionHL(bar_sess,bar_high,bar_low,rates[1].open);
        }

      // Soft live update on forming bar within active session
      if(m_levels.active!=AW_SESS_NONE)
        {
         MqlRates cur[];
         ArraySetAsSeries(cur,true);
         if(CopyRates(m_symbol,PERIOD_M5,0,1,cur)==1)
            UpdateLiveSessionHL(m_levels.active,cur[0].high,cur[0].low,bid);
        }
     }

   AWSessionLevels Levels(void) const { return m_levels; }
   string ActiveSessionName(void) const { return AW_SessionToText(m_levels.active); }
   ENUM_AW_SESSION_ID ActiveSession(void) const { return m_levels.active; }
   bool IsTradableSession(void) const { return(m_levels.active!=AW_SESS_NONE); }
  };

#endif
//+------------------------------------------------------------------+
