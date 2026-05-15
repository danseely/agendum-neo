import SwiftUI

enum RowColumns {
    static let status: CGFloat = 110
    static let author: CGFloat = 110
    static let repo: CGFloat = 130
    static let number: CGFloat = 60
    static let spacing: CGFloat = 12
}

struct PRRowView: View {
    let pr: PullRequest

    var body: some View {
        HStack(spacing: RowColumns.spacing) {
            StatusPill(text: statusText, color: statusColor)
                .frame(width: RowColumns.status, alignment: .leading)

            HStack(spacing: 6) {
                Text(pr.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if pr.isDraft {
                    Text("DRAFT")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.2)))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(pr.author)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
                .frame(width: RowColumns.author, alignment: .leading)

            Text(repoShortName(pr.repository))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(width: RowColumns.repo, alignment: .leading)

            Link("#\(pr.number)", destination: pr.url)
                .pointerStyle(.link)
                .frame(width: RowColumns.number, alignment: .trailing)
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
        HStack(spacing: RowColumns.spacing) {
            StatusPill(text: "Open", color: .green)
                .frame(width: RowColumns.status, alignment: .leading)

            Text(issue.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(issue.author)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
                .frame(width: RowColumns.author, alignment: .leading)

            Text(repoShortName(issue.repository))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(width: RowColumns.repo, alignment: .leading)

            Link("#\(issue.number)", destination: issue.url)
                .pointerStyle(.link)
                .frame(width: RowColumns.number, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .help(issue.title)
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
