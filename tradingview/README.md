# TradingView 安裝

1. 開啟任意圖表 → 下方 **Pine Editor**
2. 新建腳本，貼上 `MMXM_Entry_Detector.pine` 全部內容（`//@version=6`）
3. Save → **Add to chart**

設定面板、右上狀態表皆為**繁體中文**。

## 盈虧怎麼顯示（畫面固定）

移動圖表時請看這兩層：

1. **右上表格（真正畫面固定）**  
   永遠釘在螢幕右上：流動性路徑、DOL、E / R / T1 / T2，捲動也不會跑掉。

2. **橫貫價位線 + 色帶**  
   最新一筆的 E / R / T1 / T2，以及 ERL高/低、IRL均衡、DOL目標。

## ERL ↔ IRL（往哪邊抽）

- **ERL**：Dealing Range 外緣高低（BSL/SSL）
- **IRL**：區間內均衡（EQ）等內部目標
- 典型路徑：掃到 ERL → **ERL→IRL** 回抽 → 再到 **IRL→ERL** 擴張
- 右上會顯示例如：`ERL→IRL 偏多` / `IRL→ERL 偏空`
- 可選「進場需順DOL方向」過濾訊號

## 重要設定

### ICT進場模型
- **ERT交易系統**（預設）：HTF 過濾 + LTF MMXM 第四階段
- **MMXM第四階段**：僅本週期
- 進場參考價：中點CE / 近端 / OTE62
- 確認：觸價 / 收K確認 / 收K進入失衡區

### HTF→LTF
- 高週期時間框（如 `60`）、偏向判定（BOS / 中軸 / EMA）

### ERT
- E 進場、R 停損、T1 部分、T2 最終
- 預設強制 HTF 同向

這是**指標**，不會自動下單。
