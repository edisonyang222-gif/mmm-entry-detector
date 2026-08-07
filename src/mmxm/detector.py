from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Optional

import numpy as np
import pandas as pd

from .indicators import atr, detect_fvg_at, is_displacement_candle, rolling_range
from .models import (
    AccumulationRange,
    EntrySignal,
    ModelPhase,
    ModelSide,
    ModelState,
)


REQUIRED_COLUMNS = ("open", "high", "low", "close")


@dataclass(slots=True)
class MMXMConfig:
    """Tunable parameters for MMXM phase detection."""

    accumulation_lookback: int = 20
    atr_period: int = 14
    max_range_atr_mult: float = 3.5
    manipulation_atr_mult: float = 0.3
    displacement_body_ratio: float = 0.65
    displacement_atr_mult: float = 0.8
    min_risk_reward: float = 1.5
    entry_fill: str = "midpoint"  # midpoint | proximal | distal
    stop_buffer_atr_mult: float = 0.05
    require_close_through_range: bool = True


class MMXMDetector:
    """
    Detect ICT Market Maker Buy/Sell Model entries on OHLCV bars.

    Phase flow:
      1. Accumulation — tight range relative to ATR
      2. Manipulation — SSL (buy) / BSL (sell) liquidity sweep
      3. Expansion — displacement that closes through the range
      4. Entry — FVG formed on the displacement leg (Phase-4 style)
    """

    def __init__(self, config: Optional[MMXMConfig] = None) -> None:
        self.config = config or MMXMConfig()

    def scan(self, df: pd.DataFrame) -> list[EntrySignal]:
        frame = self._normalize(df)
        atr_series = atr(frame, self.config.atr_period)
        range_high, range_low = rolling_range(frame, self.config.accumulation_lookback)

        buy_state = ModelState(side=ModelSide.BUY)
        sell_state = ModelState(side=ModelSide.SELL)
        signals: list[EntrySignal] = []

        start = max(self.config.accumulation_lookback, self.config.atr_period)
        for i in range(start, len(frame)):
            atr_value = float(atr_series.iloc[i])
            if not np.isfinite(atr_value) or atr_value <= 0:
                continue

            rh = float(range_high.iloc[i])
            rl = float(range_low.iloc[i])
            if not np.isfinite(rh) or not np.isfinite(rl) or rh <= rl:
                continue

            row = frame.iloc[i]
            for state in (buy_state, sell_state):
                signal = self._step(
                    state=state,
                    frame=frame,
                    index=i,
                    row=row,
                    atr_value=atr_value,
                    range_high=rh,
                    range_low=rl,
                )
                if signal is not None:
                    signals.append(signal)

        return signals

    def _step(
        self,
        *,
        state: ModelState,
        frame: pd.DataFrame,
        index: int,
        row: pd.Series,
        atr_value: float,
        range_high: float,
        range_low: float,
    ) -> Optional[EntrySignal]:
        cfg = self.config
        high = float(row["high"])
        low = float(row["low"])
        open_ = float(row["open"])
        close = float(row["close"])

        # Reset completed / invalidated models so we can hunt the next cycle.
        if state.phase in {ModelPhase.ENTRY, ModelPhase.COMPLETE, ModelPhase.INVALIDATED}:
            state.phase = ModelPhase.IDLE
            state.accumulation = None
            state.manipulation_index = None
            state.manipulation_extreme = None
            state.expansion_index = None
            state.fvg = None
            state.notes.clear()

        range_width = range_high - range_low
        is_tight = range_width <= cfg.max_range_atr_mult * atr_value

        # Freeze the prior accumulation box before updating with the current bar,
        # otherwise the sweep candle widens the range and cancels itself.
        frozen_acc = state.accumulation

        if state.phase in {ModelPhase.IDLE, ModelPhase.ACCUMULATION}:
            if (
                state.phase == ModelPhase.ACCUMULATION
                and frozen_acc is not None
                and self._detect_manipulation(
                    state.side, high, low, frozen_acc, atr_value
                )
            ):
                state.phase = ModelPhase.MANIPULATION
                state.manipulation_index = index
                state.manipulation_extreme = (
                    low if state.side == ModelSide.BUY else high
                )
                # Keep the frozen pre-sweep accumulation for later expansion/entry.
                state.accumulation = frozen_acc
                return None

            if is_tight:
                state.phase = ModelPhase.ACCUMULATION
                state.accumulation = AccumulationRange(
                    start_index=index - cfg.accumulation_lookback + 1,
                    end_index=index,
                    high=range_high,
                    low=range_low,
                )
            else:
                state.phase = ModelPhase.IDLE
                state.accumulation = None
            return None

        assert state.accumulation is not None
        acc = state.accumulation

        if state.phase == ModelPhase.MANIPULATION:
            # Track deeper sweep extreme while waiting for expansion.
            if state.side == ModelSide.BUY:
                if low < (state.manipulation_extreme or low):
                    state.manipulation_extreme = low
                    state.manipulation_index = index
            else:
                if high > (state.manipulation_extreme or high):
                    state.manipulation_extreme = high
                    state.manipulation_index = index

            if self._detect_expansion(
                state.side, open_, high, low, close, atr_value, acc
            ):
                state.phase = ModelPhase.EXPANSION
                state.expansion_index = index
                fvg = detect_fvg_at(frame, index, state.side)
                if fvg is None:
                    # Displacement without FVG — still mark expansion; wait one more bar.
                    state.notes.append("expansion_without_immediate_fvg")
                    return None
                state.fvg = fvg
                return self._build_entry(state, frame, index)

            # Invalidation: opposite extreme breaks far beyond accumulation.
            if state.side == ModelSide.BUY and close < acc.low - cfg.manipulation_atr_mult * atr_value * 3:
                state.phase = ModelPhase.INVALIDATED
            elif state.side == ModelSide.SELL and close > acc.high + cfg.manipulation_atr_mult * atr_value * 3:
                state.phase = ModelPhase.INVALIDATED
            return None

        if state.phase == ModelPhase.EXPANSION:
            if state.fvg is None:
                fvg = detect_fvg_at(frame, index, state.side)
                if fvg is not None:
                    state.fvg = fvg
                    return self._build_entry(state, frame, index)
                # Give a short window after expansion.
                if state.expansion_index is not None and index - state.expansion_index >= 3:
                    state.phase = ModelPhase.INVALIDATED
            return None

        return None

    def _detect_manipulation(
        self,
        side: ModelSide,
        high: float,
        low: float,
        acc: AccumulationRange,
        atr_value: float,
    ) -> bool:
        threshold = self.config.manipulation_atr_mult * atr_value
        if side == ModelSide.BUY:
            return low < acc.low - threshold
        return high > acc.high + threshold

    def _detect_expansion(
        self,
        side: ModelSide,
        open_: float,
        high: float,
        low: float,
        close: float,
        atr_value: float,
        acc: AccumulationRange,
    ) -> bool:
        bullish = side == ModelSide.BUY
        if not is_displacement_candle(
            open_,
            high,
            low,
            close,
            atr_value,
            bullish=bullish,
            body_ratio=self.config.displacement_body_ratio,
            min_atr_mult=self.config.displacement_atr_mult,
        ):
            return False

        if not self.config.require_close_through_range:
            return True

        if bullish:
            return close > acc.high
        return close < acc.low

    def _entry_price(self, state: ModelState, fill: str) -> float:
        assert state.fvg is not None
        if fill == "proximal":
            return state.fvg.proximal
        if fill == "distal":
            return state.fvg.distal
        return state.fvg.midpoint

    def _targets(
        self,
        state: ModelState,
        entry: float,
        atr_value: float,
    ) -> tuple[float, float, float, float]:
        """Return stop, take_profit, risk, reward for a candidate entry."""
        assert state.accumulation is not None
        assert state.manipulation_extreme is not None

        buffer = 0.0
        if np.isfinite(atr_value):
            buffer = self.config.stop_buffer_atr_mult * atr_value

        if state.side == ModelSide.BUY:
            stop = state.manipulation_extreme - buffer
            manip_depth = state.accumulation.high - state.manipulation_extreme
            measured = state.accumulation.high + manip_depth
            range_projection = state.accumulation.high + state.accumulation.width
            take_profit = max(measured, range_projection)
            risk = entry - stop
            reward = take_profit - entry
        else:
            stop = state.manipulation_extreme + buffer
            manip_depth = state.manipulation_extreme - state.accumulation.low
            measured = state.accumulation.low - manip_depth
            range_projection = state.accumulation.low - state.accumulation.width
            take_profit = min(measured, range_projection)
            risk = stop - entry
            reward = entry - take_profit
        return stop, take_profit, risk, reward

    def _build_entry(
        self,
        state: ModelState,
        frame: pd.DataFrame,
        index: int,
    ) -> Optional[EntrySignal]:
        assert state.accumulation is not None
        assert state.manipulation_extreme is not None
        assert state.fvg is not None

        atr_series = atr(frame, self.config.atr_period)
        atr_value = float(atr_series.iloc[index])

        # Prefer configured fill; fall back to proximal if RR is too low.
        fill_order = [self.config.entry_fill]
        if "proximal" not in fill_order:
            fill_order.append("proximal")

        chosen: tuple[str, float, float, float, float] | None = None
        for fill in fill_order:
            entry = self._entry_price(state, fill)
            stop, take_profit, risk, reward = self._targets(state, entry, atr_value)
            if risk <= 0 or reward <= 0:
                continue
            rr = reward / risk
            if rr >= self.config.min_risk_reward:
                chosen = (fill, entry, stop, take_profit, rr)
                break
            state.notes.append(f"rr_below_min:{fill}:{rr:.2f}")

        if chosen is None:
            state.phase = ModelPhase.INVALIDATED
            return None

        fill, entry, stop, take_profit, rr = chosen
        if fill != self.config.entry_fill:
            state.notes.append(f"entry_fill_fallback:{fill}")

        ts = None
        if "timestamp" in frame.columns:
            value = frame.iloc[index]["timestamp"]
            ts = str(value)

        state.phase = ModelPhase.ENTRY
        return EntrySignal(
            side=state.side,
            bar_index=index,
            timestamp=ts,
            entry=float(entry),
            stop_loss=float(stop),
            take_profit=float(take_profit),
            risk_reward=float(rr),
            accumulation_high=float(state.accumulation.high),
            accumulation_low=float(state.accumulation.low),
            manipulation_extreme=float(state.manipulation_extreme),
            fvg_top=float(state.fvg.top),
            fvg_bottom=float(state.fvg.bottom),
        )

    @staticmethod
    def _normalize(df: pd.DataFrame) -> pd.DataFrame:
        if df is None or df.empty:
            raise ValueError("DataFrame is empty")

        frame = df.copy()
        frame.columns = [str(c).strip().lower() for c in frame.columns]

        missing = [c for c in REQUIRED_COLUMNS if c not in frame.columns]
        if missing:
            raise ValueError(f"Missing required columns: {missing}")

        for col in REQUIRED_COLUMNS:
            frame[col] = pd.to_numeric(frame[col], errors="coerce")

        if frame[list(REQUIRED_COLUMNS)].isna().any().any():
            raise ValueError("OHLC columns contain non-numeric / NaN values")

        if "timestamp" not in frame.columns and isinstance(frame.index, pd.DatetimeIndex):
            frame = frame.reset_index()
            frame.rename(columns={frame.columns[0]: "timestamp"}, inplace=True)

        return frame.reset_index(drop=True)


def signals_to_frame(signals: Iterable[EntrySignal]) -> pd.DataFrame:
    rows = [s.to_dict() for s in signals]
    if not rows:
        return pd.DataFrame(
            columns=[
                "side",
                "bar_index",
                "timestamp",
                "entry",
                "stop_loss",
                "take_profit",
                "risk_reward",
                "accumulation_high",
                "accumulation_low",
                "manipulation_extreme",
                "fvg_top",
                "fvg_bottom",
                "phase",
            ]
        )
    return pd.DataFrame(rows)
