# mmm-entry-detector

日內 **OHLC / 多時框結構進場** 指標與 EA（MT5），含中文面版、流動性掃除、有效支撐阻力回踩、收K後不消失的訊號。

## 你要的能力對應

| 需求 | 實作 |
|------|------|
| 精準入場型態 | 偏向對齊 → 流動性掃除 → 回踩有效S/R → 收K確認 |
| 回踩進場 | `回踩有效支撐` / `回踩有效阻力` |
| 有效支撐/阻力 | 未失效擺盪點 + 掃除後水位 |
| 收K後訊號不消失 | 僅評估已收盤K；緩衝與物件以K時間為鍵確定性重算 |
| 中文直觀面版 | 多時框偏向、流動性、S/R、預判、設置狀態 |
| 多時框一目了然 | HTF / MTF / LTF + 綜合「大概率走向」 |
| 掃除流動性 | 影線刺破擺盪極值後收盤收回 |
| 指標 + EA | `OHLC_MTF_Structure` + `OHLC_MTF_Structure_EA` |

## MT5 安裝

見 [`mt5/README.md`](mt5/README.md)。**請優先使用多時框結構指標/EA。**

## Python 驗證

```bash
pip install -e ".[dev]"
pytest -q
```

## TradingView

基礎 OHLC 見 `tradingview/Intraday_OHLC_Entry.pine`（結構面版以 MT5 為主）。
