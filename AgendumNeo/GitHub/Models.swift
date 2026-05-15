import Foundation

struct GHAccount: Sendable, Hashable, Identifiable, Codable {
    let host: String
    let login: String
    let isActive: Bool
    var id: String { "\(host)/\(login)" }
    var displayName: String { "\(login)@\(host)" }
}

struct Namespace: Sendable, Hashable, Identifiable, Codable {
    enum Kind: String, Sendable, Codable { case user, org }
    let host: String
    let accountLogin: String
    let owner: String
    let kind: Kind
    var id: String { "\(host)/\(accountLogin)/\(owner)" }
    var displayName: String { owner }
}

enum ReviewState: String, Sendable, Codable {
    case waiting
    case approved
    case changesRequested
    case commented
}

struct PullRequest: Sendable, Hashable, Identifiable, Codable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let repository: String
    let author: String
    let isDraft: Bool
    let updatedAt: Date
    let reviewState: ReviewState
    let reviewCount: Int
}

struct Issue: Sendable, Hashable, Identifiable, Codable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let repository: String
    let author: String
    let updatedAt: Date
}

struct InboxSnapshot: Sendable, Hashable, Codable {
    let namespace: Namespace
    let fetchedAt: Date
    let authoredPRs: [PullRequest]
    let reviewRequestedPRs: [PullRequest]
    let assignedIssues: [Issue]
}
