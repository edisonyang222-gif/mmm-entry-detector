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
        close = price + rng.normal(0, 0.08)
        high = max(open_, close) + 0.05
        low = min(open_, close) - 0.05
        rows.append(_bar(i, open_, high, low, close))
        price = close

    # Accumulation (tight range around ~100.5)
    base = 100.5
    for i in range(20):
        open_ = base + rng.normal(0, 0.03)
        close = base + rng.normal(0, 0.03)
        high = max(open_, close, base) + 0.10
        low = min(open_, close, base) - 0.10
        rows.append(_bar(n_prefix + i, open_, high, low, close))
        price = close

    idx = n_prefix + 20

    # Manipulation: SSL sweep below accumulation
    open_ = price
    low = 99.55
    high = open_ + 0.08
    close = 99.80
    rows.append(_bar(idx, open_, high, low, close))
    idx += 1
    price = close

    # Expansion displacement through range high with bullish FVG
    # candle A
    open_ = price
    close = 100.15
    high = 100.20
    low = 99.85
    rows.append(_bar(idx, open_, high, low, close))
    idx += 1

    # candle B (impulse)
    open_ = 100.25
    close = 101.35
    high = 101.45
    low = 100.20
    rows.append(_bar(idx, open_, high, low, close))
    idx += 1

    # candle C creates bullish FVG vs candle A and closes above range
    # FVG: bottom=high[A]=100.20, top=low[C]=101.30, CE≈100.75
    open_ = 101.40
    close = 102.20
    high = 102.30
    low = 101.30
    rows.append(_bar(idx, open_, high, low, close))
    idx += 1

    # Continue slightly higher (no entry yet — waiting for Phase-4 retrace)
    rows.append(_bar(idx, 102.20, 102.50, 102.00, 102.35))
    idx += 1
    rows.append(_bar(idx, 102.35, 102.60, 102.10, 102.20))
    idx += 1

    # Phase-4 retrace: wick into FVG / CE then close back up
    rows.append(_bar(idx, 102.10, 102.20, 100.70, 101.10))
    idx += 1

    # Trailing noise
    price = 101.10
    for i in range(12):
        open_ = price
        close = price + rng.normal(0.05, 0.08)
        high = max(open_, close) + 0.06
        low = min(open_, close) - 0.06
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
