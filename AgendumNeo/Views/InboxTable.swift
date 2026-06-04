import SwiftUI

/// A view-layer enum unifying the three inbox row shapes into a single
/// `RowValue` type so they can share one `Table` (and therefore one selection
/// surface, one scroll surface, and one column schema).
enum InboxItem: Identifiable, Hashable {
    case authoredPR(PullRequest)
    case reviewPR(ReviewInboxPR)
    case issue(Issue, viewerLogin: String?)

    var id: InboxItemID {
        switch self {
        case .authoredPR(let pr): return .pr(pr.id)
        case .reviewPR(let review): return .pr(review.id)
        case .issue(let issue, _): return .issue(issue.id)
        }
    }

    var title: String {
        switch self {
        case .authoredPR(let pr): return pr.title
        case .reviewPR(let review): return review.pullRequest.title
        case .issue(let issue, _): return issue.title
        }
    }

    var url: URL {
        switch self {
        case .authoredPR(let pr): return pr.url
        case .reviewPR(let review): return review.pullRequest.url
        case .issue(let issue, _): return issue.url
        }
    }

    var author: String {
        switch self {
        case .authoredPR(let pr): return pr.author
        case .reviewPR(let review): return review.pullRequest.author
        case .issue(let issue, _): return issue.author
        }
    }

    var repository: String {
        switch self {
        case .authoredPR(let pr): return pr.repository
        case .reviewPR(let review): return review.pullRequest.repository
        case .issue(let issue, _): return issue.repository
        }
    }

    var number: Int {
        switch self {
        case .authoredPR(let pr): return pr.number
        case .reviewPR(let review): return review.pullRequest.number
        case .issue(let issue, _): return issue.number
        }
    }

    var isDraftPR: Bool {
        switch self {
        case .authoredPR(let pr): return pr.isDraft
        case .reviewPR(let review): return review.pullRequest.isDraft
        case .issue: return false
        }
    }

    var statusText: String {
        switch self {
        case .authoredPR(let pr):
            switch pr.authoredStatus {
            case .open: return "Open"
            case .waitingForReview: return "Waiting for review"
            case .approved: return "Approved"
            case .changesRequested: return "Changes requested"
            case .commented: return "Commented"
            }
        case .reviewPR(let review):
            switch review.status {
            case .reviewRequested: return "Review requested"
            case .reviewed: return "Reviewed"
            }
        case .issue(let issue, let viewerLogin):
            switch issue.status(viewerLogin: viewerLogin) {
            case .open: return "Open"
            case .assignedToYou: return "Assigned to you"
            }
        }
    }

    var statusColor: Color {
        switch self {
        case .authoredPR(let pr):
            switch pr.authoredStatus {
            case .open: return StatusPalette.open
            case .waitingForReview: return StatusPalette.waitingForReview
            case .approved: return StatusPalette.approved
            case .changesRequested: return StatusPalette.changesRequested
            case .commented: return StatusPalette.commented
            }
        case .reviewPR(let review):
            switch review.status {
            case .reviewRequested: return StatusPalette.reviewRequested
            case .reviewed: return StatusPalette.reviewed
            }
        case .issue(let issue, let viewerLogin):
            switch issue.status(viewerLogin: viewerLogin) {
            case .open: return StatusPalette.open
            case .assignedToYou: return StatusPalette.assignedToYou
            }
        }
    }
}

// MARK: - Cell helpers

enum StatusPalette {
    static let open               = Color(hex: 0x60a5fa)
    static let waitingForReview   = Color(hex: 0xffaa00)
    static let approved           = Color(hex: 0x4ade80)
    static let changesRequested   = Color(hex: 0xf87171)
    static let commented          = Color(hex: 0x94a3b8)
    static let reviewRequested    = Color(hex: 0xa78bfa)
    // Positive "you've done your part" green for a PR you just reviewed. Emerald
    // sits between the brighter `approved` green and the cyan `assignedToYou`
    // teal, so it reads as a distinct success state within the review section.
    static let reviewed           = Color(hex: 0x34d399)
    static let assignedToYou      = Color(hex: 0x2dd4bf)
}

extension Color {
    init(hex: Int) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >>  8) & 0xff) / 255,
            blue:  Double( hex        & 0xff) / 255
        )
    }
}

struct DraftBadge: View {
    var body: some View {
        Text("DRAFT")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.2)))
            .foregroundStyle(.secondary)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

func repoShortName(_ ownerSlashName: String) -> String {
    if let slash = ownerSlashName.firstIndex(of: "/") {
        return String(ownerSlashName[ownerSlashName.index(after: slash)...])
    }
    return ownerSlashName
}
