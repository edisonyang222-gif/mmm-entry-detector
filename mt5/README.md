# MetaTrader 5 安裝

## 檔案對應

```
mt5/Include/MMXM/MMXMLogic.mqh      →  <Data Folder>/MQL5/Include/MMXM/MMXMLogic.mqh
mt5/Indicators/MMXM_Entry_Detector.mq5 →  <Data Folder>/MQL5/Indicators/MMXM_Entry_Detector.mq5
mt5/Experts/MMXM_Entry_EA.mq5      →  <Data Folder>/MQL5/Experts/MMXM_Entry_EA.mq5
```

在 MT5：`File → Open Data Folder` 可找到 Data Folder。

## 指標 vs EA

- **指標** `MMXM_Entry_Detector`：只畫訊號，不下單
- **EA** `MMXM_Entry_EA`：偵測到訊號後可掛單 / 市價單

兩者共用同一套 `MMXMLogic.mqh` 邏輯。
