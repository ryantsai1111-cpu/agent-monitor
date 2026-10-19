# agent-monitor

iOS 主畫面／鎖定畫面小工具（WidgetKit），監控 Anthropic Claude API 組織的**花費與 token 用量**。資料來自官方 [Usage & Cost Admin API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api)。

## 功能

| 尺寸 | 內容 |
| --- | --- |
| 小 (systemSmall) | 今日花費、近 7 日長條圖、本月花費與預算 % |
| 中 (systemMedium) | 今日花費、今日 tokens、快取命中率、本月預算環、7 日長條圖 |
| 大 (systemLarge) | 以上全部 + 預估月底花費、token 分類（輸入／快取讀／快取寫／輸出）、本月前 3 名模型花費 |
| 鎖定畫面 圓形 | 預算使用率量表（沒設預算時顯示今日花費） |
| 鎖定畫面 矩形 / 行內 | 今日、本月花費與 tokens |

- 每 15 分鐘自動更新，小工具右上角 ↻ 可手動更新（iOS 17 互動式小工具）。
- 預算環顏色：<75% 綠、<100% 橘、≥100% 紅。
- 網路失敗時保留上一次的資料並在底部顯示錯誤。
- 未設定金鑰時 App 會顯示範例資料。

## 專案結構

```
project.yml                 XcodeGen 專案定義（App + Widget Extension）
Shared/                     兩個 target 共用
  UsageModels.swift         API 回應型別、UsageSnapshot
  AnthropicUsageClient.swift  呼叫 usage_report / cost_report（含分頁）
  SharedStore.swift         App Group 設定快取、Keychain 金鑰
  Formatting.swift          數字格式、長條圖、預算環元件
AgentMonitor/               主 App：儀表板 + 設定頁
AgentMonitorWidget/         WidgetKit 擴充：TimelineProvider、各尺寸畫面
```

## 建置

需求：macOS + Xcode 15 以上、iOS 17 以上裝置／模擬器。

```bash
brew install xcodegen
xcodegen generate
open AgentMonitor.xcodeproj
```

1. 在 `project.yml` 填入 `DEVELOPMENT_TEAM`（或在 Xcode 的 Signing & Capabilities 設定）。
2. 如果 `com.ryantsai.*` bundle id 或 `group.com.ryantsai.agentmonitor` App Group 不能在你的帳號下使用，請一併修改 `project.yml` 與 `Shared/SharedStore.swift` 的 `AppConfig.appGroup`，兩邊要一致。
3. 執行 `AgentMonitor` scheme 安裝到手機，開啟 App → 右上角齒輪 → 貼上 Admin API key、輸入每月預算。
4. 長按主畫面 → 加入小工具 → 搜尋「Agent Monitor」。

## 取得 Admin API key

Claude Console → **Settings → Admin keys** 建立 `sk-ant-admin01-…` 開頭的金鑰（需組織管理員權限；個人帳號沒有 Admin API）。一般 `sk-ant-api…` 金鑰無法讀取用量報表。

金鑰存在 iOS Keychain（`AfterFirstUnlockThisDeviceOnly`，以 App Group 作為存取群組讓小工具讀取），不會離開裝置，只會送到 `api.anthropic.com`。

## 資料計算方式

- **花費**：`GET /v1/organizations/cost_report`，`group_by[]=description`，金額為美分字串，換算成美元。本月 = 當月 1 日（UTC）至今。
- **Tokens**：`GET /v1/organizations/usage_report/messages`，`bucket_width=1d`，取今日（UTC）bucket。
- **快取命中率** = 快取讀取 ÷（未快取輸入 + 快取讀取 + 快取寫入）。
- **預估月底** = 本月花費 ÷ 已過天數 × 當月天數（線性推估）。
- 日界以 **UTC** 計算，與 Console 報表一致；台灣時間每天早上 8 點換日。
- 用量資料通常延遲約 5 分鐘；Priority Tier 花費不在 cost 端點內。
