import AppIntents
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let error: String?

    static let placeholder = UsageEntry(date: Date(), snapshot: .sample(), error: nil)
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(SharedStore.lastSnapshot.map { UsageEntry(date: Date(), snapshot: $0, error: nil) } ?? .placeholder)
            return
        }
        Task {
            let result = await SharedStore.refresh()
            completion(UsageEntry(date: Date(), snapshot: result.snapshot, error: result.error))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let result = await SharedStore.refresh()
            let entry = UsageEntry(date: Date(), snapshot: result.snapshot, error: result.error)
            let next = Date().addingTimeInterval(AppConfig.refreshInterval)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

/// Tapping the refresh button in the widget. WidgetKit reloads the timeline after any
/// widget intent runs, and getTimeline does the fetch, so there is nothing to do here.
struct RefreshUsageIntent: AppIntent {
    static var title: LocalizedStringResource = "重新整理用量"

    func perform() async throws -> some IntentResult { .result() }
}
