"""Intraday OHLC entry signal detector (Python mirror of MQL5 logic)."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, IntEnum
from typing import Optional

import numpy as np
import pandas as pd


class Side(IntEnum):
    BUY = 1
    SELL = -1


class SignalType(str, Enum):
    NONE = "NONE"
    PDH_BREAKOUT = "PDH_BO"
    PDL_BREAKOUT = "PDL_BO"
    OPEN_BREAK_BUY = "OPEN_BUY"
    OPEN_BREAK_SELL = "OPEN_SELL"
    PDH_REJECTION = "PDH_REJ"
    PDL_REJECTION = "PDL_REJ"
    ORB_BREAK_BUY = "ORB_BUY"
    ORB_BREAK_SELL = "ORB_SELL"


class Mode(str, Enum):
    BREAKOUT = "BREAKOUT"
    REJECTION = "REJECTION"
    OPEN = "OPEN"
    ALL = "ALL"


@dataclass
class Config:
    mode: Mode = Mode.ALL
    session_start_hour: int = 0
    orb_bars: int = 4
    atr_period: int = 14
    touch_tol_atr: float = 0.05
    min_break_atr: float = 0.02
    reject_body_ratio: float = 0.45
    stop_atr_mult: float = 0.8
    min_rr: float = 1.5
    tp_rr: float = 2.0
    use_level_tp: bool = True
    one_per_day_per_side: bool = True

    @property
    def enable_breakout(self) -> bool:
        return self.mode in (Mode.BREAKOUT, Mode.ALL)

    @property
    def enable_rejection(self) -> bool:
        return self.mode in (Mode.REJECTION, Mode.ALL)

    @property
    def enable_open_cross(self) -> bool:
        return self.mode in (Mode.OPEN, Mode.ALL)

    @property
    def enable_orb(self) -> bool:
        return self.mode in (Mode.BREAKOUT, Mode.ALL)


@dataclass
class DayLevels:
    day_key: pd.Timestamp
    pdh: float = 0.0
    pdl: float = 0.0
    pdo: float = 0.0
    pdc: float = 0.0
    day_open: float = 0.0
    mid: float = 0.0
    orb_high: float = 0.0
    orb_low: float = 0.0
    orb_ready: bool = False
    valid: bool = False


@dataclass
class Signal:
    valid: bool = False
    side: Optional[Side] = None
    type: SignalType = SignalType.NONE
    entry: float = 0.0
    stop_loss: float = 0.0
    take_profit: float = 0.0
    risk_reward: float = 0.0
    level: float = 0.0
    day_key: Optional[pd.Timestamp] = None
    time: Optional[pd.Timestamp] = None


@dataclass
class DayTracker:
    cur_day_key: Optional[pd.Timestamp] = None
    cur_open: float = 0.0
    cur_high: float = 0.0
    cur_low: float = 0.0
    cur_close: float = 0.0
    bars_in_day: int = 0
    prev_open: float = 0.0
    prev_high: float = 0.0
    prev_low: float = 0.0
    prev_close: float = 0.0
    prev_ready: bool = False
    orb_high: float = 0.0
    orb_low: float = 0.0
    orb_ready: bool = False
    last_buy_day: Optional[pd.Timestamp] = None
    last_sell_day: Optional[pd.Timestamp] = None


def session_day_key(ts: pd.Timestamp, session_start_hour: int) -> pd.Timestamp:
    ts = pd.Timestamp(ts)
    base = ts.normalize() + pd.Timedelta(hours=session_start_hour)
    if ts.hour < session_start_hour:
        base -= pd.Timedelta(days=1)
    return base


def atr_series(high: np.ndarray, low: np.ndarray, close: np.ndarray, period: int) -> np.ndarray:
    n = len(close)
    out = np.full(n, np.nan)
    if n < period + 1:
        return out
    prev_c = close[:-1]
    tr = np.maximum(high[1:] - low[1:], np.maximum(np.abs(high[1:] - prev_c), np.abs(low[1:] - prev_c)))
    # simple moving ATR aligned to bar index 1..n-1
    csum = np.cumsum(tr)
    for i in range(period - 1, len(tr)):
        total = csum[i] - (csum[i - period] if i - period >= 0 else 0.0)
        out[i + 1] = total / period
    return out


def _build_plan(
    side: Side,
    stype: SignalType,
    entry: float,
    level: float,
    atr: float,
    cfg: Config,
    lv: DayLevels,
    day_key: pd.Timestamp,
    time: pd.Timestamp,
) -> Optional[Signal]:
    if atr <= 0 or entry <= 0:
        return None
    stop_dist = cfg.stop_atr_mult * atr
    if side == Side.BUY:
        stop = entry - stop_dist
        tp = 0.0
        if cfg.use_level_tp:
            structural = 0.0
            if stype in (SignalType.PDL_REJECTION, SignalType.OPEN_BREAK_BUY):
                structural = lv.mid if lv.mid > entry else lv.pdh
            elif stype == SignalType.ORB_BREAK_BUY:
                structural = lv.pdh
            elif stype == SignalType.PDH_BREAKOUT:
                structural = entry + (lv.pdh - lv.pdl)
            if structural > entry:
                tp = structural
        if tp <= entry:
            tp = entry + cfg.tp_rr * (entry - stop)
    else:
        stop = entry + stop_dist
        tp = 0.0
        if cfg.use_level_tp:
            structural = 0.0
            if stype in (SignalType.PDH_REJECTION, SignalType.OPEN_BREAK_SELL):
                structural = lv.mid if lv.mid < entry else lv.pdl
            elif stype == SignalType.ORB_BREAK_SELL:
                structural = lv.pdl
            elif stype == SignalType.PDL_BREAKOUT:
                structural = entry - (lv.pdh - lv.pdl)
            if 0 < structural < entry:
                tp = structural
        if tp <= 0 or tp >= entry:
            tp = entry - cfg.tp_rr * (stop - entry)

    risk = abs(entry - stop)
    if risk <= 0:
        return None
    rr = abs(tp - entry) / risk
    if rr < cfg.min_rr:
        tp = entry + cfg.tp_rr * risk if side == Side.BUY else entry - cfg.tp_rr * risk
        rr = abs(tp - entry) / risk
    if rr < cfg.min_rr:
        return None
    return Signal(
        valid=True,
        side=side,
        type=stype,
        entry=float(entry),
        stop_loss=float(stop),
        take_profit=float(tp),
        risk_reward=float(rr),
        level=float(level),
        day_key=day_key,
        time=time,
    )


def update_day(
    tr: DayTracker,
    cfg: Config,
    bar_time: pd.Timestamp,
    o: float,
    h: float,
    l: float,
    c: float,
) -> DayLevels:
    day_key = session_day_key(bar_time, cfg.session_start_hour)
    if tr.cur_day_key is None:
        tr.cur_day_key = day_key
        tr.cur_open = o
        tr.cur_high = h
        tr.cur_low = l
        tr.cur_close = c
        tr.bars_in_day = 1
        tr.orb_high = h
        tr.orb_low = l
        tr.orb_ready = cfg.orb_bars <= 1
    elif day_key != tr.cur_day_key:
        tr.prev_open = tr.cur_open
        tr.prev_high = tr.cur_high
        tr.prev_low = tr.cur_low
        tr.prev_close = tr.cur_close
        tr.prev_ready = tr.prev_high > 0 and tr.prev_low > 0
        tr.cur_day_key = day_key
        tr.cur_open = o
        tr.cur_high = h
        tr.cur_low = l
        tr.cur_close = c
        tr.bars_in_day = 1
        tr.orb_high = h
        tr.orb_low = l
        tr.orb_ready = cfg.orb_bars <= 1
    else:
        tr.cur_high = max(tr.cur_high, h)
        tr.cur_low = min(tr.cur_low, l)
        tr.cur_close = c
        tr.bars_in_day += 1
        if not tr.orb_ready:
            tr.orb_high = max(tr.orb_high, h)
            tr.orb_low = min(tr.orb_low, l)
            if tr.bars_in_day >= cfg.orb_bars:
                tr.orb_ready = True

    lv = DayLevels(day_key=day_key, day_open=tr.cur_open, orb_high=tr.orb_high, orb_low=tr.orb_low, orb_ready=tr.orb_ready)
    if tr.prev_ready:
        lv.pdh = tr.prev_high
        lv.pdl = tr.prev_low
        lv.pdo = tr.prev_open
        lv.pdc = tr.prev_close
        lv.mid = 0.5 * (lv.pdh + lv.pdl)
        lv.valid = True
    return lv


def _allow(tr: DayTracker, cfg: Config, side: Side, day_key: pd.Timestamp) -> bool:
    if not cfg.one_per_day_per_side:
        return True
    if side == Side.BUY:
        return tr.last_buy_day != day_key
    return tr.last_sell_day != day_key


def _mark(tr: DayTracker, side: Side, day_key: pd.Timestamp) -> None:
    if side == Side.BUY:
        tr.last_buy_day = day_key
    else:
        tr.last_sell_day = day_key


def evaluate_bar(
    tr: DayTracker,
    cfg: Config,
    bar_time: pd.Timestamp,
    o: float,
    h: float,
    l: float,
    c: float,
    prev_close: float,
    atr: float,
) -> Optional[Signal]:
    lv = update_day(tr, cfg, bar_time, o, h, l, c)
    if not lv.valid or atr <= 0 or np.isnan(atr):
        return None

    early = tr.bars_in_day <= 1
    tol = cfg.touch_tol_atr * atr
    brk = cfg.min_break_atr * atr
    rng = h - l
    body = abs(c - o)

    def try_plan(side: Side, stype: SignalType, entry: float, level: float) -> Optional[Signal]:
        if not _allow(tr, cfg, side, lv.day_key):
            return None
        sig = _build_plan(side, stype, entry, level, atr, cfg, lv, lv.day_key, bar_time)
        if sig:
            _mark(tr, side, lv.day_key)
        return sig

    if cfg.enable_breakout and not early:
        if prev_close <= lv.pdh + tol and c > lv.pdh + brk:
            sig = try_plan(Side.BUY, SignalType.PDH_BREAKOUT, c, lv.pdh)
            if sig:
                return sig
        if prev_close >= lv.pdl - tol and c < lv.pdl - brk:
            sig = try_plan(Side.SELL, SignalType.PDL_BREAKOUT, c, lv.pdl)
            if sig:
                return sig

    if cfg.enable_open_cross and not early:
        if prev_close <= lv.day_open + tol and c > lv.day_open + brk:
            sig = try_plan(Side.BUY, SignalType.OPEN_BREAK_BUY, c, lv.day_open)
            if sig:
                return sig
        if prev_close >= lv.day_open - tol and c < lv.day_open - brk:
            sig = try_plan(Side.SELL, SignalType.OPEN_BREAK_SELL, c, lv.day_open)
            if sig:
                return sig

    if cfg.enable_rejection and not early and rng > 0 and (body / rng) >= cfg.reject_body_ratio:
        if h >= lv.pdh - tol and c < lv.pdh - brk and c < o:
            sig = try_plan(Side.SELL, SignalType.PDH_REJECTION, c, lv.pdh)
            if sig:
                return sig
        if l <= lv.pdl + tol and c > lv.pdl + brk and c > o:
            sig = try_plan(Side.BUY, SignalType.PDL_REJECTION, c, lv.pdl)
            if sig:
                return sig

    if cfg.enable_orb and lv.orb_ready and tr.bars_in_day > cfg.orb_bars:
        if prev_close <= lv.orb_high + tol and c > lv.orb_high + brk:
            sig = try_plan(Side.BUY, SignalType.ORB_BREAK_BUY, c, lv.orb_high)
            if sig:
                return sig
        if prev_close >= lv.orb_low - tol and c < lv.orb_low - brk:
            sig = try_plan(Side.SELL, SignalType.ORB_BREAK_SELL, c, lv.orb_low)
            if sig:
                return sig
    return None


def detect(df: pd.DataFrame, cfg: Optional[Config] = None) -> pd.DataFrame:
    """Run detector on OHLCV DataFrame with columns open/high/low/close and DatetimeIndex."""
    cfg = cfg or Config()
    data = df.copy()
    if not isinstance(data.index, pd.DatetimeIndex):
        raise ValueError("DataFrame index must be DatetimeIndex")
    for col in ("open", "high", "low", "close"):
        if col not in data.columns:
            raise ValueError(f"missing column: {col}")

    atr = atr_series(
        data["high"].to_numpy(dtype=float),
        data["low"].to_numpy(dtype=float),
        data["close"].to_numpy(dtype=float),
        cfg.atr_period,
    )
    tr = DayTracker()
    rows = []
    closes = data["close"].to_numpy(dtype=float)
    for i, (ts, row) in enumerate(data.iterrows()):
        if i == 0:
            continue
        sig = evaluate_bar(
            tr,
            cfg,
            pd.Timestamp(ts),
            float(row["open"]),
            float(row["high"]),
            float(row["low"]),
            float(row["close"]),
            float(closes[i - 1]),
            float(atr[i]) if not np.isnan(atr[i]) else 0.0,
        )
        if sig and sig.valid:
            rows.append(
                {
                    "time": sig.time,
                    "side": int(sig.side),
                    "type": sig.type.value,
                    "entry": sig.entry,
                    "stop_loss": sig.stop_loss,
                    "take_profit": sig.take_profit,
                    "risk_reward": sig.risk_reward,
                    "level": sig.level,
                }
            )
    return pd.DataFrame(rows)
