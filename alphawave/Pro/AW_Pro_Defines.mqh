//+------------------------------------------------------------------+
//| AW_Pro_Defines.mqh                                               |
//| Alpha Wave Pro — Core definitions (DO NOT replace / overturn)    |
//+------------------------------------------------------------------+
#ifndef AW_PRO_DEFINES_MQH
#define AW_PRO_DEFINES_MQH

enum ENUM_AW_DIR
{
   AW_DIR_NONE = 0,
   AW_DIR_BUY  = 1,
   AW_DIR_SELL = -1
};

enum ENUM_AW_SETUP_ID
{
   AW_SETUP_NONE = 0,
   AW_SETUP_FIB_SWEEP_ENGULFING = 1,
   AW_SETUP_FIB_SWEEP_BOS       = 2,
   AW_SETUP_FIB_CHOCH           = 3,
   AW_SETUP_SWEEP_BOS           = 4,
   AW_SETUP_SWEEP_ENGULFING     = 5,
   AW_SETUP_FIB_ENGULFING       = 6,
   AW_SETUP_COUNT               = 7
};

struct AWProSwing
{
   datetime time;
   double   price;
   int      bar;
   bool     isHigh;
};

struct AWProSignal
{
   bool              valid;
   ENUM_AW_DIR       direction;
   ENUM_AW_SETUP_ID  setupId;
   string            setupName;
   datetime          signalTime;   // time of CLOSED bar that confirmed signal
   int               signalBar;    // shift of closed bar (always >= 1 at detect)
   double            entry;
   double            sl;
   double            tp1;
   double            tp2;
   double            fibLevel;
   bool              hasSweep;
   bool              hasBos;
   bool              hasChoch;
   bool              hasEngulfing;
   bool              hasFib;
   int               confirmStrength; // 1-5
   string            note;
};

string AW_Pro_SetupName(const ENUM_AW_SETUP_ID id)
{
   switch(id)
   {
      case AW_SETUP_FIB_SWEEP_ENGULFING: return "Fib+Sweep+Engulfing";
      case AW_SETUP_FIB_SWEEP_BOS:       return "Fib+Sweep+BOS";
      case AW_SETUP_FIB_CHOCH:           return "Fib+CHoCH";
      case AW_SETUP_SWEEP_BOS:           return "Sweep+BOS";
      case AW_SETUP_SWEEP_ENGULFING:     return "Sweep+Engulfing";
      case AW_SETUP_FIB_ENGULFING:       return "Fib+Engulfing";
      default:                           return "None";
   }
}

#endif
