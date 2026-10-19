import AppIntents
import SwiftUI
import WidgetKit

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        if let snap = entry.snapshot {
            switch family {
            case .systemSmall: SmallView(snap: snap)
            case .systemMedium: MediumView(snap: snap, error: entry.error)
            case .systemLarge: LargeView(snap: snap, error: entry.error)
            case .accessoryCircular: CircularView(snap: snap)
            case .accessoryRectangular: RectangularView(snap: snap)
            case .accessoryInline: Text("今日 \(Fmt.usd(snap.todayCost)) · 本月 \(Fmt.usd(snap.monthCost))")
            default: SmallView(snap: snap)
            }
        } else {
            EmptyStateView(message: entry.error ?? "開啟 App 設定 Admin API key")
        }
    }
}

// MARK: - Home screen

private struct Header: View {
    let snap: UsageSnapshot
    var showRefresh = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles").foregroundStyle(.orange)
            Text(snap.isSample ? "範例資料" : "Claude 用量")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if showRefresh {
                Button(intent: RefreshUsageIntent()) {
                    Image(systemName: "arrow.clockwise").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SmallView: View {
    let snap: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Header(snap: snap)
            Text("今日").font(.caption2).foregroundStyle(.secondary)
            Text(Fmt.usd(snap.todayCost))
                .font(.title2.weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            CostBars(days: snap.dailyCosts, tint: snap.budgetColor)
                .frame(maxHeight: .infinity)
            HStack {
                Text("本月 \(Fmt.usd(snap.monthCost))")
                Spacer(minLength: 0)
                if let f = snap.budgetFraction { Text(Fmt.percent(f)).foregroundStyle(snap.budgetColor) }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

private struct MediumView: View {
    let snap: UsageSnapshot
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Header(snap: snap)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日花費").font(.caption2).foregroundStyle(.secondary)
                    Text(Fmt.usd(snap.todayCost))
                        .font(.title.weight(.bold).monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("\(Fmt.tokens(snap.todayTokens.total)) tokens")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("快取命中 \(Fmt.percent(snap.todayTokens.cacheHitRate))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                MonthGauge(snap: snap).frame(width: 74, height: 74)
            }
            CostBars(days: snap.dailyCosts, tint: snap.budgetColor)
                .frame(maxHeight: .infinity)
            Footer(snap: snap, error: error)
        }
    }
}

private struct LargeView: View {
    let snap: UsageSnapshot
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Header(snap: snap)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日花費").font(.caption).foregroundStyle(.secondary)
                    Text(Fmt.usd(snap.todayCost))
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("預估月底 \(Fmt.usd(snap.projectedMonthCost()))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                MonthGauge(snap: snap).frame(width: 90, height: 90)
            }

            TokenGrid(tokens: snap.todayTokens)

            VStack(alignment: .leading, spacing: 4) {
                Text("近 7 日").font(.caption2).foregroundStyle(.secondary)
                CostBars(days: snap.dailyCosts, tint: snap.budgetColor).frame(height: 44)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("本月模型花費").font(.caption2).foregroundStyle(.secondary)
                ForEach(snap.topModels.prefix(3)) { m in
                    HStack {
                        Text(m.model).lineLimit(1)
                        Spacer()
                        Text(Fmt.usd(m.dollars)).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
            Spacer(minLength: 0)
            Footer(snap: snap, error: error)
        }
    }
}

private struct MonthGauge: View {
    let snap: UsageSnapshot

    var body: some View {
        ZStack {
            BudgetRing(fraction: snap.budgetFraction ?? 0, color: snap.budgetColor, lineWidth: 7)
            VStack(spacing: 0) {
                Text("本月").font(.system(size: 9)).foregroundStyle(.secondary)
                Text(Fmt.usd(snap.monthCost))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if let f = snap.budgetFraction {
                    Text(Fmt.percent(f)).font(.system(size: 9).monospacedDigit()).foregroundStyle(snap.budgetColor)
                }
            }
            .padding(8)
        }
    }
}

private struct TokenGrid: View {
    let tokens: TokenTotals

    var body: some View {
        HStack(spacing: 6) {
            cell("輸入", tokens.input)
            cell("快取讀", tokens.cacheRead)
            cell("快取寫", tokens.cacheWrite)
            cell("輸出", tokens.output)
        }
    }

    private func cell(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text(Fmt.tokens(value)).font(.caption.weight(.semibold).monospacedDigit())
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct Footer: View {
    let snap: UsageSnapshot
    let error: String?

    var body: some View {
        HStack(spacing: 4) {
            if let error {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).lineLimit(1)
            } else {
                Text("更新於 \(snap.fetchedAt, style: .time)")
            }
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
    }
}

private struct EmptyStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "key.horizontal").font(.title3).foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Lock screen

private struct CircularView: View {
    let snap: UsageSnapshot

    var body: some View {
        if let f = snap.budgetFraction {
            Gauge(value: min(f, 1)) {
                Text("$")
            } currentValueLabel: {
                Text(Fmt.percent(f)).font(.system(size: 11).monospacedDigit())
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("今日").font(.system(size: 9))
                    Text(Fmt.usd(snap.todayCost))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .minimumScaleFactor(0.5)
                }
            }
        }
    }
}

private struct RectangularView: View {
    let snap: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Claude · 今日 \(Fmt.usd(snap.todayCost))")
                .font(.headline.monospacedDigit())
                .widgetAccentable()
            Text("本月 \(Fmt.usd(snap.monthCost))" + (snap.budgetFraction.map { " (\(Fmt.percent($0)))" } ?? ""))
                .font(.caption.monospacedDigit())
            Text("\(Fmt.tokens(snap.todayTokens.total)) tokens")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Widget

struct AgentUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConfig.widgetKind, provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude 用量監控")
        .description("顯示今日與本月 API 花費、token 用量與預算進度。")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

@main
struct AgentMonitorWidgetBundle: WidgetBundle {
    var body: some Widget {
        AgentUsageWidget()
    }
}

#Preview(as: .systemMedium) {
    AgentUsageWidget()
} timeline: {
    UsageEntry.placeholder
}

#Preview(as: .systemLarge) {
    AgentUsageWidget()
} timeline: {
    UsageEntry.placeholder
}
