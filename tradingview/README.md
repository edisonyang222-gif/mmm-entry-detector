# TradingView 指標檔

Pine Script：**`//@version=6`**

## 推薦（對應 MT5 多時框結構）

**[`OHLC_MTF_Structure.pine`](OHLC_MTF_Structure.pine)**

功能：
- 中文多時框面版（高/中/低週期偏向 + 大概率走向）
- 流動性掃除標記
- 有效支撐 / 有效阻力
- 回踩進場訊號（僅收K確認，不重繪）
- 進場 / SL / TP 標示與警報

### 安裝

1. 打開 [TradingView](https://www.tradingview.com/) → Pine Editor
2. 新增空白策略/指標，貼上 `OHLC_MTF_Structure.pine` 全部內容
3. 儲存 → **加到圖表**
4. 建議周期：M5 / M15；高週期預設 60、中週期 15（可在設定改）

## 基礎版（日內 OHLC）

[`Intraday_OHLC_Entry.pine`](Intraday_OHLC_Entry.pine) — PDH/PDL/開盤/ORB 突破與拒絕。
