import Foundation

@MainActor
final class SyncEngine {
    private weak var model: AppModel?
    private var task: Task<Void, Never>?
    private static let interval: Duration = .seconds(5 * 60)

    init(model: AppModel) {
        self.model = model
    }

    deinit {
        task?.cancel()
    }

    func start(namespace: Namespace) {
        stop()
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.fetchOnce(namespace: namespace)
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func fetchOnce(namespace: Namespace) async {
        guard let model else { return }
        model.isLoading = true
        defer { model.isLoading = false }
        do {
            let accountID = "\(namespace.host)/\(namespace.accountLogin)"
            let token: String
            if let cached = model.token(forAccount: accountID) {
                token = cached
            } else {
                token = try await GHCLI.token(for: GHAccount(
                    host: namespace.host,
                    login: namespace.accountLogin,
                    isActive: false
                ))
            }
            let client = GitHubClient(host: namespace.host, token: token)
            let snapshot = try await client.fetchInbox(for: namespace)
            model.snapshot = snapshot
            model.lastSyncedAt = Date()
            model.lastError = nil
        } catch is CancellationError {
            return
        } catch {
            model.lastError = errorMessage(error)
        }
    }

    private func errorMessage(_ error: any Error) -> String {
        switch error {
        case let e as GHCLIError:
            switch e {
            case .ghNotInstalled: return "`gh` CLI not found in PATH."
            case .ghReturnedError(let code, let stderr):
                return "gh exited \(code): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            case .parseFailed(let msg): return "Failed to parse gh output: \(msg)"
            }
        case let e as GitHubError:
            switch e {
            case .httpStatus(let code, let body):
                return "GitHub HTTP \(code): \(body.prefix(200))"
            case .graphQLErrors(let msgs):
                return "GitHub: \(msgs.joined(separator: "; "))"
            case .decoding(let m): return "Decode error: \(m)"
            }
        default:
            return String(describing: error)
        }
    }
}
