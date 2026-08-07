from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


class ModelSide(str, Enum):
    BUY = "MMBM"  # Market Maker Buy Model
    SELL = "MMSM"  # Market Maker Sell Model


class ModelPhase(str, Enum):
    IDLE = "idle"
    ACCUMULATION = "accumulation"
    MANIPULATION = "manipulation"
    EXPANSION = "expansion"
    WAIT = "wait"
    ENTRY = "entry"
    COMPLETE = "complete"
    INVALIDATED = "invalidated"


@dataclass(slots=True)
class FairValueGap:
    side: ModelSide
    start_index: int
    top: float
    bottom: float
    midpoint: float

    @property
    def proximal(self) -> float:
        return self.bottom if self.side == ModelSide.BUY else self.top

    @property
    def distal(self) -> float:
        return self.top if self.side == ModelSide.BUY else self.bottom


@dataclass(slots=True)
class AccumulationRange:
    start_index: int
    end_index: int
    high: float
    low: float

    @property
    def midpoint(self) -> float:
        return (self.high + self.low) / 2.0

    @property
    def width(self) -> float:
        return self.high - self.low


@dataclass(slots=True)
class ModelState:
    side: ModelSide
    phase: ModelPhase = ModelPhase.IDLE
    accumulation: Optional[AccumulationRange] = None
    accumulation_count: int = 0
    manipulation_index: Optional[int] = None
    manipulation_extreme: Optional[float] = None
    expansion_index: Optional[int] = None
    fvg: Optional[FairValueGap] = None
    planned_entry: Optional[float] = None
    planned_stop: Optional[float] = None
    planned_tp: Optional[float] = None
    notes: list[str] = field(default_factory=list)


@dataclass(slots=True)
class EntrySignal:
    """Tradeable MMXM Phase-4 style entry after confirmed expansion."""

    side: ModelSide
    bar_index: int
    timestamp: Optional[str]
    entry: float
    stop_loss: float
    take_profit: float
    risk_reward: float
    accumulation_high: float
    accumulation_low: float
    manipulation_extreme: float
    fvg_top: float
    fvg_bottom: float
    phase: ModelPhase = ModelPhase.ENTRY

    def to_dict(self) -> dict:
        return {
            "side": self.side.value,
            "bar_index": self.bar_index,
            "timestamp": self.timestamp,
            "entry": self.entry,
            "stop_loss": self.stop_loss,
            "take_profit": self.take_profit,
            "risk_reward": round(self.risk_reward, 3),
            "accumulation_high": self.accumulation_high,
            "accumulation_low": self.accumulation_low,
            "manipulation_extreme": self.manipulation_extreme,
            "fvg_top": self.fvg_top,
            "fvg_bottom": self.fvg_bottom,
            "phase": self.phase.value,
        }
