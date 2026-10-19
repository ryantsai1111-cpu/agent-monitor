import SwiftUI

struct DashboardView: View {
    @StateObject private var model = DashboardModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                if !model.hasKey {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("尚未設定 Admin API key", systemImage: "key.horizontal")
                                .font(.headline)
                            Text("到 Claude Console → Settings → Admin keys 建立 sk-ant-admin 開頭的金鑰，再貼到設定頁。以下為範例資料。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("前往設定") { showSettings = true }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let error = model.error, model.hasKey {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                let snap = model.snapshot ?? (model.hasKey ? nil : .sample())
                if let snap {
                    overview(snap)
                    tokens(snap)
                    models(snap)
                    Section {
                        Text("更新於 \(snap.fetchedAt.formatted(date: .abbreviated, time: .shortened))（以 UTC 日界計算）")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if model.isLoading {
                    Section { ProgressView().frame(maxWidth: .infinity) }
                }
            }
            .navigationTitle("Claude 用量")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .sheet(isPresented: $showSettings) {
                SettingsView(model: model)
            }
        }
    }

    @ViewBuilder
    private func overview(_ snap: UsageSnapshot) -> some View {
        Section("花費") {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日").font(.caption).foregroundStyle(.secondary)
                    Text(Fmt.usd(snap.todayCost)).font(.largeTitle.bold().monospacedDigit())
                    Text("本月 \(Fmt.usd(snap.monthCost))").monospacedDigit()
                    Text("預估月底 \(Fmt.usd(snap.projectedMonthCost()))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let f = snap.budgetFraction, let budget = snap.monthlyBudget {
                    ZStack {
                        BudgetRing(fraction: f, color: snap.budgetColor, lineWidth: 10)
                        VStack(spacing: 0) {
                            Text(Fmt.percent(f)).font(.headline.monospacedDigit())
                            Text("of \(Fmt.usd(budget))").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 96, height: 96)
                }
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("近 7 日").font(.caption).foregroundStyle(.secondary)
                CostBars(days: snap.dailyCosts, tint: snap.budgetColor).frame(height: 80)
                HStack {
                    ForEach(snap.dailyCosts) { d in
                        Text(d.day.formatted(.dateTime.weekday(.narrow)))
                            .frame(maxWidth: .infinity)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func tokens(_ snap: UsageSnapshot) -> some View {
        Section("今日 Tokens") {
            row("輸入（未快取）", Fmt.tokens(snap.todayTokens.input))
            row("快取讀取", Fmt.tokens(snap.todayTokens.cacheRead))
            row("快取寫入", Fmt.tokens(snap.todayTokens.cacheWrite))
            row("輸出", Fmt.tokens(snap.todayTokens.output))
            row("快取命中率", Fmt.percent(snap.todayTokens.cacheHitRate))
        }
    }

    @ViewBuilder
    private func models(_ snap: UsageSnapshot) -> some View {
        if !snap.topModels.isEmpty {
            Section("本月各模型花費") {
                ForEach(snap.topModels) { m in row(m.model, Fmt.usd(m.dollars)) }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var budgetText = SharedStore.monthlyBudget.map { String(format: "%.0f", $0) } ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(model.hasKey ? "已設定（輸入新值以取代）" : "sk-ant-admin01-…", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Anthropic Admin API key")
                } footer: {
                    Text("金鑰只存在本機 Keychain，並透過 App Group 分享給小工具。需要組織的 Admin key；一般 API key 無法讀取用量報表。")
                }

                Section {
                    TextField("例如 500", text: $budgetText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("每月預算（USD，可留空）")
                } footer: {
                    Text("用來顯示預算進度環：75% 以下綠色、100% 以下橘色、超過為紅色。")
                }

                if model.hasKey {
                    Section {
                        Button("移除金鑰", role: .destructive) {
                            model.signOut()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        let budget = Double(budgetText.replacingOccurrences(of: ",", with: ""))
                        Task { await model.save(key: key, budget: budget) }
                        dismiss()
                    }
                    .disabled(!model.hasKey && key.isEmpty)
                }
            }
        }
    }
}

#Preview {
    DashboardView()
}
