"""Multi-TF structure: liquidity sweep + valid S/R + pullback entry (Python mirror)."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, IntEnum
from typing import Optional

import numpy as np
import pandas as pd


class Bias(IntEnum):
    NEUTRAL = 0
    BULL = 1
    BEAR = -1


class Side(IntEnum):
    BUY = 1
    SELL = -1


class EntryKind(str, Enum):
    NONE = "無"
    PULLBACK_SUPPORT = "回踩有效支撐"
    PULLBACK_RESIST = "回踩有效阻力"


@dataclass
class Config:
    swing_left: int = 2
    swing_right: int = 2
    atr_period: int = 14
    sweep_lookback: int = 30
    structure_lookback: int = 80
    sweep_wick_atr: float = 0.05
    zone_atr: float = 0.35
    confirm_body_ratio: float = 0.45
    stop_buf_atr: float = 0.15
    min_rr: float = 1.5
    tp_rr: float = 2.0
    require_htf_align: bool = True
    require_sweep: bool = True
    one_per_setup: bool = True


@dataclass
class SweepMemory:
    has_low: bool = False
    has_high: bool = False
    low_level: float = 0.0
    high_level: float = 0.0
    low_bar: int = -1
    high_bar: int = -1
    low_consumed: bool = False
    high_consumed: bool = False
    low_left_zone: bool = False
    high_left_zone: bool = False


@dataclass
class Signal:
    valid: bool = False
    side: Optional[Side] = None
    kind: EntryKind = EntryKind.NONE
    entry: float = 0.0
    stop_loss: float = 0.0
    take_profit: float = 0.0
    risk_reward: float = 0.0
    ref_level: float = 0.0
    time: Optional[pd.Timestamp] = None
    note: str = ""


def atr_at(high: np.ndarray, low: np.ndarray, close: np.ndarray, i: int, period: int) -> float:
    if i - period < 0:
        return 0.0
    total = 0.0
    for j in range(i - period + 1, i + 1):
        tr = max(high[j] - low[j], abs(high[j] - close[j - 1]), abs(low[j] - close[j - 1]))
        total += tr
    return total / period


def is_swing_high(high: np.ndarray, i: int, left: int, right: int) -> bool:
    n = len(high)
    if i - left < 0 or i + right >= n:
        return False
    for k in range(1, left + 1):
        if high[i - k] >= high[i]:
            return False
    for k in range(1, right + 1):
        if high[i + k] > high[i]:
            return False
    return True


def is_swing_low(low: np.ndarray, i: int, left: int, right: int) -> bool:
    n = len(low)
    if i - left < 0 or i + right >= n:
        return False
    for k in range(1, left + 1):
        if low[i - k] <= low[i]:
            return False
    for k in range(1, right + 1):
        if low[i + k] < low[i]:
            return False
    return True


def bias_from_swings(high, low, close, end: int, left: int, right: int, lookback: int) -> Bias:
    sh: list[float] = []
    sl: list[float] = []
    start = max(left, end - lookback)
    for i in range(end - right, start + left - 1, -1):
        if len(sh) < 2 and is_swing_high(high, i, left, right):
            sh.append(high[i])
        if len(sl) < 2 and is_swing_low(low, i, left, right):
            sl.append(low[i])
        if len(sh) >= 2 and len(sl) >= 2:
            break
    if len(sh) >= 2 and len(sl) >= 2:
        hh, hl = sh[0] > sh[1], sl[0] > sl[1]
        lh, ll = sh[0] < sh[1], sl[0] < sl[1]
        if hh and hl:
            return Bias.BULL
        if lh and ll:
            return Bias.BEAR
    return Bias.NEUTRAL


def nearest_swing_low(low, close, end, left, right, lookback):
    start = max(left, end - lookback)
    for i in range(end - right, start + left - 1, -1):
        if not is_swing_low(low, i, left, right):
            continue
        broken = any(close[j] < low[i] for j in range(i + right + 1, end + 1))
        return low[i], i, broken
    return None, -1, True


def nearest_swing_high(high, close, end, left, right, lookback):
    start = max(left, end - lookback)
    for i in range(end - right, start + left - 1, -1):
        if not is_swing_high(high, i, left, right):
            continue
        broken = any(close[j] > high[i] for j in range(i + right + 1, end + 1))
        return high[i], i, broken
    return None, -1, True


def detect_sweep(o, h, l, c, end, atr, cfg: Config, high, low, close):
    swept_low = swept_high = False
    low_lvl = high_lvl = 0.0
    sl, _, sl_broken = nearest_swing_low(low, close, end - 1, cfg.swing_left, cfg.swing_right, cfg.structure_lookback)
    sh, _, sh_broken = nearest_swing_high(high, close, end - 1, cfg.swing_left, cfg.swing_right, cfg.structure_lookback)
    wick = cfg.sweep_wick_atr * atr
    if sl is not None and not sl_broken and l < sl - wick and c > sl and c > o:
        swept_low, low_lvl = True, sl
    if sh is not None and not sh_broken and h > sh + wick and c < sh and c < o:
        swept_high, high_lvl = True, sh
    return swept_low, low_lvl, swept_high, high_lvl


def remember(mem: SweepMemory, end: int, cfg: Config, swept_low, low_lvl, swept_high, high_lvl):
    if mem.has_low and end - mem.low_bar > cfg.sweep_lookback:
        mem.has_low = False
        mem.low_consumed = False
        mem.low_left_zone = False
    if mem.has_high and end - mem.high_bar > cfg.sweep_lookback:
        mem.has_high = False
        mem.high_consumed = False
        mem.high_left_zone = False
    if swept_low:
        mem.has_low, mem.low_level, mem.low_bar = True, low_lvl, end
        mem.low_consumed = False
        mem.low_left_zone = False
    if swept_high:
        mem.has_high, mem.high_level, mem.high_bar = True, high_lvl, end
        mem.high_consumed = False
        mem.high_left_zone = False


def evaluate_bar(
    open_,
    high,
    low,
    close,
    times,
    i: int,
    cfg: Config,
    consensus: Bias,
    mem: SweepMemory,
) -> Optional[Signal]:
    atr = atr_at(high, low, close, i, cfg.atr_period)
    if atr <= 0:
        return None
    o, h, l, c = open_[i], high[i], low[i], close[i]
    swept_low, low_lvl, swept_high, high_lvl = detect_sweep(o, h, l, c, i, atr, cfg, high, low, close)
    remember(mem, i, cfg, swept_low, low_lvl, swept_high, high_lvl)

    support = mem.low_level if mem.has_low else None
    resist = mem.high_level if mem.has_high else None
    sl_price, _, sl_broken = nearest_swing_low(low, close, i, cfg.swing_left, cfg.swing_right, cfg.structure_lookback)
    sh_price, _, sh_broken = nearest_swing_high(high, close, i, cfg.swing_left, cfg.swing_right, cfg.structure_lookback)
    if support is None and sl_price is not None and not sl_broken and c > sl_price:
        support = sl_price
    if resist is None and sh_price is not None and not sh_broken and c < sh_price:
        resist = sh_price

    rng = h - l
    if rng <= 0:
        return None
    body = abs(c - o) / rng
    bull = c > o and body >= cfg.confirm_body_ratio
    bear = c < o and body >= cfg.confirm_body_ratio

    if mem.has_low and not mem.low_consumed and c > mem.low_level + cfg.zone_atr * atr:
        mem.low_left_zone = True
    if mem.has_high and not mem.high_consumed and c < mem.high_level - cfg.zone_atr * atr:
        mem.high_left_zone = True

    bull_ok = (not cfg.require_htf_align) or consensus == Bias.BULL
    bear_ok = (not cfg.require_htf_align) or consensus == Bias.BEAR

    if bull_ok and support is not None:
        sweep_ok = (not cfg.require_sweep) or mem.has_low
        unused = (not cfg.one_per_setup) or not mem.low_consumed
        pulled = (not cfg.require_sweep) or mem.low_left_zone
        if sweep_ok and unused and pulled:
            zone_bot = support - cfg.zone_atr * atr
            zone_top = support + cfg.zone_atr * atr
            touched = (zone_bot <= l <= zone_top) or (l <= support <= c)
            after = (not mem.has_low) or (i > mem.low_bar)
            if touched and after and bull and c >= support:
                sl = min(zone_bot, support) - cfg.stop_buf_atr * atr
                risk = c - sl
                if risk > 0:
                    tp = c + cfg.tp_rr * risk
                    rr = (tp - c) / risk
                    if rr >= cfg.min_rr:
                        if cfg.one_per_setup:
                            mem.low_consumed = True
                        return Signal(True, Side.BUY, EntryKind.PULLBACK_SUPPORT, c, sl, tp, rr, support, times[i], "已掃除下方/回踩支撐")

    if bear_ok and resist is not None:
        sweep_ok = (not cfg.require_sweep) or mem.has_high
        unused = (not cfg.one_per_setup) or not mem.high_consumed
        pulled = (not cfg.require_sweep) or mem.high_left_zone
        if sweep_ok and unused and pulled:
            zone_top = resist + cfg.zone_atr * atr
            zone_bot = resist - cfg.zone_atr * atr
            touched = (zone_bot <= h <= zone_top) or (c <= resist <= h)
            after = (not mem.has_high) or (i > mem.high_bar)
            if touched and after and bear and c <= resist:
                sl = max(zone_top, resist) + cfg.stop_buf_atr * atr
                risk = sl - c
                if risk > 0:
                    tp = c - cfg.tp_rr * risk
                    rr = (c - tp) / risk
                    if rr >= cfg.min_rr:
                        if cfg.one_per_setup:
                            mem.high_consumed = True
                        return Signal(True, Side.SELL, EntryKind.PULLBACK_RESIST, c, sl, tp, rr, resist, times[i], "已掃除上方/回踩阻力")
    return None


def detect_structure(df: pd.DataFrame, cfg: Optional[Config] = None, consensus: Bias = Bias.BULL) -> pd.DataFrame:
    cfg = cfg or Config()
    data = df.copy()
    if not isinstance(data.index, pd.DatetimeIndex):
        raise ValueError("DatetimeIndex required")
    open_ = data["open"].to_numpy(float)
    high = data["high"].to_numpy(float)
    low = data["low"].to_numpy(float)
    close = data["close"].to_numpy(float)
    times = list(data.index)
    mem = SweepMemory()
    rows = []
    start = cfg.atr_period + cfg.swing_left + cfg.swing_right + 2
    for i in range(start, len(data) - 1):  # skip forming last bar
        local = bias_from_swings(high, low, close, i, cfg.swing_left, cfg.swing_right, min(40, cfg.structure_lookback))
        use = consensus if consensus != Bias.NEUTRAL else local
        sig = evaluate_bar(open_, high, low, close, times, i, cfg, use, mem)
        if sig and sig.valid:
            rows.append(
                {
                    "time": sig.time,
                    "side": int(sig.side),
                    "kind": sig.kind.value,
                    "entry": sig.entry,
                    "stop_loss": sig.stop_loss,
                    "take_profit": sig.take_profit,
                    "risk_reward": sig.risk_reward,
                    "ref_level": sig.ref_level,
                    "note": sig.note,
                }
            )
    return pd.DataFrame(rows)
