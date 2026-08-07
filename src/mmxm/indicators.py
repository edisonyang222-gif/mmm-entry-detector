from __future__ import annotations

import numpy as np
import pandas as pd

from .models import FairValueGap, ModelSide


def true_range(high: pd.Series, low: pd.Series, close: pd.Series) -> pd.Series:
    prev_close = close.shift(1)
    ranges = pd.concat(
        [
            high - low,
            (high - prev_close).abs(),
            (low - prev_close).abs(),
        ],
        axis=1,
    )
    return ranges.max(axis=1)


def atr(df: pd.DataFrame, period: int = 14) -> pd.Series:
    tr = true_range(df["high"], df["low"], df["close"])
    return tr.rolling(window=period, min_periods=period).mean()


def rolling_range(df: pd.DataFrame, lookback: int) -> tuple[pd.Series, pd.Series]:
    highs = df["high"].rolling(window=lookback, min_periods=lookback).max()
    lows = df["low"].rolling(window=lookback, min_periods=lookback).min()
    return highs, lows


def is_displacement_candle(
    open_: float,
    high: float,
    low: float,
    close: float,
    atr_value: float,
    *,
    bullish: bool,
    body_ratio: float,
    min_atr_mult: float,
) -> bool:
    candle_range = high - low
    if candle_range <= 0 or not np.isfinite(atr_value) or atr_value <= 0:
        return False
    body = abs(close - open_)
    if body / candle_range < body_ratio:
        return False
    if candle_range < min_atr_mult * atr_value:
        return False
    if bullish:
        return close > open_
    return close < open_


def detect_fvg_at(
    df: pd.DataFrame,
    index: int,
    side: ModelSide,
) -> FairValueGap | None:
    """3-candle FVG ending at `index` (candle i-2, i-1, i)."""
    if index < 2:
        return None

    c0 = df.iloc[index - 2]
    c2 = df.iloc[index]

    if side == ModelSide.BUY:
        # Bullish FVG: current low above candle[i-2] high
        if c2["low"] > c0["high"]:
            top = float(c2["low"])
            bottom = float(c0["high"])
            return FairValueGap(
                side=side,
                start_index=index - 1,
                top=top,
                bottom=bottom,
                midpoint=(top + bottom) / 2.0,
            )
    else:
        # Bearish FVG: current high below candle[i-2] low
        if c2["high"] < c0["low"]:
            top = float(c0["low"])
            bottom = float(c2["high"])
            return FairValueGap(
                side=side,
                start_index=index - 1,
                top=top,
                bottom=bottom,
                midpoint=(top + bottom) / 2.0,
            )
    return None
