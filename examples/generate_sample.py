"""Generate a synthetic OHLCV series that contains a clear MMBM pattern."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd


def build_mmbm_sample(n_prefix: int = 40) -> pd.DataFrame:
    rng = np.random.default_rng(7)
    rows: list[dict] = []
    price = 100.0

    # Warm-up / noise
    for i in range(n_prefix):
        open_ = price
        close = price + rng.normal(0, 0.15)
        high = max(open_, close) + abs(rng.normal(0.05, 0.05))
        low = min(open_, close) - abs(rng.normal(0.05, 0.05))
        rows.append(_bar(i, open_, high, low, close))
        price = close

    # Accumulation (tight range around ~100.5)
    base = 100.5
    for i in range(20):
        open_ = base + rng.normal(0, 0.05)
        close = base + rng.normal(0, 0.05)
        high = max(open_, close, base) + 0.12
        low = min(open_, close, base) - 0.12
        rows.append(_bar(n_prefix + i, open_, high, low, close))
        price = close

    idx = n_prefix + 20

    # Manipulation: SSL sweep below accumulation
    open_ = price
    low = 99.6
    high = open_ + 0.1
    close = 99.85
    rows.append(_bar(idx, open_, high, low, close))
    idx += 1
    price = close

    # Expansion displacement through range high with bullish FVG
    # candle A
    open_ = price
    close = 100.2
    high = 100.25
    low = 99.9
    rows.append(_bar(idx, open_, high, low, close))
    idx += 1

    # candle B (impulse)
    open_ = 100.3
    close = 101.4
    high = 101.5
    low = 100.25
    rows.append(_bar(idx, open_, high, low, close))
    idx += 1

    # candle C creates bullish FVG vs candle A and closes above range
    open_ = 101.45
    close = 102.3
    high = 102.4
    low = 101.35  # > candle A high (100.25) => FVG
    rows.append(_bar(idx, open_, high, low, close))
    idx += 1

    # Trailing noise
    price = close
    for i in range(15):
        open_ = price
        close = price + rng.normal(0.05, 0.1)
        high = max(open_, close) + 0.08
        low = min(open_, close) - 0.08
        rows.append(_bar(idx + i, open_, high, low, close))
        price = close

    return pd.DataFrame(rows)


def _bar(i: int, open_: float, high: float, low: float, close: float) -> dict:
    ts = pd.Timestamp("2024-01-01", tz="UTC") + pd.Timedelta(minutes=i)
    return {
        "timestamp": ts.isoformat().replace("+00:00", "Z"),
        "open": round(float(open_), 5),
        "high": round(float(high), 5),
        "low": round(float(low), 5),
        "close": round(float(close), 5),
        "volume": 1000,
    }


def main() -> None:
    out = Path(__file__).with_name("sample_ohlcv.csv")
    df = build_mmbm_sample()
    df.to_csv(out, index=False)
    print(f"Wrote {out} ({len(df)} rows)")


if __name__ == "__main__":
    main()
