import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var namespaces: [Namespace] = []
    var activeNamespace: Namespace?

    var snapshot: InboxSnapshot?
    var lastError: String?
    var isLoading: Bool = false
    var lastSyncedAt: Date?
    var hasCompletedFirstSync: Bool = false

    @ObservationIgnored private var sync: SyncEngine!
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var tokensByAccount: [String: String] = [:]
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let selectedNamespaceKey = "AgendumNeo.selectedNamespaceID"

    init() {
        self.sync = SyncEngine(model: self)
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        if DemoData.isEnabled {
            await loadDemoState()
            return
        }
        await loadNamespaces()
        if let active = activeNamespace {
            sync.start(namespace: active)
        }
    }

    private func loadDemoState() async {
        // Simulate a brief network round-trip so the loading screen is
        // actually visible in demo mode.
        try? await Task.sleep(for: .milliseconds(800))
        namespaces = DemoData.namespaces
        let chosen = namespaces.first(where: { $0.kind == .user }) ?? namespaces.first
        activeNamespace = chosen
        if let chosen {
            snapshot = DemoData.snapshot(for: chosen)
            lastSyncedAt = Date()
        }
        lastError = nil
        hasCompletedFirstSync = true
    }

    func loadNamespaces() async {
        do {
            let accounts = try await GHCLI.listAccounts()
            guard !accounts.isEmpty else {
                self.namespaces = []
                self.activeNamespace = nil
                self.lastError = "No authenticated `gh` account found. Run `gh auth login`."
                self.hasCompletedFirstSync = true
                return
            }

            var all: [Namespace] = []
            for account in accounts {
                let token = try await GHCLI.token(for: account)
                tokensByAccount[account.id] = token
                let client = GitHubClient(host: account.host, token: token)
                let ns = try await client.fetchNamespaces(forAccount: account)
                all.append(contentsOf: ns)
            }
            self.namespaces = all

            let chosen: Namespace?
            if let persisted = defaults.string(forKey: Self.selectedNamespaceKey),
               let match = all.first(where: { $0.id == persisted }) {
                chosen = match
            } else if let userNS = all.first(where: { $0.kind == .user }) {
                chosen = userNS
            } else {
                chosen = all.first
            }
            self.activeNamespace = chosen
            self.lastError = nil
        } catch {
            if let ghError = error as? GHCLIError {
                self.lastError = ghError.description
            } else {
                self.lastError = String(describing: error)
            }
            self.hasCompletedFirstSync = true
        }
    }

    func selectNamespace(_ namespace: Namespace) {
        guard namespace != activeNamespace else { return }
        activeNamespace = namespace
        if DemoData.isEnabled {
            snapshot = DemoData.snapshot(for: namespace)
            lastSyncedAt = Date()
            lastError = nil
            return
        }
        defaults.set(namespace.id, forKey: Self.selectedNamespaceKey)
        snapshot = nil
        lastSyncedAt = nil
        lastError = nil
        sync.start(namespace: namespace)
    }

    func refresh() async {
        if DemoData.isEnabled {
            if let ns = activeNamespace {
                snapshot = DemoData.snapshot(for: ns)
                lastSyncedAt = Date()
            }
            return
        }
        guard let ns = activeNamespace else {
            await loadNamespaces()
            if let activeNamespace {
                sync.start(namespace: activeNamespace)
            }
            return
        }
        await sync.fetchOnce(namespace: ns)
    }

    func token(forAccount accountID: String) -> String? {
        tokensByAccount[accountID]
    }
}
