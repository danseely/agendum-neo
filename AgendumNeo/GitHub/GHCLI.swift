import Foundation

enum GHCLIError: Error, CustomStringConvertible, LocalizedError, Sendable {
    case ghNotInstalled
    case ghReturnedError(exitCode: Int32, stderr: String)
    case parseFailed(String)

    var description: String {
        switch self {
        case .ghNotInstalled:
            return "gh not found in PATH. Install via Homebrew or run from a terminal."
        case .ghReturnedError(let exitCode, let stderr):
            return "gh exited \(exitCode): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .parseFailed(let message):
            return "Failed to parse gh output: \(message)"
        }
    }

    var errorDescription: String? {
        description
    }
}

struct GHCLI {
    static let ghSearchPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

    static func listAccounts() async throws -> [GHAccount] {
        let result = try await run(arguments: ["auth", "status", "--json", "hosts"])
        guard result.exitCode == 0 else {
            if result.stderr.contains("not found") || result.stderr.contains("command not found") {
                throw GHCLIError.ghNotInstalled
            }
            throw GHCLIError.ghReturnedError(exitCode: result.exitCode, stderr: result.stderr)
        }
        guard let data = result.stdout.data(using: .utf8) else {
            throw GHCLIError.parseFailed("stdout not UTF-8")
        }
        return try parseAccounts(data: data)
    }

    static func token(for account: GHAccount) async throws -> String {
        let result = try await run(arguments: ["auth", "token", "--hostname", account.host, "--user", account.login])
        guard result.exitCode == 0 else {
            throw GHCLIError.ghReturnedError(exitCode: result.exitCode, stderr: result.stderr)
        }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw GHCLIError.parseFailed("empty token")
        }
        return trimmed
    }

    private struct ProcessResult: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private static func run(arguments: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
            // Detach so the blocking Process work doesn't pin a cooperative thread.
            let args = arguments
            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["gh"] + args
                process.environment = ["PATH": ghSearchPath]

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    // env failing to find `gh` shows up as POSIXError or NSError; surface as not installed.
                    continuation.resume(throwing: GHCLIError.ghNotInstalled)
                    return
                }

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                if process.terminationStatus == 127 {
                    continuation.resume(throwing: GHCLIError.ghNotInstalled)
                    return
                }

                let result = ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? ""
                )
                continuation.resume(returning: result)
            }
        }
    }

    private static func parseAccounts(data: Data) throws -> [GHAccount] {
        // Shape: {"hosts": {"<host>": [{"login":..., "active":..., "state":...}, ...]}}
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw GHCLIError.parseFailed("invalid JSON: \(error.localizedDescription)")
        }
        guard
            let rootDict = root as? [String: Any],
            let hosts = rootDict["hosts"] as? [String: Any]
        else {
            throw GHCLIError.parseFailed("missing hosts dictionary")
        }

        var accounts: [GHAccount] = []
        for (host, value) in hosts {
            guard let entries = value as? [[String: Any]] else { continue }
            for entry in entries {
                guard
                    let state = entry["state"] as? String,
                    state == "success",
                    let login = entry["login"] as? String
                else { continue }
                let active = (entry["active"] as? Bool) ?? false
                accounts.append(GHAccount(host: host, login: login, isActive: active))
            }
        }

        accounts.sort { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
            if lhs.host != rhs.host { return lhs.host < rhs.host }
            return lhs.login < rhs.login
        }
        return accounts
    }
}
