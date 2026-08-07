from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from mmxm.detector import MMXMConfig, MMXMDetector, signals_to_frame
from mmxm.indicators import atr, detect_fvg_at, is_displacement_candle
from mmxm.models import ModelSide


def _df_from_rows(rows: list[dict]) -> pd.DataFrame:
    return pd.DataFrame(rows)


def test_atr_has_expected_warmup():
    n = 30
    df = pd.DataFrame(
        {
            "open": np.linspace(100, 110, n),
            "high": np.linspace(100.5, 110.5, n),
            "low": np.linspace(99.5, 109.5, n),
            "close": np.linspace(100.2, 110.2, n),
        }
    )
    values = atr(df, period=14)
    assert values.isna().sum() == 13
    assert values.iloc[13] > 0


def test_detect_bullish_fvg():
    df = _df_from_rows(
        [
            {"open": 10, "high": 10.5, "low": 9.8, "close": 10.2},
            {"open": 10.3, "high": 11.0, "low": 10.2, "close": 10.9},
            {"open": 11.2, "high": 11.8, "low": 11.1, "close": 11.6},  # low > first high
        ]
    )
    fvg = detect_fvg_at(df, 2, ModelSide.BUY)
    assert fvg is not None
    assert fvg.bottom == pytest.approx(10.5)
    assert fvg.top == pytest.approx(11.1)


def test_displacement_candle_rules():
    assert is_displacement_candle(
        100, 102, 99.8, 101.8, atr_value=1.0, bullish=True, body_ratio=0.65, min_atr_mult=0.8
    )
    assert not is_displacement_candle(
        100, 100.4, 99.9, 100.2, atr_value=1.0, bullish=True, body_ratio=0.65, min_atr_mult=0.8
    )


def test_detector_finds_synthetic_mmbm():
    from examples.generate_sample import build_mmbm_sample

    df = build_mmbm_sample()
    # Loosen RR for synthetic geometry so the structural path is tested.
    detector = MMXMDetector(
        MMXMConfig(
            accumulation_lookback=20,
            atr_period=14,
            max_range_atr_mult=4.0,
            manipulation_atr_mult=0.2,
            displacement_body_ratio=0.5,
            displacement_atr_mult=0.5,
            min_risk_reward=1.0,
        )
    )
    signals = detector.scan(df)
    assert signals, "expected at least one MMXM signal on synthetic MMBM data"
    buy_signals = [s for s in signals if s.side == ModelSide.BUY]
    assert buy_signals, "expected an MMBM (buy) signal"
    sig = buy_signals[0]
    assert sig.entry > sig.stop_loss
    assert sig.take_profit > sig.entry
    assert sig.risk_reward >= 1.0

    frame = signals_to_frame(signals)
    assert "side" in frame.columns
    assert len(frame) == len(signals)


def test_missing_columns_raise():
    df = pd.DataFrame({"open": [1], "high": [2], "close": [1.5]})
    with pytest.raises(ValueError, match="Missing required columns"):
        MMXMDetector().scan(df)
