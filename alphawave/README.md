# Alpha Wave Institutional

**不推翻 Alpha Wave Pro。** Institutional 是疊在 Pro 之上的風控 / 制度層。

目標不是增加交易，而是：

1. 降低 Drawdown  
2. 降低垃圾 setup  
3. 提高穩定性  

優先順序：**控制最大回撤 → 正 Expectancy → Profit Factor → 穩定性 → 最後才是總獲利**

---

## 架構

```
alphawave/
  Pro/                         ← Alpha Wave Pro（核心 setup，獨立、不被改寫）
    AW_Pro_Defines.mqh
    AW_Pro_Structure.mqh        M15/H1 BOS / CHoCH
    AW_Pro_Liquidity.mqh       Liquidity Sweep
    AW_Pro_Fib.mqh
    AW_Pro_Confirmations.mqh    Engulfing 等
    AW_Pro_Engine.mqh           Pro API（Institutional 只呼叫、不取代）

  Institutional/               ← 制度層
    AW_Inst_Regime.mqh         Market Regime Detector
    AW_Inst_AdaptiveFilter.mqh Adaptive Trade Filter
    AW_Inst_TradeScore.mqh     Advanced Trade Score + Dynamic Min
    AW_Inst_Drawdown.mqh       DD Protection L1/L2/L3
    AW_Inst_Stats.mqh          Performance Statistics
    AW_Inst_SetupDB.mqh        Setup Performance Database
    AW_Inst_AutoDisable.mqh    Auto Disable（預設 false）
    AW_Inst_Safety.mqh         禁止馬丁/網格/加倉回本/ML改參
    AW_Inst_Dashboard.mqh
    AW_Inst_Engine.mqh

  Experts/
    AlphaWave_Institutional.mq5
  Presets/
    Institutional_Conservative.set
```

### 安裝（MT5）

1. 將 `Pro/` 與 `Institutional/` 放到 `MQL5/Include/AlphaWave/`  
2. 將 `Experts/AlphaWave_Institutional.mq5` 放到 `MQL5/Experts/AlphaWave/`  
3. 修改 mq5 內 include 路徑為：

```cpp
#include <AlphaWave/Pro/AW_Pro_Engine.mqh>
#include <AlphaWave/Institutional/AW_Inst_Engine.mqh>
```

（倉庫內相對路徑方便閱讀；編譯時請用 Include 標準路徑。）

---

## 模組對照

| # | 模組 | 行為 |
|---|------|------|
| 1 | Market Regime | TRENDING / RANGING / HIGH VOL / LOW VOL / UNSTABLE（ATR、ADX、M15/H1 結構、Session Range；門檻皆 input） |
| 2 | Adaptive Filter | 依 regime 開關趨勢/盤整類 setup，並調 score 權重（非加碼） |
| 3 | Trade Score | 基礎 100 分路徑 → A+ / A / B / C / NO TRADE |
| 4 | Dynamic Min Score | 正常 75；高波動 85；低流動性 90；低波動/不穩定可直接禁 |
| 5 | Drawdown Protection | 日/週/月 DD → L1 降風險、L2 只 A+、L3 STOPPED |
| 6 | Performance Stats | WR/PF/Exp/AvgR/MaxDD/連勝連敗，並可依 Session/方向/Setup/確認/Score/Regime/星期/小時 |
| 7 | Setup DB | 每種 setup 獨立統計（Fib+Sweep+Engulfing 等），只收集不改策略 |
| 8 | Auto Disable | **預設 false**；樣本≥N 且 PF/Exp 低於門檻才暫停，並記錄原因 |
| 9 | Safety | 禁止 ML 改參、馬丁、網格、Recovery、虧損後加 lot |
| 10 | Dashboard | Regime、Risk Mode、Score、MinScore、DD、Setup Perf、EA Status |

EA Status：`NORMAL` / `REDUCED RISK` / `A+ ONLY` / `STOPPED`

---

## Pro setups（保留）

- Fib + Sweep + Engulfing  
- Fib + Sweep + BOS  
- Fib + CHoCH  
- Sweep + BOS  
- Sweep + Engulfing  
- Fib + Engulfing  

---

## 偏差 / 安全檢查（已處理）

| 風險 | 處理 |
|------|------|
| Look-ahead bias | 訊號只用 **已收盤 K**（shift≥1）；ATR/ADX CopyBuffer 自 shift 1 |
| Future data leakage | 結構樞紐要求右側 K 已收盤；Session range 不含未收盤 |
| Duplicate trades | 每根收盤 K 只評估一次；同 magic 禁加倉/網格 |
| Incorrect lot | `Safety.CalcLot` 依 SL 距離與 tick value 算固定風險%，DD 只允許 **降** 風險 |
| Session timezone bug | 用 `TimeGMT + InpGmtOffsetHours`（預設 +8 台北），分鐘區間含隔夜美盤 |
| Daily reset bug | DD 日/週/月 key 依同一 TZ 日曆重算，非整點 server 隨便切 |
| Overfitting | 門檻全為 input；AutoDisable 預設關；不自動改策略參數 |
| Martingale/Grid | 編譯期政策禁止 + 同圖只允許一筆部位 |

---

## 不是目標的事

- 不是最多交易  
- 不是最高勝率  
- 不是最高回測淨利  

**請先在模擬盤驗證 DD 閘道與 Score 門檻，再考慮實盤。**
