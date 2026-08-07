from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Optional

import numpy as np
import pandas as pd

from .indicators import atr, detect_fvg_at, is_displacement_candle, rolling_range
from .models import (
    AccumulationRange,
    EntrySignal,
    FairValueGap,
    ModelPhase,
    ModelSide,
    ModelState,
)


REQUIRED_COLUMNS = ("open", "high", "low", "close")


@dataclass(slots=True)
class MMXMConfig:
    """Tunable parameters for MMXM phase detection."""

    accumulation_lookback: int = 20
    min_accumulation_bars: int = 5
    atr_period: int = 14
    max_range_atr_mult: float = 2.5
    manipulation_atr_mult: float = 0.25
    min_sweep_of_range: float = 0.15
    displacement_body_ratio: float = 0.55
    displacement_atr_mult: float = 0.9
    min_risk_reward: float = 2.0
    entry_fill: str = "midpoint"  # midpoint | proximal
    stop_buffer_atr_mult: float = 0.05
    require_close_through_range: bool = True
    max_wait_bars: int = 20
    require_close_back: bool = True


class MMXMDetector:
    """
    Detect ICT Market Maker Buy/Sell Model entries on OHLCV bars.

    Phase flow:
      1. Accumulation — tight range held for N bars
      2. Manipulation — SSL (buy) / BSL (sell) liquidity sweep
      3. Expansion — displacement + MSS through range + FVG
      4. Wait — arm entry at FVG CE / proximal
      5. Entry — Phase-4 retrace tap into FVG
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

    def _reset(self, state: ModelState) -> None:
        state.phase = ModelPhase.IDLE
        state.accumulation = None
        state.accumulation_count = 0
        state.manipulation_index = None
        state.manipulation_extreme = None
        state.expansion_index = None
        state.fvg = None
        state.planned_entry = None
        state.planned_stop = None
        state.planned_tp = None
        state.notes.clear()

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

        if state.phase in {ModelPhase.ENTRY, ModelPhase.COMPLETE, ModelPhase.INVALIDATED}:
            self._reset(state)

        range_width = range_high - range_low
        is_tight = range_width <= cfg.max_range_atr_mult * atr_value

        if state.phase in {ModelPhase.IDLE, ModelPhase.ACCUMULATION}:
            frozen = state.accumulation
            if (
                state.phase == ModelPhase.ACCUMULATION
                and frozen is not None
                and state.accumulation_count >= cfg.min_accumulation_bars
            ):
                min_sweep = max(
                    cfg.manipulation_atr_mult * atr_value,
                    cfg.min_sweep_of_range * frozen.width,
                )
                swept = (
                    (frozen.low - low) >= min_sweep
                    if state.side == ModelSide.BUY
                    else (high - frozen.high) >= min_sweep
                )
                if swept:
                    state.phase = ModelPhase.MANIPULATION
                    state.manipulation_index = index
                    state.manipulation_extreme = low if state.side == ModelSide.BUY else high
                    return None
                if is_tight:
                    state.accumulation_count += 1
                    return None
                self._reset(state)
                return None

            if is_tight:
                if state.phase == ModelPhase.IDLE or frozen is None:
                    state.phase = ModelPhase.ACCUMULATION
                    state.accumulation = AccumulationRange(
                        start_index=index - cfg.accumulation_lookback + 1,
                        end_index=index,
                        high=range_high,
                        low=range_low,
                    )
                    # The lookback window itself already proved consolidation.
                    state.accumulation_count = cfg.accumulation_lookback
                else:
                    # Keep / slightly tighten frozen box before unlock.
                    new_high = min(frozen.high, range_high)
                    new_low = max(frozen.low, range_low)
                    if new_high > new_low:
                        state.accumulation = AccumulationRange(
                            start_index=frozen.start_index,
                            end_index=index,
                            high=new_high,
                            low=new_low,
                        )
                    else:
                        state.accumulation = AccumulationRange(
                            start_index=index - cfg.accumulation_lookback + 1,
                            end_index=index,
                            high=range_high,
                            low=range_low,
                        )
                    state.accumulation_count += 1
            else:
                self._reset(state)
            return None

        assert state.accumulation is not None
        acc = state.accumulation

        if state.phase == ModelPhase.MANIPULATION:
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
                if fvg is not None:
                    state.fvg = fvg
                return None

            thr = max(cfg.manipulation_atr_mult * atr_value, acc.width) * 1.5
            if state.side == ModelSide.BUY and close < acc.low - thr:
                state.phase = ModelPhase.INVALIDATED
            elif state.side == ModelSide.SELL and close > acc.high + thr:
                state.phase = ModelPhase.INVALIDATED
            return None

        if state.phase == ModelPhase.EXPANSION:
            if state.fvg is None:
                fvg = detect_fvg_at(frame, index, state.side)
                if fvg is not None:
                    state.fvg = fvg
                elif (
                    state.expansion_index is not None
                    and index - state.expansion_index >= 3
                ):
                    state.phase = ModelPhase.INVALIDATED
                return None

            armed = self._arm_wait(state, atr_value)
            if not armed:
                state.phase = ModelPhase.INVALIDATED
            return None

        if state.phase == ModelPhase.WAIT:
            assert state.fvg is not None
            assert state.planned_entry is not None
            assert state.planned_stop is not None
            assert state.planned_tp is not None

            fvg_bar = state.fvg.start_index + 1  # approximate formation bar
            if index - fvg_bar >= cfg.max_wait_bars:
                state.phase = ModelPhase.INVALIDATED
                return None

            if state.side == ModelSide.BUY:
                if close < state.planned_stop or close < state.fvg.bottom:
                    state.phase = ModelPhase.INVALIDATED
                    return None
                tapped = (low <= state.fvg.top and high >= state.fvg.bottom) or (
                    low <= state.planned_entry <= high
                )
                close_ok = (not cfg.require_close_back) or (
                    close >= state.planned_entry or close >= state.fvg.bottom
                )
            else:
                if close > state.planned_stop or close > state.fvg.top:
                    state.phase = ModelPhase.INVALIDATED
                    return None
                tapped = (high >= state.fvg.bottom and low <= state.fvg.top) or (
                    low <= state.planned_entry <= high
                )
                close_ok = (not cfg.require_close_back) or (
                    close <= state.planned_entry or close <= state.fvg.top
                )

            if tapped and close_ok:
                return self._emit_planned(state, frame, index)
            return None

        return None

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
        return close > acc.high if bullish else close < acc.low

    def _entry_price(self, fvg: FairValueGap, fill: str) -> float:
        proximal = fvg.proximal
        mid = fvg.midpoint
        return proximal if fill == "proximal" else mid

    def _targets(
        self,
        state: ModelState,
        entry: float,
        atr_value: float,
    ) -> tuple[float, float, float, float]:
        assert state.accumulation is not None
        assert state.manipulation_extreme is not None
        buffer = self.config.stop_buffer_atr_mult * atr_value if atr_value > 0 else 0.0

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

    def _arm_wait(self, state: ModelState, atr_value: float) -> bool:
        assert state.fvg is not None
        fill = self.config.entry_fill if self.config.entry_fill in {"midpoint", "proximal"} else "midpoint"
        entry = self._entry_price(state.fvg, fill)
        stop, take_profit, risk, reward = self._targets(state, entry, atr_value)
        if risk <= 0 or reward <= 0:
            return False
        rr = reward / risk
        if rr < self.config.min_risk_reward:
            # try proximal once
            if fill != "proximal":
                entry = self._entry_price(state.fvg, "proximal")
                stop, take_profit, risk, reward = self._targets(state, entry, atr_value)
                if risk <= 0 or reward <= 0 or reward / risk < self.config.min_risk_reward:
                    return False
            else:
                return False
        state.planned_entry = float(entry)
        state.planned_stop = float(stop)
        state.planned_tp = float(take_profit)
        state.phase = ModelPhase.WAIT
        return True

    def _emit_planned(
        self,
        state: ModelState,
        frame: pd.DataFrame,
        index: int,
    ) -> EntrySignal:
        assert state.accumulation is not None
        assert state.manipulation_extreme is not None
        assert state.fvg is not None
        assert state.planned_entry is not None
        assert state.planned_stop is not None
        assert state.planned_tp is not None

        entry = state.planned_entry
        stop = state.planned_stop
        take_profit = state.planned_tp
        risk = abs(entry - stop)
        reward = abs(take_profit - entry)
        rr = reward / risk if risk > 0 else 0.0

        ts = None
        if "timestamp" in frame.columns:
            ts = str(frame.iloc[index]["timestamp"])

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
