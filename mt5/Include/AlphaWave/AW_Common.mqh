//+------------------------------------------------------------------+
//| AW_Common.mqh                                                     |
//| Alpha Wave — shared types / constants                             |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_COMMON_MQH
#define AW_COMMON_MQH

#define AW_VERSION_LITE          1
#define AW_VERSION_PRO           2
#define AW_VERSION_INSTITUTIONAL 3

#define AW_PRODUCT_NAME          "Alpha Wave"
#define AW_DEFAULT_SYMBOL        "XAUUSD"

#define AW_UNUSED(x) ((void)(x))

enum ENUM_AW_LOG_LEVEL
  {
   AW_LOG_DEBUG = 0,
   AW_LOG_INFO  = 1,
   AW_LOG_WARN  = 2,
   AW_LOG_ERROR = 3
  };

enum ENUM_AW_EDITION
  {
   AW_EDITION_LITE          = AW_VERSION_LITE,
   AW_EDITION_PRO           = AW_VERSION_PRO,
   AW_EDITION_INSTITUTIONAL = AW_VERSION_INSTITUTIONAL
  };

enum ENUM_AW_BIAS
  {
   AW_BIAS_NEUTRAL = 0,
   AW_BIAS_BULL    = 1,
   AW_BIAS_BEAR    = -1
  };

enum ENUM_AW_SIGNAL_DIR
  {
   AW_SIGNAL_NONE = 0,
   AW_SIGNAL_BUY  = 1,
   AW_SIGNAL_SELL = -1
  };

enum ENUM_AW_TF_ROLE
  {
   AW_TF_H4  = 0,
   AW_TF_H1  = 1,
   AW_TF_M15 = 2,
   AW_TF_M5  = 3
  };

enum ENUM_AW_SWING_TYPE
  {
   AW_SWING_NONE = 0,
   AW_SWING_HIGH = 1,
   AW_SWING_LOW  = -1
  };

enum ENUM_AW_STRUCTURE_EVENT
  {
   AW_EVT_NONE  = 0,
   AW_EVT_HH    = 1,
   AW_EVT_HL    = 2,
   AW_EVT_LH    = 3,
   AW_EVT_LL    = 4,
   AW_EVT_BOS   = 5,
   AW_EVT_CHOCH = 6
  };

enum ENUM_AW_SESSION_ID
  {
   AW_SESS_NONE   = 0,
   AW_SESS_ASIA   = 1,
   AW_SESS_LONDON = 2,
   AW_SESS_NY     = 3
  };

enum ENUM_AW_SWEEP_TYPE
  {
   AW_SWEEP_NONE         = 0,
   AW_SWEEP_PDH          = 1,
   AW_SWEEP_PDL          = 2,
   AW_SWEEP_ASIA_HIGH    = 3,
   AW_SWEEP_ASIA_LOW     = 4,
   AW_SWEEP_LONDON_HIGH  = 5,
   AW_SWEEP_LONDON_LOW   = 6
  };

enum ENUM_AW_CONFIRM_TYPE
  {
   AW_CONF_NONE          = 0,
   AW_CONF_ENGULFING     = 1,
   AW_CONF_PINBAR        = 2,
   AW_CONF_REJECTION     = 3,
   AW_CONF_BOS           = 4,
   AW_CONF_CHOCH         = 5
  };

enum ENUM_AW_SCORE_BAND
  {
   AW_SCORE_NO_TRADE     = 0,
   AW_SCORE_LOW_QUALITY  = 1,
   AW_SCORE_VALID        = 2,
   AW_SCORE_APLUS        = 3
  };

enum ENUM_AW_UI_STATUS
  {
   AW_UI_WAIT   = 0,
   AW_UI_WATCH  = 1,
   AW_UI_VALID  = 2,
   AW_UI_APLUS  = 3
  };

struct AWModuleSwitches
  {
   bool enableMarketStructure;
   bool enableSessionManager;
   bool enableLiquidityManager;
   bool enableFibManager;
   bool enableSetupDetector;
   bool enableConfirmation;
   bool enableTradeScore;
   bool enableRiskManager;
   bool enableTradeManager;
   bool enableStatistics;
  };

struct AWDailyContext
  {
   datetime sessionDayKey;
   datetime lastResetTime;
   bool     resetDone;
  };

struct AWSwingPoint
  {
   datetime time;
   double   price;
   int      bar_index;   // shift at detection time (informational)
   ENUM_AW_SWING_TYPE type;
   bool     valid;
  };

struct AWTfStructureState
  {
   ENUM_AW_BIAS           bias;
   ENUM_AW_STRUCTURE_EVENT last_event;
   datetime               last_event_time;
   double                 last_swing_high;
   double                 last_swing_low;
   datetime               last_swing_high_time;
   datetime               last_swing_low_time;
   bool                   bos_bull;
   bool                   bos_bear;
   bool                   choch_bull;
   bool                   choch_bear;
  };

struct AWSessionLevels
  {
   double   asia_high;
   double   asia_low;
   double   asia_open;
   bool     asia_ready;
   double   london_high;
   double   london_low;
   double   london_open;
   bool     london_ready;
   double   ny_high;
   double   ny_low;
   double   ny_open;
   bool     ny_ready;
   double   pdh;
   double   pdl;
   double   prev_day_open;
   double   curr_day_open;
   bool     day_levels_ready;
   ENUM_AW_SESSION_ID active;
  };

struct AWSweepState
  {
   bool pdh;
   bool pdl;
   bool asia_high;
   bool asia_low;
   bool london_high;
   bool london_low;
   ENUM_AW_SWEEP_TYPE last_type;
   datetime           last_time;
   string             last_name;
  };

struct AWFibSetupState
  {
   bool              active;
   bool              ready;          // two-leg trend established
   bool              in_zone;        // price near 0.5
   bool              two_leg_pullback;
   ENUM_AW_SIGNAL_DIR direction;
   double            anchor0;        // fib 0
   double            anchor1;        // fib 1
   double            lvl_0;
   double            lvl_25;
   double            lvl_50;
   double            lvl_618;
   double            lvl_75;
   double            lvl_100;
   datetime          created_time;
   string            reason;
  };

struct AWConfirmState
  {
   bool                 active;
   ENUM_AW_CONFIRM_TYPE type;
   ENUM_AW_SIGNAL_DIR   direction;
   datetime             bar_time;
   string               name;
  };

struct AWScoreState
  {
   int                 score;
   ENUM_AW_SCORE_BAND  band;
   ENUM_AW_UI_STATUS   ui_status;
   ENUM_AW_SIGNAL_DIR  direction;
   string              breakdown;
   string              setup_name;
  };

void AW_InitModuleSwitches(AWModuleSwitches &sw)
  {
   sw.enableMarketStructure  = true;
   sw.enableSessionManager   = true;
   sw.enableLiquidityManager = true;
   sw.enableFibManager       = true;
   sw.enableSetupDetector    = true;
   sw.enableConfirmation     = true;
   sw.enableTradeScore       = true;
   sw.enableRiskManager      = true;
   sw.enableTradeManager     = false;
   sw.enableStatistics       = true;
  }

string AW_BiasToText(const ENUM_AW_BIAS b)
  {
   if(b==AW_BIAS_BULL) return "Bullish";
   if(b==AW_BIAS_BEAR) return "Bearish";
   return "Neutral";
  }

string AW_SignalDirToText(const ENUM_AW_SIGNAL_DIR d)
  {
   if(d==AW_SIGNAL_BUY)  return "BUY";
   if(d==AW_SIGNAL_SELL) return "SELL";
   return "NONE";
  }

string AW_EditionToText(const ENUM_AW_EDITION e)
  {
   if(e==AW_EDITION_PRO) return "Pro";
   if(e==AW_EDITION_INSTITUTIONAL) return "Institutional";
   return "Lite";
  }

string AW_ScoreBandToText(const ENUM_AW_SCORE_BAND b)
  {
   if(b==AW_SCORE_APLUS) return "A+ SETUP";
   if(b==AW_SCORE_VALID) return "VALID SETUP";
   if(b==AW_SCORE_LOW_QUALITY) return "LOW QUALITY";
   return "NO TRADE";
  }

string AW_UiStatusToText(const ENUM_AW_UI_STATUS s)
  {
   if(s==AW_UI_APLUS) return "A+";
   if(s==AW_UI_VALID) return "VALID";
   if(s==AW_UI_WATCH) return "WATCH";
   return "WAIT";
  }

string AW_ConfirmToText(const ENUM_AW_CONFIRM_TYPE t)
  {
   switch(t)
     {
      case AW_CONF_ENGULFING: return "Engulfing";
      case AW_CONF_PINBAR:    return "PinBar";
      case AW_CONF_REJECTION: return "Rejection";
      case AW_CONF_BOS:       return "BOS";
      case AW_CONF_CHOCH:     return "CHoCH";
     }
   return "None";
  }

string AW_SweepToText(const ENUM_AW_SWEEP_TYPE t)
  {
   switch(t)
     {
      case AW_SWEEP_PDH:         return "PDH Sweep";
      case AW_SWEEP_PDL:         return "PDL Sweep";
      case AW_SWEEP_ASIA_HIGH:   return "Asia High Sweep";
      case AW_SWEEP_ASIA_LOW:    return "Asia Low Sweep";
      case AW_SWEEP_LONDON_HIGH: return "London High Sweep";
      case AW_SWEEP_LONDON_LOW:  return "London Low Sweep";
     }
   return "None";
  }

string AW_SessionToText(const ENUM_AW_SESSION_ID s)
  {
   if(s==AW_SESS_ASIA) return "Asia";
   if(s==AW_SESS_LONDON) return "London";
   if(s==AW_SESS_NY) return "NewYork";
   return "None";
  }

string AW_PriceOrNA(const double v, const int digits)
  {
   if(v<=0.0) return "n/a";
   return DoubleToString(v,digits);
  }

ENUM_AW_SCORE_BAND AW_ScoreToBand(const int score)
  {
   if(score>=85) return AW_SCORE_APLUS;
   if(score>=70) return AW_SCORE_VALID;
   if(score>=50) return AW_SCORE_LOW_QUALITY;
   return AW_SCORE_NO_TRADE;
  }

ENUM_AW_UI_STATUS AW_BandToUi(const ENUM_AW_SCORE_BAND b)
  {
   if(b==AW_SCORE_APLUS) return AW_UI_APLUS;
   if(b==AW_SCORE_VALID) return AW_UI_VALID;
   if(b==AW_SCORE_LOW_QUALITY) return AW_UI_WATCH;
   return AW_UI_WAIT;
  }

#endif
//+------------------------------------------------------------------+
