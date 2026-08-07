# MMXM Entry Detector

ICT **Market Maker Model (MMXM)** entry detector for OHLCV data.

Detects Market Maker Buy Model (`MMBM`) and Market Maker Sell Model (`MMSM`) phases, then emits Phase-4 style entries at the displacement Fair Value Gap (FVG).

## Phase logic

1. **Accumulation** — rolling range stays tight vs ATR
2. **Manipulation** — SSL sweep (buy) or BSL sweep (sell) beyond the range
3. **Expansion** — displacement candle closes through the accumulation range
4. **Entry** — FVG on the displacement leg; stop beyond sweep extreme; target opposing liquidity

## Install

```bash
python -m pip install -e ".[dev]"
```

## Usage

```bash
# regenerate sample CSV
python examples/generate_sample.py

# scan for signals
mmxm examples/sample_ohlcv.csv

# JSON / CSV output
mmxm examples/sample_ohlcv.csv --format json
mmxm examples/sample_ohlcv.csv --format csv -o signals.csv
```

CSV columns required: `open`, `high`, `low`, `close`  
Optional: `timestamp` / `datetime` / `date`, `volume`

## Python API

```python
import pandas as pd
from mmxm import MMXMDetector, MMXMConfig

df = pd.read_csv("examples/sample_ohlcv.csv")
signals = MMXMDetector(MMXMConfig(min_risk_reward=1.5)).scan(df)

for s in signals:
    print(s.side, s.entry, s.stop_loss, s.take_profit, s.risk_reward)
```

## Tests

```bash
pytest -q
```

## Notes

- This is a research / charting helper, not financial advice.
- Tune `--lookback`, ATR, and `--min-rr` per market and timeframe.
