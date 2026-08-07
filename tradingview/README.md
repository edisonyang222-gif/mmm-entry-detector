# TradingView 安裝

1. 開啟任意圖表 → 下方 **Pine Editor**
2. 新建腳本，貼上 `MMXM_Entry_Detector.pine` 全部內容（`//@version=6`）
3. Save → **Add to chart**
4. 需要推播時：右鍵圖表 → Add alert → 選 `MMBM Entry` / `MMSM Entry`

## 圖上會看到什麼

- 黃框 **WAIT**：已形成 FVG，等待回踩（尚未進場）
- 訊號當下才出現：紅色 RISK / 綠色 REWARD 方塊、ENTRY/SL/TP 線
- 藍框 FVG、紫框 ACC
- 右上角狀態表

## 偵測邏輯（較嚴謹）

1. 累積區間先站穩（預設至少 5 根）
2. 掃蕩流動性（SSL/BSL）
3. 強勢位移 + 收破區間 + 留下 FVG
4. **等價格回踩 FVG / CE 才出進場訊號**（真正 Phase-4）

## 時區

只依 K 線 OHLC，不綁 session／時區。

這是**指標**，不會自動下單。
