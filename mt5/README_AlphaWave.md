# Alpha Wave Lite — MT5 Analysis EA

Analysis-only Expert Advisor for XAUUSD. **Does not place orders.**

## Features

1. **Session system (UTC+8)** — Asia / London / NY windows (all `input`), PDH/PDL, PDO/CDO, session H/L/Open
2. **Market structure** — H4/H1/M15 swing HH/HL/LH/LL, BOS, CHoCH → Bullish / Bearish / Neutral
3. **Intraday bias** — rule-based score from structure, PD location, Asia range, sweeps
4. **Liquidity sweep** — pierce + reclaim for PDH/PDL/Asia/London (thresholds as `input`)
5. **Fib setup** — reset 04:45 UTC+8; two-leg trend → Fib 0/0.25/0.5/0.618/0.75/1; two-leg pullback into 0.5 zone
6. **M5 confirmation** — Engulfing / Pin / Rejection / BOS / CHoCH (only in Fib zone)
7. **Trade quality score** — 0–100 with configurable weights + band labels
8. **Chart panel** — top-right HUD
9. **Alert** — only when score ≥ `InpAlert_MinScore`

## Install

```
mt5/Experts/AlphaWave_Lite.mq5  →  MQL5/Experts/
mt5/Include/AlphaWave/*         →  MQL5/Include/AlphaWave/
```

Compile in MetaEditor. Attach to XAUUSD chart (any TF; analysis uses H4/H1/M15/M5 internally).

## Important inputs

| Group | Key inputs |
|-------|------------|
| Time | Broker UTC offset, trade TZ (+8), day start 04:45 |
| Session | Asia/London/NY start-end minutes (UTC+8) |
| Structure | Swing left/right bars |
| Liquidity | Pierce / reclaim points |
| Fib | 0.5 tolerance, min impulse |
| M5 | Pin wick/body ratio (default 2.0) |
| Score | Per-factor weights |
| Alert | Min score, popup/push/sound |

## Safety

- Edition locked to Lite
- `CAWTradeManager` auto-trade forced `false`
- No order placement APIs in EA analysis path
- Same-bar signal dedupe helpers in Fib / Confirmation / Alert
