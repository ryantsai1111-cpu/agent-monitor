import SwiftUI
import WidgetKit

@main
struct AgentMonitorApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
    }
}

@MainActor
final class DashboardModel: ObservableObject {
    @Published var snapshot: UsageSnapshot? = SharedStore.lastSnapshot
    @Published var error: String? = SharedStore.lastError
    @Published var isLoading = false
    @Published var hasKey = SharedStore.adminKey != nil

    func refresh() async {
        guard hasKey else { return }
        isLoading = true
        let result = await SharedStore.refresh()
        snapshot = result.snapshot
        error = result.error
        isLoading = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    func save(key: String, budget: Double?) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { SharedStore.adminKey = trimmed }
        SharedStore.monthlyBudget = budget
        hasKey = SharedStore.adminKey != nil
        await refresh()
    }

    func signOut() {
        SharedStore.adminKey = nil
        SharedStore.lastSnapshot = nil
        SharedStore.lastError = nil
        snapshot = nil
        error = nil
        hasKey = false
        WidgetCenter.shared.reloadAllTimelines()
    }
}
