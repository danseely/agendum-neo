import SwiftUI

enum RowColumns {
    static let status: CGFloat = 130
    static let author: CGFloat = 90
    static let repo: CGFloat = 130
    static let number: CGFloat = 56
    static let spacing: CGFloat = 12
}

struct PRRowView: View {
    let pr: PullRequest
    let kind: Kind

    enum Kind {
        case authored
        case reviewRequested
    }

    var body: some View {
        InboxRow(
            number: pr.number,
            url: pr.url,
            author: pr.author,
            repository: pr.repository,
            status: StatusPill(text: statusText, color: statusColor)
        ) {
            HStack(spacing: 6) {
                Text(pr.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if pr.isDraft {
                    DraftBadge()
                }
            }
        }
        .contentShape(Rectangle())
        .help(pr.title)
    }

    private var statusText: String {
        switch kind {
        case .authored:
            switch pr.authoredStatus {
            case .open: return "Open"
            case .waitingForReview: return "Waiting for review"
            case .reviewReceived: return "Review received"
            }
        case .reviewRequested:
            return "Review requested"
        }
    }

    private var statusColor: Color {
        switch kind {
        case .authored:
            switch pr.authoredStatus {
            case .open: return StatusPalette.open
            case .waitingForReview: return StatusPalette.waitingForReview
            case .reviewReceived: return StatusPalette.reviewReceived
            }
        case .reviewRequested:
            return StatusPalette.reviewRequested
        }
    }
}

struct IssueRowView: View {
    let issue: Issue
    let viewerLogin: String?

    var body: some View {
        InboxRow(
            number: issue.number,
            url: issue.url,
            author: issue.author,
            repository: issue.repository,
            status: StatusPill(text: statusText, color: statusColor)
        ) {
            Text(issue.title)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .contentShape(Rectangle())
        .help(issue.title)
    }

    private var statusText: String {
        switch issue.status(viewerLogin: viewerLogin) {
        case .open: return "Open"
        case .assignedToYou: return "Assigned to you"
        }
    }

    private var statusColor: Color {
        switch issue.status(viewerLogin: viewerLogin) {
        case .open: return StatusPalette.open
        case .assignedToYou: return StatusPalette.assignedToYou
        }
    }
}

private enum StatusPalette {
    static let open               = Color(hex: 0x60a5fa)
    static let waitingForReview   = Color(hex: 0xffaa00)
    static let reviewReceived     = Color(hex: 0xf59e0b)
    static let reviewRequested    = Color(hex: 0xa78bfa)
    static let assignedToYou      = Color(hex: 0xa78bfa)
}

private extension Color {
    init(hex: Int) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >>  8) & 0xff) / 255,
            blue:  Double( hex        & 0xff) / 255
        )
    }
}

private struct InboxRow<Status: View, Title: View>: View {
    let number: Int
    let url: URL
    let author: String
    let repository: String
    let status: Status
    let title: Title

    init(
        number: Int,
        url: URL,
        author: String,
        repository: String,
        status: Status,
        @ViewBuilder title: () -> Title
    ) {
        self.number = number
        self.url = url
        self.author = author
        self.repository = repository
        self.status = status
        self.title = title()
    }

    var body: some View {
        HStack(spacing: RowColumns.spacing) {
            status
                .frame(width: RowColumns.status, alignment: .leading)

            title
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(author)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
                .frame(width: RowColumns.author, alignment: .leading)

            Text(repoShortName(repository))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(width: RowColumns.repo, alignment: .leading)

            Link("#\(number)", destination: url)
                .pointerStyle(.link)
                .font(.callout)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: RowColumns.number, alignment: .trailing)
        }
    }
}

private struct DraftBadge: View {
    var body: some View {
        Text("DRAFT")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.2)))
            .foregroundStyle(.secondary)
    }
}

private struct StatusPill: View {
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

private func repoShortName(_ ownerSlashName: String) -> String {
    if let slash = ownerSlashName.firstIndex(of: "/") {
        return String(ownerSlashName[ownerSlashName.index(after: slash)...])
    }
    return ownerSlashName
}
