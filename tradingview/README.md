# TradingView 指標檔

Pine Script：**`//@version=6`**

## 推薦（對應 MT5 多時框結構）

**[`OHLC_MTF_Structure.pine`](OHLC_MTF_Structure.pine)**

功能：
- 中文多時框面版（高/中/低週期偏向 + 大概率走向）
- 流動性掃除標記
- 有效支撐 **S** / 有效阻力 **R**
- **流動性池數量**：擺盪高/低形成時標上量能近似值（`R↑ 12.5K` / `S↓ 8.2K`）
  - **未被獵取**：數字保留
  - **一旦影線掃除/獵取**：數字取消（標籤刪除）
- 進場訊號與警報

### 安裝

1. 打開 [TradingView](https://www.tradingview.com/) → Pine Editor
2. 新增空白策略/指標，貼上 `OHLC_MTF_Structure.pine` 或 `Intraday_OHLC_Entry.pine`
3. 儲存 → **加到圖表**
4. 建議周期：M5 / M15；高週期預設 60、中週期 15（可在設定改）

### 價格線 / 日分隔（04:45）

- 每天 **04:45**（可調）畫**黃色虛線垂直分隔**
- PDH / PDL / Mid / Day Open / ORB 用**連續水平價格線**（非中斷線），從當日 04:45 畫到當日結束
- 預設交易日開始：`時=4`、`分=45`

## 基礎版（日內 OHLC）

[`Intraday_OHLC_Entry.pine`](Intraday_OHLC_Entry.pine) — PDH/PDL/開盤/ORB 突破與拒絕。
