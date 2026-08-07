from __future__ import annotations

import numpy as np
import pandas as pd

from ohlc.structure import (
    Bias,
    Config,
    EntryKind,
    Side,
    SweepMemory,
    detect_structure,
    evaluate_bar,
    is_swing_high,
    is_swing_low,
)


def test_swing_pivot_non_repaint_window():
    # index 5 is unique high with 2 left / 2 right lower
    high = np.array([1, 2, 3, 4, 5, 10, 5, 4, 3, 2, 1], dtype=float)
    assert is_swing_high(high, 5, 2, 2)
    assert not is_swing_high(high, 4, 2, 2)  # right side not confirmed yet if we only had data to 5


def test_liquidity_sweep_then_pullback_buy():
    """Build: swing low -> sweep wick below -> later bullish reclaim pullback."""
    cfg = Config(
        swing_left=1,
        swing_right=1,
        atr_period=3,
        sweep_lookback=20,
        structure_lookback=30,
        sweep_wick_atr=0.01,
        zone_atr=0.5,
        confirm_body_ratio=0.3,
        stop_buf_atr=0.1,
        min_rr=1.0,
        tp_rr=2.0,
        require_htf_align=True,
        require_sweep=True,
        one_per_setup=True,
    )
    # Craft OHLC series (oldest first)
    rows = []
    # flat then make swing low at bar 5 (price 100)
    prices = [
        # o,h,l,c
        (105, 106, 104, 105),
        (105, 107, 104, 106),
        (106, 108, 105, 107),
        (107, 107.5, 103, 104),
        (104, 105, 102, 103),
        (103, 104, 100, 101),  # swing low candidate center=5 low=100
        (101, 103, 100.5, 102),
        (102, 104, 101, 103),
        # sweep below 100 then close back up (陽線收復)
        (99.5, 103.5, 98.5, 101.8),
        # displace up
        (101.8, 106, 101, 105.5),
        (105.5, 107, 104, 106),
        # pullback into support ~100 with bullish confirm (strong body)
        (101.0, 104.0, 100.1, 103.5),
        (103.5, 104.5, 102.5, 104.0),
        (104.0, 105.0, 103.0, 104.5),
    ]
    idx = pd.date_range("2024-07-01", periods=len(prices), freq="h")
    df = pd.DataFrame(prices, columns=["open", "high", "low", "close"], index=idx)
    # pad with ATR history
    pad_n = 8
    pad_idx = pd.date_range("2024-06-30", periods=pad_n, freq="h")
    pad = pd.DataFrame(
        {
            "open": np.full(pad_n, 105.0),
            "high": np.full(pad_n, 106.0),
            "low": np.full(pad_n, 104.0),
            "close": np.full(pad_n, 105.0),
        },
        index=pad_idx,
    )
    df = pd.concat([pad, df])
    signals = detect_structure(df, cfg, consensus=Bias.BULL)
    assert len(signals) >= 1
    assert signals.iloc[-1]["side"] == int(Side.BUY)
    assert signals.iloc[-1]["kind"] == EntryKind.PULLBACK_SUPPORT.value


def test_signal_stable_on_closed_bars_only():
    cfg = Config(require_htf_align=False, require_sweep=False, min_rr=1.0, atr_period=3, swing_left=1, swing_right=1)
    idx = pd.date_range("2024-01-01", periods=40, freq="h")
    close = np.linspace(100, 120, 40)
    df = pd.DataFrame(
        {
            "open": close - 0.3,
            "high": close + 1.0,
            "low": close - 1.0,
            "close": close,
        },
        index=idx,
    )
    a = detect_structure(df, cfg, consensus=Bias.BULL)
    b = detect_structure(df, cfg, consensus=Bias.BULL)
    # deterministic: same closed-bar inputs → same signals (不消失/不漂移)
    pd.testing.assert_frame_equal(a.reset_index(drop=True), b.reset_index(drop=True))
