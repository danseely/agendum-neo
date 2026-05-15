import SwiftUI

struct PRRowView: View {
    let pr: PullRequest

    var body: some View {
        InboxRow(
            title: pr.title,
            metadata: "\(pr.author) - \(repoShortName(pr.repository))",
            number: pr.number,
            url: pr.url,
            status: StatusPill(text: statusText, color: statusColor)
        ) {
            if pr.isDraft {
                DraftBadge()
            }
        }
        .contentShape(Rectangle())
        .help(pr.title)
    }

    private var statusText: String {
        switch pr.reviewState {
        case .waiting: return "Waiting"
        case .approved: return "Approved"
        case .changesRequested: return "Changes"
        case .commented: return "Commented"
        }
    }

    private var statusColor: Color {
        switch pr.reviewState {
        case .waiting: return .gray
        case .approved: return .green
        case .changesRequested: return .red
        case .commented: return .yellow
        }
    }
}

struct IssueRowView: View {
    let issue: Issue

    var body: some View {
        InboxRow(
            title: issue.title,
            metadata: "\(issue.author) - \(repoShortName(issue.repository))",
            number: issue.number,
            url: issue.url,
            status: StatusPill(text: "Open", color: .green)
        )
        .contentShape(Rectangle())
        .help(issue.title)
    }
}

private struct InboxRow<Status: View, Accessory: View>: View {
    let title: String
    let metadata: String
    let number: Int
    let url: URL
    let status: Status
    let accessory: Accessory

    init(
        title: String,
        metadata: String,
        number: Int,
        url: URL,
        status: Status,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.metadata = metadata
        self.number = number
        self.url = url
        self.status = status
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            status
                .frame(width: 86, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    accessory
                }

                Text(metadata)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Link("#\(number)", destination: url)
                .pointerStyle(.link)
                .font(.callout)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

private extension InboxRow where Accessory == EmptyView {
    init(
        title: String,
        metadata: String,
        number: Int,
        url: URL,
        status: Status
    ) {
        self.init(
            title: title,
            metadata: metadata,
            number: number,
            url: url,
            status: status
        ) {
            EmptyView()
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
    }
}

private func repoShortName(_ ownerSlashName: String) -> String {
    if let slash = ownerSlashName.firstIndex(of: "/") {
        return String(ownerSlashName[ownerSlashName.index(after: slash)...])
    }
    return ownerSlashName
}
