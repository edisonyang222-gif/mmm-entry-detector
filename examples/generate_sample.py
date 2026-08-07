"""Generate a small synthetic OHLCV sample for CLI demos."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd


def main() -> None:
    rng = np.random.default_rng(42)
    idx = pd.date_range("2024-06-01", periods=5 * 24, freq="h")
    # random walk with mild drift
    ret = rng.normal(0.02, 0.8, size=len(idx))
    close = 2000 + np.cumsum(ret)
    open_ = np.roll(close, 1)
    open_[0] = close[0]
    high = np.maximum(open_, close) + rng.uniform(0.2, 1.5, size=len(idx))
    low = np.minimum(open_, close) - rng.uniform(0.2, 1.5, size=len(idx))
    # inject a clear PDH break on day 3
    day3 = idx[48:72]
    pdh = high[24:48].max()
    high[60] = pdh + 5
    close[60] = pdh + 4
    open_[60] = pdh + 1

    df = pd.DataFrame(
        {
            "time": idx,
            "open": open_,
            "high": high,
            "low": low,
            "close": close,
            "volume": rng.integers(100, 1000, size=len(idx)),
        }
    )
    out = Path(__file__).with_name("sample_ohlcv.csv")
    df.to_csv(out, index=False)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
