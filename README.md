# Gold MMM Entry Detector

黃金專用進場指標：**Multi-filter Momentum Method（多濾網動能法）**。  
把進場條件收成可執行、可回測的規則，用風險報酬比去抓趨勢段，而不是賭每一根 K 線。

> 沒有指標能保證賺錢。以下數字是歷史回測，不是未來獲利保證。

## 建議用法（先看這段）

| 項目 | 建議 |
|------|------|
| 商品 | XAUUSD / GOLD / GC |
| 週期 | **H4 或 D1**（H1 雜訊太多，預設參數在 H1 會虧） |
| 方向 | 大多頭年可切 `Long only` |
| 單筆風險 | ≤ 帳戶 1% |
| 事件 | 非農 / FOMC / CPI 前後空手或減碼 |

Python 回測（GC=F，調參後預設）：

| 資料 | 交易數 | 勝率 | 盈虧比 PF | 報酬 | 最大回撤 |
|------|--------|------|-----------|------|----------|
| H4 約 2 年 | 55 | 45% | 1.58 | +16.9% | 4.9% |
| D1 約 5 年 | 22 | 50% | 1.87 | +10.1% | 4.9% |
| H4 前半 / 後半 | 29 / 26 | 48% / 42% | 1.64 / 1.52 | +8.8% / +7.5% | ~5% |

## 邏輯（四層濾網）

1. **趨勢**：EMA20 > EMA50 且收盤 > EMA100 → 只做多（空頭反向）  
2. **回檔**：價格回踩 EMA20 後收復 → 不追高  
3. **RSI 甜蜜區**：多 35–55；空 45–65  
4. **ATR 波動**：ATR 相對均線在 0.6×～3.0×，太死或爆衝不做  

**出場**：SL = 2 ATR；TP1 = 3 ATR（平半倉、停損移成本）；TP2 = 5 ATR；趨勢翻轉清倉。

## 檔案

```
indicators/gold_mmm_entry_detector.pine   # TradingView 指標（訊號 + Alert）
indicators/gold_mmm_strategy.pine         # TradingView 策略（Strategy Tester）
backtest/gold_mmm_backtest.py             # Python 回測
requirements.txt
```

## TradingView

1. 打開 Pine Editor，貼上 `gold_mmm_entry_detector.pine` → Add to chart  
2. 選 **XAUUSD**，週期 **240（H4）** 或 **1D**  
3. 出現 LONG / SHORT 三角與 SL/TP 標籤；右上角儀表板顯示 Bias / RSI / R:R  
4. 建立 Alert：`Gold MMM Long` / `Gold MMM Short`  
5. 策略回測改用 `gold_mmm_strategy.pine`

## Python 回測

```bash
pip install -r requirements.txt

# 黃金期貨 H1（可自行 resample；建議用 H4 CSV）
python3 backtest/gold_mmm_backtest.py --symbol GC=F --interval 1h --period 2y

# 只做多
python3 backtest/gold_mmm_backtest.py --symbol GC=F --interval 1d --period 5y --long-only

# 自備 CSV：datetime,open,high,low,close
python3 backtest/gold_mmm_backtest.py --csv your_xauusd_h4.csv

# 離線煙霧測試
python3 backtest/gold_mmm_backtest.py --synthetic
```

成交明細：`backtest/output/trades.csv`

## 實盤檢查清單

- [ ] 週期是 H4 或 D1  
- [ ] Bias 與訊號同向（儀表板 BULL 才做 LONG）  
- [ ] 算好 SL 口數，風險 ≤ 1%  
- [ ] 設好 TP1 / TP2，不要盤中改規則  
- [ ] 重大數據前不加倉  

這是技術工具，不是投資建議。
