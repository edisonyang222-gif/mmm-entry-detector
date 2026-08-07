//+------------------------------------------------------------------+
//| AW_Pro_Engine.mqh                                                |
//| Alpha Wave Pro — setup engine API (Institutional consumes this)  |
//| Pro is standalone: Institutional must NOT overturn this module   |
//+------------------------------------------------------------------+
#ifndef AW_PRO_ENGINE_MQH
#define AW_PRO_ENGINE_MQH

#include "AW_Pro_Defines.mqh"
#include "AW_Pro_Structure.mqh"
#include "AW_Pro_Liquidity.mqh"
#include "AW_Pro_Fib.mqh"
#include "AW_Pro_Confirmations.mqh"

struct AWProConfig
{
   string          symbol;
   ENUM_TIMEFRAMES entryTf;
   ENUM_TIMEFRAMES htfTf;
   int             swingLeft;
   int             swingRight;
   int             structLookback;
   int             sweepLookback;
   double          sweepWickMinAtr;
   double          fibLow;
   double          fibHigh;
   double          slAtrMult;
   double          tp1AtrMult;
   double          tp2AtrMult;
   bool            enableFibSweepEngulfing;
   bool            enableFibSweepBos;
   bool            enableFibChoch;
   bool            enableSweepBos;
   bool            enableSweepEngulfing;
   bool            enableFibEngulfing;
};

class CAWProEngine
{
private:
   AWProConfig         m_cfg;
   CAWProStructure     m_stEntry;
   CAWProStructure     m_stHtf;
   CAWProLiquidity     m_liq;
   CAWProFib           m_fib;
   CAWProConfirmations m_conf;
   int                 m_atrHandle;
   datetime            m_lastSignalBarTime; // duplicate trade guard

public:
   CAWProEngine(): m_atrHandle(INVALID_HANDLE), m_lastSignalBarTime(0) {}

   ~CAWProEngine()
   {
      if(m_atrHandle != INVALID_HANDLE)
         IndicatorRelease(m_atrHandle);
   }

   bool Init(const AWProConfig &cfg)
   {
      m_cfg = cfg;
      m_stEntry.Init(cfg.symbol, cfg.entryTf, cfg.swingLeft, cfg.swingRight, cfg.structLookback);
      m_stHtf.Init(cfg.symbol, cfg.htfTf, cfg.swingLeft, cfg.swingRight, cfg.structLookback);
      m_liq.Init(cfg.symbol, cfg.entryTf, cfg.sweepLookback, cfg.sweepWickMinAtr);
      m_fib.Init(cfg.fibLow, cfg.fibHigh);
      m_conf.Init(cfg.symbol, cfg.entryTf);
      m_atrHandle = iATR(cfg.symbol, cfg.entryTf, 14);
      return (m_atrHandle != INVALID_HANDLE);
   }

   void Update()
   {
      m_stEntry.Update();
      m_stHtf.Update();
   }

   double Atr() const
   {
      double buf[];
      if(CopyBuffer(m_atrHandle, 0, 1, 1, buf) != 1) // closed bar ATR
         return 0.0;
      return buf[0];
   }

   ENUM_AW_DIR HtfBias() const { return m_stHtf.Bias(); }
   ENUM_AW_DIR EntryBias() const { return m_stEntry.Bias(); }
   CAWProLiquidity* Liq() { return GetPointer(m_liq); }
   CAWProConfirmations* Conf() { return GetPointer(m_conf); }

   // Evaluate Pro setups on last CLOSED bar. No future data.
   int CollectSignals(AWProSignal &out[], const int maxOut)
   {
      ArrayResize(out, 0);
      const datetime barTime = iTime(m_cfg.symbol, m_cfg.entryTf, 1);
      if(barTime == 0 || barTime == m_lastSignalBarTime)
         return 0; // same closed bar already processed → no duplicates

      const double atr = Atr();
      if(atr <= 0.0) return 0;

      TryPush(out, maxOut, BuildBuy(atr));
      TryPush(out, maxOut, BuildSell(atr));

      if(ArraySize(out) > 0)
         m_lastSignalBarTime = barTime;
      return ArraySize(out);
   }

   void MarkBarProcessed()
   {
      m_lastSignalBarTime = iTime(m_cfg.symbol, m_cfg.entryTf, 1);
   }

private:
   void TryPush(AWProSignal &out[], const int maxOut, const AWProSignal &sig)
   {
      if(!sig.valid) return;
      const int n = ArraySize(out);
      if(n >= maxOut) return;
      ArrayResize(out, n + 1);
      out[n] = sig;
   }

   AWProSignal BuildBuy(const double atr)
   {
      AWProSignal sig;
      ZeroMemory(sig);
      sig.direction = AW_DIR_BUY;
      sig.signalBar = 1;
      sig.signalTime = iTime(m_cfg.symbol, m_cfg.entryTf, 1);
      sig.entry = iClose(m_cfg.symbol, m_cfg.entryTf, 1);

      double fibLvl = 0.0;
      const bool fib = m_fib.InBuyZone(m_stEntry, fibLvl);
      const bool sweep = m_liq.SweepBuy(atr);
      const bool bos = m_stEntry.IsBos(AW_DIR_BUY);
      const bool choch = m_stEntry.IsChoch(AW_DIR_BUY);
      const bool eng = m_conf.BullEngulfing();

      sig.hasFib = fib;
      sig.hasSweep = sweep;
      sig.hasBos = bos;
      sig.hasChoch = choch;
      sig.hasEngulfing = eng;
      sig.fibLevel = fibLvl;
      sig.confirmStrength = m_conf.StrengthBuy();

      ENUM_AW_SETUP_ID id = AW_SETUP_NONE;
      if(fib && sweep && eng && m_cfg.enableFibSweepEngulfing) id = AW_SETUP_FIB_SWEEP_ENGULFING;
      else if(fib && sweep && bos && m_cfg.enableFibSweepBos)   id = AW_SETUP_FIB_SWEEP_BOS;
      else if(fib && choch && m_cfg.enableFibChoch)             id = AW_SETUP_FIB_CHOCH;
      else if(sweep && bos && m_cfg.enableSweepBos)             id = AW_SETUP_SWEEP_BOS;
      else if(sweep && eng && m_cfg.enableSweepEngulfing)       id = AW_SETUP_SWEEP_ENGULFING;
      else if(fib && eng && m_cfg.enableFibEngulfing)           id = AW_SETUP_FIB_ENGULFING;

      if(id == AW_SETUP_NONE) return sig;

      sig.valid = true;
      sig.setupId = id;
      sig.setupName = AW_Pro_SetupName(id);
      sig.sl = sig.entry - atr * m_cfg.slAtrMult;
      sig.tp1 = sig.entry + atr * m_cfg.tp1AtrMult;
      sig.tp2 = sig.entry + atr * m_cfg.tp2AtrMult;
      sig.note = "Pro BUY closed-bar";
      return sig;
   }

   AWProSignal BuildSell(const double atr)
   {
      AWProSignal sig;
      ZeroMemory(sig);
      sig.direction = AW_DIR_SELL;
      sig.signalBar = 1;
      sig.signalTime = iTime(m_cfg.symbol, m_cfg.entryTf, 1);
      sig.entry = iClose(m_cfg.symbol, m_cfg.entryTf, 1);

      double fibLvl = 0.0;
      const bool fib = m_fib.InSellZone(m_stEntry, fibLvl);
      const bool sweep = m_liq.SweepSell(atr);
      const bool bos = m_stEntry.IsBos(AW_DIR_SELL);
      const bool choch = m_stEntry.IsChoch(AW_DIR_SELL);
      const bool eng = m_conf.BearEngulfing();

      sig.hasFib = fib;
      sig.hasSweep = sweep;
      sig.hasBos = bos;
      sig.hasChoch = choch;
      sig.hasEngulfing = eng;
      sig.fibLevel = fibLvl;
      sig.confirmStrength = m_conf.StrengthSell();

      ENUM_AW_SETUP_ID id = AW_SETUP_NONE;
      if(fib && sweep && eng && m_cfg.enableFibSweepEngulfing) id = AW_SETUP_FIB_SWEEP_ENGULFING;
      else if(fib && sweep && bos && m_cfg.enableFibSweepBos)   id = AW_SETUP_FIB_SWEEP_BOS;
      else if(fib && choch && m_cfg.enableFibChoch)             id = AW_SETUP_FIB_CHOCH;
      else if(sweep && bos && m_cfg.enableSweepBos)             id = AW_SETUP_SWEEP_BOS;
      else if(sweep && eng && m_cfg.enableSweepEngulfing)       id = AW_SETUP_SWEEP_ENGULFING;
      else if(fib && eng && m_cfg.enableFibEngulfing)           id = AW_SETUP_FIB_ENGULFING;

      if(id == AW_SETUP_NONE) return sig;

      sig.valid = true;
      sig.setupId = id;
      sig.setupName = AW_Pro_SetupName(id);
      sig.sl = sig.entry + atr * m_cfg.slAtrMult;
      sig.tp1 = sig.entry - atr * m_cfg.tp1AtrMult;
      sig.tp2 = sig.entry - atr * m_cfg.tp2AtrMult;
      sig.note = "Pro SELL closed-bar";
      return sig;
   }
};

#endif
