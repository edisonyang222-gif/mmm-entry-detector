# MetaTrader 5 — 日內 OHLC / 多時框結構進場

## 檔案對應

```
mt5/Include/OHLC/IntradayOHLCLogic.mqh   →  MQL5/Include/OHLC/
mt5/Include/OHLC/StructureLogic.mqh      →  MQL5/Include/OHLC/
mt5/Indicators/Intraday_OHLC_Entry.mq5   →  MQL5/Indicators/   （基礎日線OHLC）
mt5/Indicators/OHLC_MTF_Structure.mq5    →  MQL5/Indicators/   （★推薦：多時框面版）
mt5/Experts/Intraday_OHLC_EA.mq5         →  MQL5/Experts/
mt5/Experts/OHLC_MTF_Structure_EA.mq5    →  MQL5/Experts/      （★推薦）
```

MT5：`File → Open Data Folder`。先放 `.mqh` 再編譯。

## 推薦：多時框結構系統

| 元件 | 作用 |
|------|------|
| **指標** `OHLC_MTF_Structure` | 中文面版 + 流動性掃除標記 + 回踩進場箭頭 |
| **EA** `OHLC_MTF_Structure_EA` | 同一邏輯，收K確認後市價進場 |

### 面版一眼看懂

- 高/中/低週期偏向（偏多▲ / 偏空▼ / 盤整）
- **綜合偏向預判**：大概率向上 / 向下 / 觀望
- 流動性是否已掃除（上方/下方）
- 有效支撐 / 有效阻力價位與來源
- 設置狀態（回踩監控中 / 等待掃除）
- 最近進場訊號與 SL/TP/RR

### 精準進場型態

1. 多時框偏向對齊（可關）
2. **掃除流動性**（刺破擺盪高/低後收回收盤）
3. 等待 **回踩有效支撐/阻力**
4. 收K實體確認 → 進場  
   → 只在**已收盤K**評分，歷史箭頭與物件以時間為鍵，**收K後不消失、不重繪**

### 建議周期

圖表 M5/M15；高週期 H1；中週期 M15；依商品調整。
