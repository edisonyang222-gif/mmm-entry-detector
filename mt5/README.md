# MetaTrader 5 — 日內 OHLC 進場訊號

## 檔案對應

```
mt5/Include/OHLC/IntradayOHLCLogic.mqh  →  <Data Folder>/MQL5/Include/OHLC/IntradayOHLCLogic.mqh
mt5/Indicators/Intraday_OHLC_Entry.mq5  →  <Data Folder>/MQL5/Indicators/Intraday_OHLC_Entry.mq5
mt5/Experts/Intraday_OHLC_EA.mq5        →  <Data Folder>/MQL5/Experts/Intraday_OHLC_EA.mq5
```

在 MT5：`File → Open Data Folder` 可找到 Data Folder。編譯指標與 EA 前請先放好 `.mqh`。

## 指標 vs EA

| 元件 | 作用 |
|------|------|
| **指標** `Intraday_OHLC_Entry` | 畫 PDH/PDL/日開盤/ORB 與進場箭頭，不下單 |
| **EA** `Intraday_OHLC_EA` | 同一套邏輯，收線後可市價或 Stop 掛單 |

兩者共用 `IntradayOHLCLogic.mqh`。

## 訊號邏輯（日內 OHLC）

以**前一日 OHLC**與**今日開盤 / Opening Range**為關鍵價：

| 類型 | 方向 | 條件 |
|------|------|------|
| `PDH_BO` | Buy | 收盤向上突破前高 |
| `PDL_BO` | Sell | 收盤向下突破前低 |
| `OPEN_BUY` / `OPEN_SELL` | Buy/Sell | 收盤穿越當日開盤價 |
| `PDH_REJ` | Sell | 觸及前高後收在下方（拒絕） |
| `PDL_REJ` | Buy | 觸及前低後收在上方（拒絕） |
| `ORB_BUY` / `ORB_SELL` | Buy/Sell | 突破開盤區間高低 |

### 模式 (`InpMode`)

- `BREAKOUT` — 前高/前低突破 + ORB
- `REJECTION` — 僅拒絕訊號
- `OPEN` — 僅日開盤穿越
- `ALL` — 全部（預設，依優先順序取第一個）

### 風控

- SL：`InpStopAtrMult × ATR`
- TP：優先下一個 OHLC 結構位（中軸 / 對側日線），否則 `InpTpRR × 風險`
- 可設每日每邊一筆、交易時段過濾、收盤前平倉

### 建議周期

M5 / M15 / M30（日內）。`InpSessionStartHour` 對齊券商伺服器日切換（外匯常見 0 或 22–24 視伺服器時區）。
