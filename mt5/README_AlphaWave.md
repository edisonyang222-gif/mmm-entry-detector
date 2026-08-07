# Alpha Wave — MT5 / MQL5 XAUUSD Quant Scaffold

Modular Expert Advisor framework for XAUUSD on MetaTrader 5.

## Versions

| Version | Name | Role |
|--------|------|------|
| 1 | **Alpha Wave Lite** | Market analysis, drawing hooks, hints, signal scoring — **no auto trading** |
| 2 | Alpha Wave Pro | Lite analysis + auto trade, SL/TP, risk, kill switch |
| 3 | Alpha Wave Institutional | Pro + regime filters, quality score, stats, reject low-quality trades |

This repository step implements **Lite scaffold only**: architecture, inputs, UTC+8 time, daily 04:45 reset, debug logger. **No entry strategy. No orders.**

## Layout

```
mt5/
  Experts/AlphaWave_Lite.mq5
  Include/AlphaWave/
    AW_All.mqh
    AW_Common.mqh
    AW_Logger.mqh
    AW_TimeManager.mqh
    AW_MarketStructure.mqh
    AW_SessionManager.mqh
    AW_LiquidityManager.mqh
    AW_FibManager.mqh
    AW_SetupDetector.mqh
    AW_ConfirmationManager.mqh
    AW_TradeScore.mqh
    AW_RiskManager.mqh
    AW_TradeManager.mqh
    AW_Statistics.mqh
```

Copy into your MT5 data folder:

- `mt5/Experts/*` → `MQL5/Experts/`
- `mt5/Include/AlphaWave/*` → `MQL5/Include/AlphaWave/`

Then compile `AlphaWave_Lite.mq5` in MetaEditor.

## Shared rules (enforced in design)

- Prefer XAUUSD; TFs: H4/H1 bias, M15 setup, M5 confirm
- Trade timezone **UTC+8**; daily structure reset at **04:45 UTC+8**
- Modular classes — logic not dumped into `OnTick()`
- Every condition / module toggleable via `input`
- No martingale / grid / averaging down / stealth SL removal
- Prefer max drawdown control over max profit
- Log entry reasons and reject reasons (APIs ready)
- Same bar must not re-fire the same setup id (`SetupDetector.ConsumeIfNewBar`)
- Unclear rules → independent stub + `TODO` (do not invent strategy)

## Module map

| Module | Purpose |
|--------|---------|
| **TimeManager** | Broker ↔ UTC ↔ UTC+8; session-day key; detect/consume daily 04:45 reset |
| **MarketStructure** | H4/H1 bias + M15 structure (stub) |
| **SessionManager** | Asia / London / NY windows in UTC+8 minutes (stub policy) |
| **LiquidityManager** | Liquidity pools / sweeps (stub) |
| **FibManager** | Fib / OTE levels (stub) |
| **SetupDetector** | M15 setups + same-bar dedupe helper (stub) |
| **ConfirmationManager** | M5 confirmation (stub) |
| **TradeScore** | Signal quality score + thresholds (stub) |
| **RiskManager** | Risk %, daily loss, DD kill-switch; forbids martingale/grid/avg-down |
| **TradeManager** | Order API; **hard-disabled in Lite** |
| **Statistics** | Counters / future Institutional stats |
| **Logger** | Terminal/file debug log; entry & reject reason APIs |

## Lite behaviour

1. `OnInit` wires all modules from inputs.
2. First load + each UTC+8 04:45 crossing → `DailyReset` on every module.
3. `OnTick` only: check reset → `UpdateModules()` → optional heartbeat log.
4. Auto trade forced off regardless of `InpEnableTradeManager`.

## Next steps (not in this PR)

- Confirm and implement structure / liquidity / fib / setup / confirm rules
- Chart drawing & hint UI for Lite
- Pro: TradeManager + mandatory SL/TP + risk sizing
- Institutional: regime filters + quality reject + deeper statistics
