from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .detector import MMXMConfig, MMXMDetector, signals_to_frame
from .io import load_ohlcv_csv


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mmxm",
        description="Detect ICT Market Maker Model (MMXM) entry signals from OHLCV CSV.",
    )
    parser.add_argument("csv", type=Path, help="Path to OHLCV CSV file")
    parser.add_argument(
        "--lookback",
        type=int,
        default=20,
        help="Accumulation lookback bars (default: 20)",
    )
    parser.add_argument(
        "--atr-period",
        type=int,
        default=14,
        help="ATR period (default: 14)",
    )
    parser.add_argument(
        "--min-rr",
        type=float,
        default=1.5,
        help="Minimum risk/reward to emit a signal (default: 1.5)",
    )
    parser.add_argument(
        "--entry-fill",
        choices=("midpoint", "proximal", "distal"),
        default="midpoint",
        help="FVG fill level used as entry (default: midpoint)",
    )
    parser.add_argument(
        "--format",
        choices=("table", "json", "csv"),
        default="table",
        help="Output format (default: table)",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Optional output file path",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        df = load_ohlcv_csv(args.csv)
    except Exception as exc:  # noqa: BLE001 - surface CLI errors cleanly
        print(f"error: failed to load CSV: {exc}", file=sys.stderr)
        return 1

    config = MMXMConfig(
        accumulation_lookback=args.lookback,
        atr_period=args.atr_period,
        min_risk_reward=args.min_rr,
        entry_fill=args.entry_fill,
    )
    signals = MMXMDetector(config).scan(df)
    frame = signals_to_frame(signals)

    if args.format == "json":
        payload = json.dumps(frame.to_dict(orient="records"), indent=2)
    elif args.format == "csv":
        payload = frame.to_csv(index=False)
    else:
        if frame.empty:
            payload = "No MMXM entry signals found."
        else:
            payload = frame.to_string(index=False)

    if args.output:
        args.output.write_text(payload if payload.endswith("\n") else payload + "\n")
        print(f"Wrote {len(signals)} signal(s) to {args.output}")
    else:
        print(payload)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
