# MMXM Entry Detector

ICT **Market Maker Model (MMXM)** 進場偵測：累積 → 掃蕩 → 擴張 → FVG 進場。

這個 repo 同時提供 **三種用法**：

| 類型 | 檔案 | 會不會自動下單 | 用在哪 |
|------|------|----------------|--------|
| TradingView **指標** | `tradingview/MMXM_Entry_Detector.pine` | 否，只畫訊號 | TradingView 圖表 |
| MT5 **指標** | `mt5/Indicators/MMXM_Entry_Detector.mq5` | 否，只畫箭頭 | MetaTrader 5 圖表 |
| MT5 **EA** | `mt5/Experts/MMXM_Entry_EA.mq5` | 可以自動下單 | MetaTrader 5 |

另外還有 Python CLI（離線分析 CSV），在 `src/mmxm/`。

## 1) TradingView 指標

1. 打開 [TradingView Pine Editor](https://www.tradingview.com/)
2. 貼上 `tradingview/MMXM_Entry_Detector.pine` 內容
3. 按 **Add to chart**
4. 圖上會出現 MMBM / MMSM 三角訊號；可設 Alert

## 2) MT5 指標（不下單）

1. 複製：
   - `mt5/Include/MMXM/MMXMLogic.mqh` → `MQL5/Include/MMXM/`
   - `mt5/Indicators/MMXM_Entry_Detector.mq5` → `MQL5/Indicators/`
2. 在 MetaEditor 編譯 `.mq5`
3. 在圖表插入指標 **MMXM_Entry_Detector**
4. 只顯示買賣箭頭與 Entry/SL/TP 線，**不會下單**

## 3) MT5 EA（可自動交易）

1. 同樣先放好 `MMXMLogic.mqh`
2. 複製 `mt5/Experts/MMXM_Entry_EA.mq5` → `MQL5/Experts/`
3. 編譯後拖到圖表
4. 開啟 Algo Trading
5. 重要參數：
   - `InpLots` 手數
   - `InpUseLimitEntry=true`：用 FVG 限價單；`false`：市價進場
   - `InpOneTradeAtATime`：同時只掛一筆
   - `InpAllowBuy` / `InpAllowSell`

> EA 會真實下單，請先用模擬帳戶測試。

## Phase logic（共通）

1. **Accumulation** — 區間相對 ATR 夠窄，並站穩一段時間  
2. **Manipulation** — SSL（買）/ BSL（賣）掃蕩  
3. **Expansion** — 強勢位移並收破累積區間，留下 FVG  
4. **Wait → Entry** — 等價格回踩 FVG / CE（Phase-4）才出訊號；停損在掃蕩極端外，目標用 measured move  

## Python（可選）

```bash
python -m pip install -e ".[dev]"
python examples/generate_sample.py
mmxm examples/sample_ohlcv.csv
pytest -q
```

## Notes

- 研究 / 輔助工具，非投資建議。
- 不同商品、週期請自行調整 lookback / ATR / min RR。
