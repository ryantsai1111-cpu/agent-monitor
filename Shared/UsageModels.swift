import Foundation

// MARK: - Anthropic Admin API wire types

/// Response of `GET /v1/organizations/usage_report/messages`.
struct UsageReportResponse: Decodable {
    let data: [UsageBucket]
    let hasMore: Bool
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

struct UsageBucket: Decodable {
    let startingAt: Date
    let endingAt: Date
    let results: [UsageResult]

    enum CodingKeys: String, CodingKey {
        case startingAt = "starting_at"
        case endingAt = "ending_at"
        case results
    }
}

struct UsageResult: Decodable {
    struct CacheCreation: Decodable {
        let ephemeral1h: Int?
        let ephemeral5m: Int?

        enum CodingKeys: String, CodingKey {
            case ephemeral1h = "ephemeral_1h_input_tokens"
            case ephemeral5m = "ephemeral_5m_input_tokens"
        }

        var total: Int { (ephemeral1h ?? 0) + (ephemeral5m ?? 0) }
    }

    let uncachedInputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreation: CacheCreation?
    let outputTokens: Int?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case uncachedInputTokens = "uncached_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreation = "cache_creation"
        case outputTokens = "output_tokens"
        case model
    }
}

/// Response of `GET /v1/organizations/cost_report`.
struct CostReportResponse: Decodable {
    let data: [CostBucket]
    let hasMore: Bool
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

struct CostBucket: Decodable {
    let startingAt: Date
    let endingAt: Date
    let results: [CostResult]

    enum CodingKeys: String, CodingKey {
        case startingAt = "starting_at"
        case endingAt = "ending_at"
        case results
    }
}

struct CostResult: Decodable {
    /// USD, as a decimal string in cents (e.g. "1234.5" == $12.345).
    let amount: String
    let currency: String?
    let model: String?
    let description: String?

    var dollars: Double { (Double(amount) ?? 0) / 100 }
}

// MARK: - Snapshot shown by the app and the widget

struct TokenTotals: Codable, Equatable {
    var input: Int = 0
    var cacheRead: Int = 0
    var cacheWrite: Int = 0
    var output: Int = 0

    var total: Int { input + cacheRead + cacheWrite + output }

    /// Share of all input tokens that were served from cache.
    var cacheHitRate: Double {
        let allInput = input + cacheRead + cacheWrite
        return allInput == 0 ? 0 : Double(cacheRead) / Double(allInput)
    }

    mutating func add(_ r: UsageResult) {
        input += r.uncachedInputTokens ?? 0
        cacheRead += r.cacheReadInputTokens ?? 0
        cacheWrite += r.cacheCreation?.total ?? 0
        output += r.outputTokens ?? 0
    }
}

struct DailyCost: Codable, Equatable, Identifiable {
    var day: Date
    var dollars: Double
    var id: Date { day }
}

struct ModelShare: Codable, Equatable, Identifiable {
    var model: String
    var dollars: Double
    var id: String { model }
}

struct UsageSnapshot: Codable, Equatable {
    var fetchedAt: Date
    var todayCost: Double
    var monthCost: Double
    var monthlyBudget: Double?
    var todayTokens: TokenTotals
    /// Last 7 days (oldest first), including today.
    var dailyCosts: [DailyCost]
    /// Month-to-date cost per model, largest first.
    var topModels: [ModelShare]
    var isSample: Bool = false

    var budgetFraction: Double? {
        guard let budget = monthlyBudget, budget > 0 else { return nil }
        return monthCost / budget
    }

    /// Linear month-end projection from the month-to-date run rate.
    func projectedMonthCost(calendar: Calendar = .utc) -> Double {
        let now = fetchedAt
        guard let range = calendar.range(of: .day, in: .month, for: now),
              let monthStart = calendar.dateInterval(of: .month, for: now)?.start
        else { return monthCost }
        let elapsedDays = max(now.timeIntervalSince(monthStart) / 86_400, 1.0 / 24)
        return monthCost / elapsedDays * Double(range.count)
    }
}

extension Calendar {
    /// The Admin API buckets by UTC day, so all day math uses UTC.
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}

extension UsageSnapshot {
    static func sample(now: Date = Date()) -> UsageSnapshot {
        let cal = Calendar.utc
        let today = cal.startOfDay(for: now)
        let costs: [Double] = [8.4, 12.1, 6.7, 15.3, 11.0, 9.8, 13.6]
        let daily = costs.enumerated().map { i, c in
            DailyCost(day: cal.date(byAdding: .day, value: i - 6, to: today)!, dollars: c)
        }
        return UsageSnapshot(
            fetchedAt: now,
            todayCost: 13.6,
            monthCost: 187.4,
            monthlyBudget: 400,
            todayTokens: TokenTotals(input: 1_240_000, cacheRead: 6_850_000, cacheWrite: 410_000, output: 382_000),
            dailyCosts: daily,
            topModels: [
                ModelShare(model: "Claude Opus 5.5", dollars: 121.9),
                ModelShare(model: "Claude Sonnet 5.5", dollars: 48.2),
                ModelShare(model: "Claude Haiku 5.5", dollars: 17.3),
            ],
            isSample: true
        )
    }
}
