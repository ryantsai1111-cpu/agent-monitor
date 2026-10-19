import Foundation

enum UsageClientError: LocalizedError {
    case missingKey
    case http(status: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "尚未設定 Admin API key"
        case let .http(status, message):
            switch status {
            case 401: return "API key 無效（401）。請確認使用 sk-ant-admin 開頭的 Admin key。"
            case 403: return "權限不足（403）：\(message)"
            case 429: return "請求過於頻繁（429），稍後再試。"
            default: return "HTTP \(status)：\(message)"
            }
        case .invalidResponse:
            return "無法解析伺服器回應"
        }
    }
}

/// Raw-HTTP client for the Anthropic Usage & Cost Admin API.
/// These endpoints are not in the SDKs and require an Admin API key (`sk-ant-admin...`).
struct AnthropicUsageClient {
    var adminKey: String
    var baseURL = URL(string: "https://api.anthropic.com")!
    var session: URLSession = .shared

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = plain.date(from: s) ?? fractional.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Bad date: \(s)"))
        }
        return d
    }()

    private static let iso: ISO8601DateFormatter = ISO8601DateFormatter()

    // MARK: Endpoints

    func usageReport(from start: Date, groupByModel: Bool = false) async throws -> [UsageBucket] {
        var items = [
            URLQueryItem(name: "starting_at", value: Self.iso.string(from: start)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31"),
        ]
        if groupByModel { items.append(URLQueryItem(name: "group_by[]", value: "model")) }
        return try await paginate(path: "/v1/organizations/usage_report/messages", query: items) {
            (page: UsageReportResponse) in (page.data, page.hasMore ? page.nextPage : nil)
        }
    }

    func costReport(from start: Date) async throws -> [CostBucket] {
        let items = [
            URLQueryItem(name: "starting_at", value: Self.iso.string(from: start)),
            URLQueryItem(name: "group_by[]", value: "description"),
            URLQueryItem(name: "limit", value: "31"),
        ]
        return try await paginate(path: "/v1/organizations/cost_report", query: items) {
            (page: CostReportResponse) in (page.data, page.hasMore ? page.nextPage : nil)
        }
    }

    // MARK: Snapshot

    /// Fetches month-to-date cost plus the last 7 days of usage and folds them into one snapshot.
    func fetchSnapshot(monthlyBudget: Double?, now: Date = Date()) async throws -> UsageSnapshot {
        let cal = Calendar.utc
        let today = cal.startOfDay(for: now)
        let weekStart = cal.date(byAdding: .day, value: -6, to: today)!
        let monthStart = cal.dateInterval(of: .month, for: now)!.start
        // Cover both the current month and the 7-day sparkline in one cost query.
        let costStart = min(weekStart, monthStart)

        async let costBuckets = costReport(from: costStart)
        async let usageBuckets = usageReport(from: today)
        let (costs, usage) = try await (costBuckets, usageBuckets)

        var monthCost = 0.0
        var todayCost = 0.0
        var perDay: [Date: Double] = [:]
        var perModel: [String: Double] = [:]
        for bucket in costs {
            let day = cal.startOfDay(for: bucket.startingAt)
            let sum = bucket.results.reduce(0) { $0 + $1.dollars }
            perDay[day, default: 0] += sum
            if day == today { todayCost += sum }
            guard day >= monthStart else { continue }
            monthCost += sum
            for r in bucket.results {
                perModel[Self.displayName(for: r.model ?? r.description), default: 0] += r.dollars
            }
        }

        var tokens = TokenTotals()
        for bucket in usage where cal.startOfDay(for: bucket.startingAt) == today {
            bucket.results.forEach { tokens.add($0) }
        }

        let daily = (0..<7).map { offset -> DailyCost in
            let day = cal.date(byAdding: .day, value: offset, to: weekStart)!
            return DailyCost(day: day, dollars: perDay[day] ?? 0)
        }
        let top = perModel
            .map { ModelShare(model: $0.key, dollars: $0.value) }
            .filter { $0.dollars > 0 }
            .sorted { $0.dollars > $1.dollars }

        return UsageSnapshot(fetchedAt: now,
                             todayCost: todayCost,
                             monthCost: monthCost,
                             monthlyBudget: monthlyBudget,
                             todayTokens: tokens,
                             dailyCosts: daily,
                             topModels: Array(top.prefix(5)))
    }

    /// "claude-opus-5-5" -> "Claude Opus 5.5". Non-model descriptions pass through unchanged.
    static func displayName(for raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "其他" }
        guard raw.hasPrefix("claude-") else { return raw }
        let parts = raw.split(separator: "-").map(String.init)
        var words: [String] = []
        var digits: [String] = []
        for p in parts {
            if p.allSatisfy(\.isNumber) {
                // Skip date suffixes such as 20250514.
                if p.count < 4 { digits.append(p) }
            } else {
                words.append(p.prefix(1).uppercased() + p.dropFirst())
            }
        }
        return (words + (digits.isEmpty ? [] : [digits.joined(separator: ".")])).joined(separator: " ")
    }

    // MARK: Transport

    private func paginate<Page: Decodable, Item>(
        path: String,
        query: [URLQueryItem],
        extract: (Page) -> ([Item], String?)
    ) async throws -> [Item] {
        var all: [Item] = []
        var nextPage: String?
        repeat {
            var items = query
            if let nextPage { items.append(URLQueryItem(name: "page", value: nextPage)) }
            let page: Page = try await get(path: path, query: items)
            let (data, next) = extract(page)
            all += data
            nextPage = next
        } while nextPage != nil
        return all
    }

    private func get<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        guard !adminKey.isEmpty else { throw UsageClientError.missingKey }
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query
        // URLComponents leaves "[]" and "+" unescaped; "+" in a page token would decode as a space.
        comps.percentEncodedQuery = comps.percentEncodedQuery?
            .replacingOccurrences(of: "[", with: "%5B")
            .replacingOccurrences(of: "]", with: "%5D")
            .replacingOccurrences(of: "+", with: "%2B")

        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 20
        req.setValue(adminKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("AgentMonitor-iOS/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw UsageClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw UsageClientError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    private static func errorMessage(from data: Data) -> String {
        struct Envelope: Decodable { struct E: Decodable { let message: String }; let error: E }
        if let env = try? JSONDecoder().decode(Envelope.self, from: data) { return env.error.message }
        return String(data: data, encoding: .utf8)?.prefix(200).description ?? ""
    }
}
