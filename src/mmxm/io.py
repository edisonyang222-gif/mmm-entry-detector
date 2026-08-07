from __future__ import annotations

from pathlib import Path

import pandas as pd


def load_ohlcv_csv(path: str | Path) -> pd.DataFrame:
    """Load OHLCV CSV with flexible column naming."""
    frame = pd.read_csv(path)
    frame.columns = [str(c).strip().lower() for c in frame.columns]

    aliases = {
        "o": "open",
        "h": "high",
        "l": "low",
        "c": "close",
        "time": "timestamp",
        "datetime": "timestamp",
        "date": "timestamp",
        "ts": "timestamp",
    }
    frame.rename(columns={k: v for k, v in aliases.items() if k in frame.columns}, inplace=True)

    required = {"open", "high", "low", "close"}
    missing = required - set(frame.columns)
    if missing:
        raise ValueError(f"CSV missing columns: {sorted(missing)}")

    return frame
