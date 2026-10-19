import Foundation
import SwiftUI

enum Fmt {
    static func usd(_ value: Double) -> String {
        if value >= 1000 { return String(format: "$%.0f", value) }
        if value >= 100 { return String(format: "$%.1f", value) }
        return String(format: "$%.2f", value)
    }

    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        switch d {
        case 1_000_000_000...: return String(format: "%.1fB", d / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", d / 1_000_000)
        case 1_000...: return String(format: "%.1fK", d / 1_000)
        default: return "\(n)"
        }
    }

    static func percent(_ f: Double) -> String { String(format: "%.0f%%", f * 100) }
}

extension UsageSnapshot {
    /// Green under 75% of budget, orange up to 100%, red above.
    var budgetColor: Color {
        guard let f = budgetFraction else { return .accentColor }
        switch f {
        case ..<0.75: return .green
        case ..<1.0: return .orange
        default: return .red
        }
    }
}

// MARK: - Shared components

/// Small bar chart of the last 7 days of cost; today is highlighted.
struct CostBars: View {
    var days: [DailyCost]
    var tint: Color = .accentColor

    var body: some View {
        let maxValue = max(days.map(\.dollars).max() ?? 0, 0.01)
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: geo.size.width * 0.04) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i == days.count - 1 ? tint : tint.opacity(0.35))
                        .frame(height: max(geo.size.height * d.dollars / maxValue, 2))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// Circular month-to-date budget gauge.
struct BudgetRing: View {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(fraction, 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
