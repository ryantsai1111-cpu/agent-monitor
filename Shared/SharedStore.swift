import Foundation
import Security

enum AppConfig {
    /// Must match the App Group in both targets' entitlements (see project.yml).
    static let appGroup = "group.com.ryantsai.agentmonitor"
    static let widgetKind = "AgentUsageWidget"
    /// WidgetKit refresh cadence. The Usage & Cost API refreshes roughly every 5 minutes.
    static let refreshInterval: TimeInterval = 15 * 60
}

/// Settings and the last snapshot, shared between the app and the widget via the App Group.
enum SharedStore {
    private static var defaults: UserDefaults { UserDefaults(suiteName: AppConfig.appGroup) ?? .standard }
    private static let snapshotKey = "lastSnapshot"
    private static let budgetKey = "monthlyBudget"
    private static let errorKey = "lastError"

    static var monthlyBudget: Double? {
        get {
            let v = defaults.double(forKey: budgetKey)
            return v > 0 ? v : nil
        }
        set { defaults.set(newValue ?? 0, forKey: budgetKey) }
    }

    static var lastSnapshot: UsageSnapshot? {
        get {
            guard let data = defaults.data(forKey: snapshotKey) else { return nil }
            return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
        }
        set {
            defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: snapshotKey)
        }
    }

    static var lastError: String? {
        get { defaults.string(forKey: errorKey) }
        set { defaults.set(newValue, forKey: errorKey) }
    }

    static var adminKey: String? {
        get { Keychain.read() }
        set {
            if let newValue, !newValue.isEmpty { Keychain.write(newValue) } else { Keychain.delete() }
        }
    }

    /// Fetches a fresh snapshot, caches it, and records any error for display.
    /// Falls back to the cached snapshot on failure so the widget never goes blank.
    @discardableResult
    static func refresh() async -> (snapshot: UsageSnapshot?, error: String?) {
        guard let key = adminKey else {
            lastError = UsageClientError.missingKey.errorDescription
            return (nil, lastError)
        }
        do {
            let snap = try await AnthropicUsageClient(adminKey: key).fetchSnapshot(monthlyBudget: monthlyBudget)
            lastSnapshot = snap
            lastError = nil
            return (snap, nil)
        } catch {
            lastError = error.localizedDescription
            return (lastSnapshot, lastError)
        }
    }
}

/// Stores the Admin API key in the Keychain under the App Group access group so the widget can read it.
enum Keychain {
    private static let service = "com.ryantsai.agentmonitor.adminKey"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "anthropic-admin",
            kSecAttrAccessGroup as String: AppConfig.appGroup,
        ]
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String) {
        delete()
        var query = baseQuery
        query[kSecValueData as String] = Data(value.utf8)
        // The widget refreshes in the background while the device is locked.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
