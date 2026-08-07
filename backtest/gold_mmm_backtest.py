#!/usr/bin/env python3
"""
黃金 MMM 進場偵測 — Python 回測（小週期共振版）

濾網：
  1) EMA 趨勢 + 回檔
  2) RSI 甜蜜區
  3) ATR 波動區間
  4) 高週期共振（HTF1 / HTF2）
  5) ADX 趨勢強度
  6) MACD 柱狀動能
  7) EMA 斜率
  8) 共振分數門檻

用法：
  python3 backtest/gold_mmm_backtest.py --symbol GC=F --interval 1h --period 2y --htf1 4h --htf2 1D
  python3 backtest/gold_mmm_backtest.py --synthetic
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


def macd_hist(series: pd.Series, fast: int = 12, slow: int = 26, signal: int = 9) -> pd.Series:
    line = ema(series, fast) - ema(series, slow)
    sig = ema(line, signal)
    return line - sig


def adx(df: pd.DataFrame, length: int = 14) -> pd.Series:
    up = df["high"].diff()
    down = -df["low"].diff()
    plus_dm = np.where((up > down) & (up > 0), up, 0.0)
    minus_dm = np.where((down > up) & (down > 0), down, 0.0)
    atr_rma = (
        pd.concat(
            [
                df["high"] - df["low"],
                (df["high"] - df["close"].shift(1)).abs(),
                (df["low"] - df["close"].shift(1)).abs(),
            ],
            axis=1,
        )
        .max(axis=1)
        .ewm(alpha=1 / length, min_periods=length, adjust=False)
        .mean()
    )
    plus_di = 100 * pd.Series(plus_dm, index=df.index).ewm(
        alpha=1 / length, min_periods=length, adjust=False
    ).mean() / atr_rma.replace(0, np.nan)
    minus_di = 100 * pd.Series(minus_dm, index=df.index).ewm(
        alpha=1 / length, min_periods=length, adjust=False
    ).mean() / atr_rma.replace(0, np.nan)
    dx = (plus_di - minus_di).abs() / (plus_di + minus_di).replace(0, np.nan) * 100
    return dx.ewm(alpha=1 / length, min_periods=length, adjust=False).mean()


def htf_bias(df: pd.DataFrame, rule: str, ema_len: int) -> pd.Series:
    """Higher-timeframe close vs EMA, forward-filled to base TF without lookahead."""
    htf = df.resample(rule).agg({"close": "last"}).dropna()
    htf_ema = ema(htf["close"], ema_len)
    bias = (htf["close"] > htf_ema).astype(float)
    # shift 1 so current incomplete HTF bar is not used
    bias = bias.shift(1)
    aligned = bias.reindex(df.index, method="ffill")
    return aligned.fillna(0.0)


# ── config ──────────────────────────────────────────────────

@dataclass
class Params:
    # 小週期共振預設（H1）；H4/D1 可關 mtf / 放寬分數
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
    cooldown: int = 8
    risk_pct: float = 0.01
    start_equity: float = 10_000.0
    long_only: bool = False
    short_only: bool = False
    # 共振
    use_mtf: bool = True
    htf1_rule: str = "1h"   # 對 M15 用 1h；對 H1 用 4h
    use_htf2: bool = True
    htf2_rule: str = "4h"
    htf_ema: int = 50
    use_adx: bool = True
    adx_len: int = 14
    adx_min: float = 20.0
    use_macd: bool = True
    use_slope: bool = True
    slope_bars: int = 3
    min_score: int = 5
    # 盤整過濾
    use_range_filter: bool = True
    use_chop: bool = True
    chop_len: int = 14
    chop_max: float = 61.8
    use_ema_squeeze: bool = True
    ema_gap_min_atr: float = 0.35
    use_er: bool = True
    er_len: int = 10
    er_min: float = 0.25
    # 若 base TF 已是 H1，htf1 應設 4h、htf2 設 1D（由 CLI 覆寫）


def choppiness(df: pd.DataFrame, length: int = 14) -> pd.Series:
    tr = pd.concat(
        [
            df["high"] - df["low"],
            (df["high"] - df["close"].shift(1)).abs(),
            (df["low"] - df["close"].shift(1)).abs(),
        ],
        axis=1,
    ).max(axis=1)
    atr_sum = tr.rolling(length).sum()
    hi = df["high"].rolling(length).max()
    lo = df["low"].rolling(length).min()
    rng = (hi - lo).replace(0, np.nan)
    return 100 * np.log10(atr_sum / rng) / np.log10(length)


def efficiency_ratio(close: pd.Series, length: int = 10) -> pd.Series:
    move = (close - close.shift(length)).abs()
    path = close.diff().abs().rolling(length).sum().replace(0, np.nan)
    return move / path


# ── signal engine ───────────────────────────────────────────

def build_signals(df: pd.DataFrame, p: Params) -> pd.DataFrame:
    out = df.copy()
    out["ema_fast"] = ema(out["close"], p.ema_fast)
    out["ema_slow"] = ema(out["close"], p.ema_slow)
    out["ema_bias"] = ema(out["close"], p.ema_bias)
    out["rsi"] = rsi(out["close"], p.rsi_len)
    out["atr"] = atr(out, p.atr_len)
    out["atr_ma"] = out["atr"].rolling(p.atr_ma_len).mean()
    out["macd_hist"] = macd_hist(out["close"])
    out["adx"] = adx(out, p.adx_len)
    out["chop"] = choppiness(out, p.chop_len)
    out["er"] = efficiency_ratio(out["close"], p.er_len)

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
    slope_up = out["ema_fast"] > out["ema_fast"].shift(p.slope_bars)
    slope_dn = out["ema_fast"] < out["ema_fast"].shift(p.slope_bars)
    adx_ok = out["adx"] >= p.adx_min if p.use_adx else pd.Series(True, index=out.index)
    if p.use_macd:
        macd_long = (out["macd_hist"] > 0) & (out["macd_hist"] > out["macd_hist"].shift(1))
        macd_short = (out["macd_hist"] < 0) & (out["macd_hist"] < out["macd_hist"].shift(1))
    else:
        macd_long = macd_short = pd.Series(True, index=out.index)
    chop_ok = out["chop"] <= p.chop_max if p.use_chop else pd.Series(True, index=out.index)
    ema_gap = (out["ema_fast"] - out["ema_slow"]).abs() / out["atr"].replace(0, np.nan)
    ema_squeeze_ok = (
        ema_gap >= p.ema_gap_min_atr if p.use_ema_squeeze else pd.Series(True, index=out.index)
    )
    er_ok = out["er"] >= p.er_min if p.use_er else pd.Series(True, index=out.index)
    if p.use_range_filter:
        trend_market_ok = adx_ok & chop_ok & ema_squeeze_ok & er_ok
    else:
        trend_market_ok = pd.Series(True, index=out.index)

    if p.use_mtf:
        h1 = htf_bias(out, p.htf1_rule, p.htf_ema)
        htf1_bull = h1 > 0.5
        htf1_bear = h1 < 0.5
        if p.use_htf2:
            h2 = htf_bias(out, p.htf2_rule, p.htf_ema)
            htf2_bull = h2 > 0.5
            htf2_bear = h2 < 0.5
        else:
            htf2_bull = pd.Series(True, index=out.index)
            htf2_bear = pd.Series(True, index=out.index)
    else:
        htf1_bull = htf2_bull = pd.Series(True, index=out.index)
        htf1_bear = htf2_bear = pd.Series(True, index=out.index)

    mtf_long = htf1_bull & htf2_bull
    mtf_short = htf1_bear & htf2_bear

    # 打分（與 Pine 對齊，關閉項給滿分）
    score_long = (
        bull.astype(int)
        + pull_long.astype(int)
        + rsi_long.astype(int)
        + vol_ok.astype(int)
        + (htf1_bull if p.use_mtf else pd.Series(True, index=out.index)).astype(int)
        + (
            htf2_bull
            if (p.use_mtf and p.use_htf2)
            else pd.Series(True, index=out.index)
        ).astype(int)
        + (adx_ok if p.use_adx else pd.Series(True, index=out.index)).astype(int)
        + (macd_long if p.use_macd else pd.Series(True, index=out.index)).astype(int)
    )
    score_short = (
        bear.astype(int)
        + pull_short.astype(int)
        + rsi_short.astype(int)
        + vol_ok.astype(int)
        + (htf1_bear if p.use_mtf else pd.Series(True, index=out.index)).astype(int)
        + (
            htf2_bear
            if (p.use_mtf and p.use_htf2)
            else pd.Series(True, index=out.index)
        ).astype(int)
        + (adx_ok if p.use_adx else pd.Series(True, index=out.index)).astype(int)
        + (macd_short if p.use_macd else pd.Series(True, index=out.index)).astype(int)
    )

    slope_long_ok = slope_up if p.use_slope else pd.Series(True, index=out.index)
    slope_short_ok = slope_dn if p.use_slope else pd.Series(True, index=out.index)

    raw_long = (
        bull
        & pull_long
        & bull_c
        & slope_long_ok
        & mtf_long
        & trend_market_ok
        & (score_long >= p.min_score)
    )
    raw_short = (
        bear
        & pull_short
        & bear_c
        & slope_short_ok
        & mtf_short
        & trend_market_ok
        & (score_short >= p.min_score)
    )

    long_fire = np.zeros(len(out), dtype=bool)
    short_fire = np.zeros(len(out), dtype=bool)
    last_long = -10_000
    last_short = -10_000
    for i in range(len(out)):
        if (not p.short_only) and bool(raw_long.iloc[i]) and i - last_long >= p.cooldown:
            long_fire[i] = True
            last_long = i
        if (not p.long_only) and bool(raw_short.iloc[i]) and i - last_short >= p.cooldown:
            short_fire[i] = True
            last_short = i

    out["long"] = long_fire
    out["short"] = short_fire
    out["bull_trend"] = bull
    out["bear_trend"] = bear
    out["score_long"] = score_long
    out["score_short"] = score_short
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
    print("\n═══ 黃金MMM 回測報告 ═══")
    labels = {
        "trades": "交易數",
        "wins": "獲利筆數",
        "losses": "虧損筆數",
        "win_rate": "勝率%",
        "profit_factor": "盈虧比PF",
        "net_pnl": "淨損益",
        "final_equity": "最終權益",
        "return_pct": "報酬%",
        "max_drawdown_pct": "最大回撤%",
        "avg_pnl": "平均損益",
    }
    for k, v in stats.items():
        name = labels.get(k, k)
        if isinstance(v, float):
            print(f"  {name:12s} {v:>12.2f}")
        else:
            print(f"  {name:12s} {v:>12}")
    print("\n最近 10 筆：")
    for t in trades[-10:]:
        exit_px = f"{t.exit:.2f}" if t.exit is not None else "-"
        side = "做多" if t.side == "long" else "做空"
        print(
            f"  {side} {t.entry_time} @ {t.entry:.2f} → "
            f"{exit_px} | 損益 {t.pnl:+.2f} | {t.reason}"
        )


def main() -> int:
    ap = argparse.ArgumentParser(description="黃金 MMM 回測")
    ap.add_argument("--csv", type=Path, help="OHLCV CSV 路徑")
    ap.add_argument("--symbol", default="GC=F", help="Yahoo 代碼（預設 GC=F）")
    ap.add_argument("--interval", default="1h", help="Yahoo 週期")
    ap.add_argument("--period", default="2y", help="Yahoo 區間")
    ap.add_argument("--synthetic", action="store_true", help="合成資料煙霧測試")
    ap.add_argument("--long-only", action="store_true", help="只做多")
    ap.add_argument("--short-only", action="store_true", help="只做空")
    ap.add_argument("--resample", default="", help="重採樣，例如 4h")
    ap.add_argument("--htf1", default="4h", help="第一共振週期（H1 圖建議 4h）")
    ap.add_argument("--htf2", default="1D", help="第二共振週期（H1 圖建議 1D）")
    ap.add_argument("--min-score", type=int, default=5, help="最低共振分數")
    ap.add_argument("--no-mtf", action="store_true", help="關閉高週期共振")
    ap.add_argument("--no-adx", action="store_true", help="關閉 ADX")
    ap.add_argument("--no-macd", action="store_true", help="關閉 MACD")
    args = ap.parse_args()

    params = Params(
        long_only=args.long_only,
        short_only=args.short_only,
        htf1_rule=args.htf1,
        htf2_rule=args.htf2,
        min_score=args.min_score,
        use_mtf=not args.no_mtf,
        use_adx=not args.no_adx,
        use_macd=not args.no_macd,
    )

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
            print("Yahoo 下載失敗，改用合成資料。", file=sys.stderr)
            df = synthetic_gold()
            source = "synthetic (fallback)"

    if args.resample:
        df = (
            df.resample(args.resample)
            .agg({"open": "first", "high": "max", "low": "min", "close": "last"})
            .dropna()
        )
        source = f"{source} → {args.resample}"

    print(f"資料: {source} | K線={len(df)} | {df.index[0]} → {df.index[-1]}")
    print(
        f"共振: MTF={'開' if params.use_mtf else '關'}({params.htf1_rule}/{params.htf2_rule}) "
        f"ADX={'開' if params.use_adx else '關'} MACD={'開' if params.use_macd else '關'} "
        f"分數≥{params.min_score}"
    )
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
        print(f"\n成交明細 → {out_dir / 'trades.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
