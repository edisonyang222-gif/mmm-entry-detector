# TradingView 安裝

1. 開啟任意圖表 → 下方 **Pine Editor**
2. 新建腳本，貼上 `MMXM_Entry_Detector.pine` 全部內容（`//@version=6`）
3. Save → **Add to chart**
4. 需要推播時：右鍵圖表 → Add alert → 選 `MMBM Entry` / `MMSM Entry`

## 圖上會看到什麼

- **紅色 RISK 方塊**：進場到止損（虧損區）
- **綠色 REWARD 方塊**：進場到止盈（獲利區）
- **ENTRY / SL / TP 線**與價格標籤
- **FVG 藍框**、**ACC 紫框**（結構上下文）
- 右上角狀態表：目前買賣模型階段、ATR、區間是否收斂

## 時區說明

偵測只依 K 線 OHLC，**不依交易所時區 / session**，所以 UTC、台北、紐約等圖表都能用。  
換時區只會改變時間軸顯示，不會改變訊號邏輯。

這是**指標**，不會自動下單。
