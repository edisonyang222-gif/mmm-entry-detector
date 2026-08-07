#!/usr/bin/env python3
"""
Gold MMM Entry Detector — Python backtest

Same Multi-filter Momentum Method used in the Pine scripts:
  1) EMA trend bias (21/55 + 200)
  2) Pullback to fast EMA
  3) RSI sweet-spot
  4) ATR regime filter
  5) Session filter (optional; skipped on daily bars)

Usage:
  pip install -r requirements.txt
  python backtest/gold_mmm_backtest.py
  python backtest/gold_mmm_backtest.py --csv path/to/xauusd_h1.csv
  python backtest/gold_mmm_backtest.py --symbol GC=F --interval 1h --period 2y

CSV columns expected: datetime, open, high, low, close [, volume]
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd


# ── indicators ──────────────────────────────────────────────

def ema(series: pd.Series, length: int) -> pd.Series:
    return series.ewm(span=length, adjust=False).mean()


def rsi(series: pd.Series, length: int = 14) -> pd.Series:
    delta = series.diff()
    gain = delta.clip(lower=0)
    loss = -delta.clip(upper=0)
    avg_gain = gain.ewm(alpha=1 / length, min_periods=length, adjust=False).mean()
    avg_loss = loss.ewm(alpha=1 / length, min_periods=length, adjust=False).mean()
    rs = avg_gain / avg_loss.replace(0, np.nan)
    return 100 - (100 / (1 + rs))


def atr(df: pd.DataFrame, length: int = 14) -> pd.Series:
    prev_close = df["close"].shift(1)
    tr = pd.concat(
        [
            df["high"] - df["low"],
            (df["high"] - prev_close).abs(),
            (df["low"] - prev_close).abs(),
        ],
        axis=1,
    ).max(axis=1)
    return tr.ewm(alpha=1 / length, min_periods=length, adjust=False).mean()


# ── config ──────────────────────────────────────────────────

@dataclass
class Params:
    # Defaults tuned for XAU / GC on H4 (also works on D1)
    ema_fast: int = 20
    ema_slow: int = 50
    ema_bias: int = 100
    rsi_len: int = 14
    rsi_buy_low: float = 35
    rsi_buy_high: float = 55
    rsi_sell_low: float = 45
    rsi_sell_high: float = 65
    atr_len: int = 14
    atr_ma_len: int = 50
    min_atr_mult: float = 0.6
    max_atr_mult: float = 3.0
    sl_atr: float = 2.0
    tp1_atr: float = 3.0
    tp2_atr: float = 5.0
    cooldown: int = 6
    risk_pct: float = 0.01  # risk 1% equity per trade
    start_equity: float = 10_000.0
    long_only: bool = False
    short_only: bool = False


# ── signal engine ───────────────────────────────────────────

def build_signals(df: pd.DataFrame, p: Params) -> pd.DataFrame:
    out = df.copy()
    out["ema_fast"] = ema(out["close"], p.ema_fast)
    out["ema_slow"] = ema(out["close"], p.ema_slow)
    out["ema_bias"] = ema(out["close"], p.ema_bias)
    out["rsi"] = rsi(out["close"], p.rsi_len)
    out["atr"] = atr(out, p.atr_len)
    out["atr_ma"] = out["atr"].rolling(p.atr_ma_len).mean()

    bull = (out["ema_fast"] > out["ema_slow"]) & (out["close"] > out["ema_bias"])
    bear = (out["ema_fast"] < out["ema_slow"]) & (out["close"] < out["ema_bias"])
    vol_ok = (
        (out["atr_ma"] > 0)
        & (out["atr"] / out["atr_ma"] >= p.min_atr_mult)
        & (out["atr"] / out["atr_ma"] <= p.max_atr_mult)
    )

    pull_long = (out["low"] <= out["ema_fast"] * 1.001) & (out["close"] > out["ema_fast"])
    pull_short = (out["high"] >= out["ema_fast"] * 0.999) & (out["close"] < out["ema_fast"])
    rsi_long = (out["rsi"] >= p.rsi_buy_low) & (out["rsi"] <= p.rsi_buy_high)
    rsi_short = (out["rsi"] <= p.rsi_sell_high) & (out["rsi"] >= p.rsi_sell_low)
    bull_c = (out["close"] > out["open"]) & (out["close"] > out["close"].shift(1))
    bear_c = (out["close"] < out["open"]) & (out["close"] < out["close"].shift(1))

    raw_long = bull & pull_long & rsi_long & vol_ok & bull_c
    raw_short = bear & pull_short & rsi_short & vol_ok & bear_c

    long_fire = np.zeros(len(out), dtype=bool)
    short_fire = np.zeros(len(out), dtype=bool)
    last_long = -10_000
    last_short = -10_000
    for i in range(len(out)):
        if (not p.short_only) and raw_long.iloc[i] and i - last_long >= p.cooldown:
            long_fire[i] = True
            last_long = i
        if (not p.long_only) and raw_short.iloc[i] and i - last_short >= p.cooldown:
            short_fire[i] = True
            last_short = i

    out["long"] = long_fire
    out["short"] = short_fire
    out["bull_trend"] = bull
    out["bear_trend"] = bear
    return out


# ── backtest ────────────────────────────────────────────────

@dataclass
class Trade:
    side: str
    entry_time: pd.Timestamp
    entry: float
    sl: float
    tp1: float
    tp2: float
    exit_time: pd.Timestamp | None = None
    exit: float | None = None
    pnl: float = 0.0
    reason: str = ""


def run_backtest(df: pd.DataFrame, p: Params) -> tuple[list[Trade], dict]:
    sig = build_signals(df, p)
    trades: list[Trade] = []
    open_trade: Trade | None = None
    equity = p.start_equity
    curve = [equity]
    half_taken = False

    for i in range(1, len(sig)):
        row = sig.iloc[i]
        prev = sig.iloc[i - 1]
        ts = sig.index[i]

        # manage open trade on this bar's OHLC
        if open_trade is not None:
            side = open_trade.side
            hit_sl = hit_tp1 = hit_tp2 = False
            if side == "long":
                hit_sl = row["low"] <= open_trade.sl
                hit_tp1 = (not half_taken) and row["high"] >= open_trade.tp1
                hit_tp2 = row["high"] >= open_trade.tp2
            else:
                hit_sl = row["high"] >= open_trade.sl
                hit_tp1 = (not half_taken) and row["low"] <= open_trade.tp1
                hit_tp2 = row["low"] <= open_trade.tp2

            # conservative: SL before TP if both touch same bar
            if hit_sl:
                exit_px = open_trade.sl
                risk = abs(open_trade.entry - open_trade.sl)
                units = (equity * p.risk_pct) / risk if risk > 0 else 0
                remaining = 0.5 if half_taken else 1.0
                pnl = units * remaining * (
                    (exit_px - open_trade.entry) if side == "long" else (open_trade.entry - exit_px)
                )
                equity += pnl
                open_trade.exit_time = ts
                open_trade.exit = exit_px
                open_trade.pnl += pnl
                open_trade.reason = "SL"
                trades.append(open_trade)
                open_trade = None
                half_taken = False
            else:
                if hit_tp1:
                    risk = abs(open_trade.entry - open_trade.sl)
                    units = (equity * p.risk_pct) / risk if risk > 0 else 0
                    pnl = units * 0.5 * (
                        (open_trade.tp1 - open_trade.entry)
                        if side == "long"
                        else (open_trade.entry - open_trade.tp1)
                    )
                    equity += pnl
                    open_trade.pnl += pnl
                    half_taken = True
                    # move SL to breakeven after TP1
                    open_trade.sl = open_trade.entry
                if hit_tp2:
                    orig_risk = abs(open_trade.tp1 - open_trade.entry) / p.tp1_atr * p.sl_atr
                    units = (equity * p.risk_pct) / orig_risk if orig_risk > 0 else 0
                    remaining = 0.5 if half_taken or hit_tp1 else 1.0
                    pnl = units * remaining * (
                        (open_trade.tp2 - open_trade.entry)
                        if side == "long"
                        else (open_trade.entry - open_trade.tp2)
                    )
                    equity += pnl
                    open_trade.exit_time = ts
                    open_trade.exit = open_trade.tp2
                    open_trade.pnl += pnl
                    open_trade.reason = "TP2"
                    trades.append(open_trade)
                    open_trade = None
                    half_taken = False
                elif (side == "long" and row["bear_trend"]) or (
                    side == "short" and row["bull_trend"]
                ):
                    exit_px = row["close"]
                    orig_risk = abs(open_trade.tp1 - open_trade.entry) / p.tp1_atr * p.sl_atr
                    units = (equity * p.risk_pct) / orig_risk if orig_risk > 0 else 0
                    remaining = 0.5 if half_taken else 1.0
                    pnl = units * remaining * (
                        (exit_px - open_trade.entry)
                        if side == "long"
                        else (open_trade.entry - exit_px)
                    )
                    equity += pnl
                    open_trade.exit_time = ts
                    open_trade.exit = exit_px
                    open_trade.pnl += pnl
                    open_trade.reason = "trend_flip"
                    trades.append(open_trade)
                    open_trade = None
                    half_taken = False

        # new entries use previous bar signal → next open (no look-ahead)
        if open_trade is None:
            if prev["long"]:
                entry = row["open"]
                a = prev["atr"]
                open_trade = Trade(
                    side="long",
                    entry_time=ts,
                    entry=entry,
                    sl=entry - a * p.sl_atr,
                    tp1=entry + a * p.tp1_atr,
                    tp2=entry + a * p.tp2_atr,
                )
                half_taken = False
            elif prev["short"]:
                entry = row["open"]
                a = prev["atr"]
                open_trade = Trade(
                    side="short",
                    entry_time=ts,
                    entry=entry,
                    sl=entry + a * p.sl_atr,
                    tp1=entry - a * p.tp1_atr,
                    tp2=entry - a * p.tp2_atr,
                )
                half_taken = False

        curve.append(equity)

    # force close
    if open_trade is not None:
        last = sig.iloc[-1]
        exit_px = last["close"]
        orig_risk = abs(open_trade.tp1 - open_trade.entry) / p.tp1_atr * p.sl_atr
        units = (equity * p.risk_pct) / orig_risk if orig_risk > 0 else 0
        remaining = 0.5 if half_taken else 1.0
        pnl = units * remaining * (
            (exit_px - open_trade.entry)
            if open_trade.side == "long"
            else (open_trade.entry - exit_px)
        )
        equity += pnl
        open_trade.exit_time = sig.index[-1]
        open_trade.exit = exit_px
        open_trade.pnl += pnl
        open_trade.reason = "eod"
        trades.append(open_trade)
        curve[-1] = equity

    wins = [t for t in trades if t.pnl > 0]
    losses = [t for t in trades if t.pnl <= 0]
    gross_win = sum(t.pnl for t in wins) or 0.0
    gross_loss = abs(sum(t.pnl for t in losses)) or 1e-9
    peak = curve[0]
    max_dd = 0.0
    for e in curve:
        peak = max(peak, e)
        max_dd = max(max_dd, (peak - e) / peak if peak else 0)

    stats = {
        "trades": len(trades),
        "wins": len(wins),
        "losses": len(losses),
        "win_rate": (len(wins) / len(trades) * 100) if trades else 0.0,
        "profit_factor": gross_win / gross_loss,
        "net_pnl": equity - p.start_equity,
        "final_equity": equity,
        "return_pct": (equity / p.start_equity - 1) * 100,
        "max_drawdown_pct": max_dd * 100,
        "avg_pnl": (sum(t.pnl for t in trades) / len(trades)) if trades else 0.0,
    }
    return trades, stats


# ── data loaders ────────────────────────────────────────────

def load_csv(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    cols = {c.lower().strip(): c for c in df.columns}
    rename = {}
    for need in ("open", "high", "low", "close"):
        if need not in cols:
            raise SystemExit(f"CSV missing column: {need}")
        rename[cols[need]] = need
    dt_col = None
    for cand in ("datetime", "date", "time", "timestamp"):
        if cand in cols:
            dt_col = cols[cand]
            break
    if dt_col is None:
        raise SystemExit("CSV needs a datetime/date column")
    df = df.rename(columns=rename)
    df["datetime"] = pd.to_datetime(df[dt_col], utc=True, errors="coerce")
    df = df.dropna(subset=["datetime", "open", "high", "low", "close"])
    df = df.set_index("datetime").sort_index()
    return df[["open", "high", "low", "close"]].astype(float)


def load_yahoo(symbol: str, interval: str, period: str) -> pd.DataFrame:
    try:
        import yfinance as yf
    except ImportError as e:
        raise SystemExit("Install deps: pip install -r requirements.txt") from e

    raw = yf.download(symbol, interval=interval, period=period, auto_adjust=True, progress=False)
    if raw.empty:
        raise SystemExit(f"No data for {symbol}")
    if isinstance(raw.columns, pd.MultiIndex):
        raw.columns = [c[0].lower() for c in raw.columns]
    else:
        raw.columns = [c.lower() for c in raw.columns]
    raw = raw.rename(columns={"adj close": "close"})
    return raw[["open", "high", "low", "close"]].dropna().astype(float)


def synthetic_gold(bars: int = 5000, seed: int = 42) -> pd.DataFrame:
    """GBM-like series with mild trend regimes — for smoke tests only."""
    rng = np.random.default_rng(seed)
    dt = pd.date_range("2020-01-01", periods=bars, freq="h", tz="UTC")
    price = 1800.0
    closes = []
    for i in range(bars):
        # regime drift flips every ~400 bars
        drift = 0.00015 if (i // 400) % 2 == 0 else -0.0001
        shock = rng.normal(drift, 0.0018)
        price = max(100.0, price * (1 + shock))
        closes.append(price)
    close = np.array(closes)
    open_ = np.r_[close[0], close[:-1]]
    high = np.maximum(open_, close) * (1 + rng.uniform(0.0002, 0.0015, bars))
    low = np.minimum(open_, close) * (1 - rng.uniform(0.0002, 0.0015, bars))
    return pd.DataFrame({"open": open_, "high": high, "low": low, "close": close}, index=dt)


def print_report(trades: list[Trade], stats: dict) -> None:
    print("\n═══ Gold MMM Backtest Report ═══")
    for k, v in stats.items():
        if isinstance(v, float):
            print(f"  {k:20s} {v:>12.2f}")
        else:
            print(f"  {k:20s} {v:>12}")
    print("\nLast 10 trades:")
    for t in trades[-10:]:
        exit_px = f"{t.exit:.2f}" if t.exit is not None else "-"
        print(
            f"  {t.side:5s} {t.entry_time} @ {t.entry:.2f} → "
            f"{exit_px} | PnL {t.pnl:+.2f} | {t.reason}"
        )


def main() -> int:
    ap = argparse.ArgumentParser(description="Gold MMM backtest")
    ap.add_argument("--csv", type=Path, help="OHLCV CSV path")
    ap.add_argument("--symbol", default="GC=F", help="Yahoo symbol (default GC=F gold futures)")
    ap.add_argument("--interval", default="1h", help="Yahoo interval")
    ap.add_argument("--period", default="2y", help="Yahoo period")
    ap.add_argument("--synthetic", action="store_true", help="Use synthetic data (offline smoke test)")
    ap.add_argument("--long-only", action="store_true", help="Disable short entries")
    ap.add_argument("--short-only", action="store_true", help="Disable long entries")
    ap.add_argument("--resample", default="", help="Optional pandas resample rule, e.g. 4h")
    args = ap.parse_args()

    params = Params(long_only=args.long_only, short_only=args.short_only)

    if args.csv:
        df = load_csv(args.csv)
        source = str(args.csv)
    elif args.synthetic:
        df = synthetic_gold()
        source = "synthetic"
    else:
        try:
            df = load_yahoo(args.symbol, args.interval, args.period)
            source = f"{args.symbol} {args.interval} {args.period}"
        except SystemExit:
            print("Yahoo download failed; falling back to synthetic data.", file=sys.stderr)
            df = synthetic_gold()
            source = "synthetic (fallback)"

    if args.resample:
        df = (
            df.resample(args.resample)
            .agg({"open": "first", "high": "max", "low": "min", "close": "last"})
            .dropna()
        )
        source = f"{source} → {args.resample}"

    print(f"Data: {source} | bars={len(df)} | {df.index[0]} → {df.index[-1]}")
    trades, stats = run_backtest(df, params)
    print_report(trades, stats)

    out_dir = Path(__file__).resolve().parent / "output"
    out_dir.mkdir(exist_ok=True)
    if trades:
        pd.DataFrame(
            [
                {
                    "side": t.side,
                    "entry_time": t.entry_time,
                    "entry": t.entry,
                    "exit_time": t.exit_time,
                    "exit": t.exit,
                    "sl": t.sl,
                    "tp1": t.tp1,
                    "tp2": t.tp2,
                    "pnl": t.pnl,
                    "reason": t.reason,
                }
                for t in trades
            ]
        ).to_csv(out_dir / "trades.csv", index=False)
        print(f"\nTrades saved → {out_dir / 'trades.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
