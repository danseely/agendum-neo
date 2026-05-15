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
        await loadNamespaces()
        if let active = activeNamespace {
            sync.start(namespace: active)
        }
    }

    func loadNamespaces() async {
        do {
            let accounts = try await GHCLI.listAccounts()
            guard !accounts.isEmpty else {
                self.namespaces = []
                self.activeNamespace = nil
                self.lastError = "No authenticated `gh` account found. Run `gh auth login`."
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
        }
    }

    func selectNamespace(_ namespace: Namespace) {
        guard namespace != activeNamespace else { return }
        activeNamespace = namespace
        defaults.set(namespace.id, forKey: Self.selectedNamespaceKey)
        snapshot = nil
        lastSyncedAt = nil
        lastError = nil
        sync.start(namespace: namespace)
    }

    func refresh() async {
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
