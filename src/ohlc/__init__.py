"""Intraday OHLC entry detector package."""

from .detector import Config, Mode, Side, SignalType, detect

__all__ = ["Config", "Mode", "Side", "SignalType", "detect"]
