# Alpha Wave Institutional — Pre-flight Checklist

## Completed safeguards

- [x] Look-ahead bias: signals / ATR / ADX / swings use closed bars (shift ≥ 1)
- [x] Future data leakage: swing right-side must be closed; session range excludes forming bar
- [x] Duplicate trades: one evaluation per closed bar; max one position per symbol+magic
- [x] Lot calculation: risk % × equity / SL distance via tick value; DD mult only reduces size
- [x] Session timezone: `TimeGMT + InpGmtOffsetHours` (default +8)
- [x] Daily reset: day/week/month keys from same TZ calendar
- [x] No ML parameter mutation
- [x] No martingale / grid / recovery / lot increase after loss
- [x] AutoDisable default **false**; requires min samples + logs reason
- [x] Pro module not overturned — Institutional only filters/scores/gates

## Manual verification in MT5 Strategy Tester

- [ ] Compile with includes under `MQL5/Include/AlphaWave/`
- [ ] Visual mode: confirm entries only after bar close
- [ ] Force DD Level3 in demo → EA Status STOPPED, no new orders
- [ ] LOW VOLATILITY + BlockLowVol → no trades
- [ ] AutoDisable=false → weak setups still allowed
- [ ] Check journal for SetupDB pause reasons when AutoDisable enabled after 100 samples
