# mmm-entry-detector

日內 **OHLC 進場訊號**指標與 Expert Advisor（MT5），以及對應的 Python / TradingView 實作。

## 快速開始（MT5）

見 [`mt5/README.md`](mt5/README.md)。

1. 複製 `Include/OHLC/`、`Indicators/`、`Experts/` 到 MT5 Data Folder
2. MetaEditor 編譯 `Intraday_OHLC_Entry` 與 `Intraday_OHLC_EA`
3. 圖表掛上指標看訊號；要自動下單再掛 EA

## 訊號摘要

以前一日 High/Low/Close、當日 Open、Opening Range 為參考：

- **突破**：PDH / PDL / ORB
- **開盤穿越**：Day Open cross
- **拒絕**：PDH/PDL wick rejection

## Python（邏輯驗證）

```bash
pip install -e ".[dev]"
pytest -q
python -m ohlc.cli examples/sample_ohlcv.csv
```

## TradingView

見 [`tradingview/Intraday_OHLC_Entry.pine`](tradingview/Intraday_OHLC_Entry.pine)。
