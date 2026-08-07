from __future__ import annotations

import pandas as pd
import pytest

from ohlc.detector import Config, Mode, Side, SignalType, DayTracker, detect, evaluate_bar, session_day_key


def _bar(ts, o, h, l, c):
    return pd.Timestamp(ts), o, h, l, c


def test_session_day_key_midnight():
    assert session_day_key(pd.Timestamp("2024-01-02 09:00"), 0) == pd.Timestamp("2024-01-02 00:00")
    assert session_day_key(pd.Timestamp("2024-01-02 01:00"), 22) == pd.Timestamp("2024-01-01 22:00")
    assert session_day_key(pd.Timestamp("2024-01-02 23:00"), 22) == pd.Timestamp("2024-01-02 22:00")


def test_pdh_breakout_signal():
    cfg = Config(mode=Mode.BREAKOUT, atr_period=2, orb_bars=2, one_per_day_per_side=True, min_rr=1.0, tp_rr=2.0)
    tr = DayTracker()
    # Day 1: establish PDH=110 PDL=100
    day1 = [
        _bar("2024-06-03 00:00", 105, 108, 104, 106),
        _bar("2024-06-03 01:00", 106, 110, 105, 109),
        _bar("2024-06-03 02:00", 109, 109.5, 100, 101),
    ]
    # Day 2: open below PDH then break
    day2 = [
        _bar("2024-06-04 00:00", 105, 106, 104, 105),
        _bar("2024-06-04 01:00", 105, 107, 104.5, 106),
        _bar("2024-06-04 02:00", 106, 108, 105.5, 107),  # ORB forming
        _bar("2024-06-04 03:00", 107, 112, 106.5, 111),  # break PDH=110
    ]
    atr = 2.0
    prev = None
    sig = None
    for ts, o, h, l, c in day1 + day2:
        pc = prev if prev is not None else c
        sig = evaluate_bar(tr, cfg, ts, o, h, l, c, pc, atr)
        prev = c
    assert sig is not None
    assert sig.valid
    assert sig.side == Side.BUY
    assert sig.type == SignalType.PDH_BREAKOUT
    assert sig.entry == 111
    assert sig.stop_loss < sig.entry < sig.take_profit


def test_pdl_rejection_signal():
    cfg = Config(mode=Mode.REJECTION, atr_period=2, orb_bars=1, reject_body_ratio=0.3, min_rr=1.0, tp_rr=2.0)
    tr = DayTracker()
    day1 = [
        _bar("2024-06-03 00:00", 105, 110, 100, 105),
    ]
    day2 = [
        _bar("2024-06-04 00:00", 105, 106, 104, 105),
        # pierce PDL=100 then close back up bullish
        _bar("2024-06-04 01:00", 102, 104, 99, 103.5),
    ]
    atr = 2.0
    prev = None
    last = None
    for ts, o, h, l, c in day1 + day2:
        pc = prev if prev is not None else c
        last = evaluate_bar(tr, cfg, ts, o, h, l, c, pc, atr)
        prev = c
    assert last is not None
    assert last.side == Side.BUY
    assert last.type == SignalType.PDL_REJECTION


def test_detect_on_dataframe_one_per_day():
    # synthetic continuous series
    idx = pd.date_range("2024-06-01", periods=48, freq="h")
    close = pd.Series(range(100, 148), index=idx, dtype=float)
    high = close + 1.5
    low = close - 1.5
    open_ = close.shift(1).fillna(close.iloc[0])
    # force a clear PDH break on second day
    df = pd.DataFrame({"open": open_, "high": high, "low": low, "close": close})
    # inflate second-day highs so breakout can fire
    df.loc[idx[30]:, "high"] = df.loc[idx[30]:, "close"] + 5
    df.loc[idx[35], "close"] = df.loc[idx[24]:idx[29], "high"].max() + 3
    df.loc[idx[35], "high"] = df.loc[idx[35], "close"] + 0.5

    cfg = Config(mode=Mode.BREAKOUT, atr_period=5, orb_bars=2, one_per_day_per_side=True, min_rr=1.0)
    signals = detect(df, cfg)
    assert isinstance(signals, pd.DataFrame)
    if len(signals):
        assert set(signals["side"]).issubset({1, -1})
        # at most one buy per calendar session day
        buys = signals[signals["side"] == 1]
        if len(buys):
            days = pd.to_datetime(buys["time"]).dt.floor("D")
            assert days.duplicated().sum() == 0
