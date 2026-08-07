"""CLI: python -m ohlc.cli path/to/ohlcv.csv"""

from __future__ import annotations

import argparse
import sys

import pandas as pd

from .detector import Config, Mode, detect


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Intraday OHLC entry signal detector")
    p.add_argument("csv", help="OHLCV CSV with datetime index or time column")
    p.add_argument("--mode", default="ALL", choices=[m.value for m in Mode])
    p.add_argument("--session-hour", type=int, default=0)
    p.add_argument("--orb-bars", type=int, default=4)
    p.add_argument("-o", "--output", default="")
    args = p.parse_args(argv)

    df = pd.read_csv(args.csv)
    if "time" in df.columns:
        df["time"] = pd.to_datetime(df["time"])
        df = df.set_index("time")
    elif "datetime" in df.columns:
        df["datetime"] = pd.to_datetime(df["datetime"])
        df = df.set_index("datetime")
    else:
        df.index = pd.to_datetime(df.index)

    df.columns = [c.lower() for c in df.columns]
    cfg = Config(mode=Mode(args.mode), session_start_hour=args.session_hour, orb_bars=args.orb_bars)
    signals = detect(df, cfg)
    if args.output:
        signals.to_csv(args.output, index=False)
        print(f"wrote {len(signals)} signals -> {args.output}")
    else:
        print(signals.to_string(index=False) if len(signals) else "(no signals)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
