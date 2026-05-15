import SwiftUI

enum InboxItemID: Hashable {
    case pr(String)
    case issue(String)
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    @State private var selection: InboxItemID?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            inboxList

            Divider()

            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .frame(
            minWidth: 360,
            idealWidth: 420,
            minHeight: 320,
            idealHeight: 520
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if app.namespaces.isEmpty {
                Text("Not signed in. Run `gh auth login`.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Namespace", selection: namespacePickerBinding) {
                    ForEach(app.namespaces) { ns in
                        Label {
                            Text(ns.displayName)
                        } icon: {
                            Image(systemName: ns.kind == .user ? "person.crop.circle" : "building.2")
                        }
                        .tag(Optional(ns))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }

            Spacer(minLength: 0)
                .contentShape(.rect)
                .onTapGesture { selection = nil }

            if app.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await app.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(app.isLoading)
            .help("Refresh")
        }
    }

    private var namespacePickerBinding: Binding<Namespace?> {
        Binding(
            get: { app.activeNamespace },
            set: { newValue in
                if let newValue {
                    app.selectNamespace(newValue)
                }
            }
        )
    }

    // MARK: - List

    private var inboxList: some View {
        List(selection: $selection) {
            Section {
                if authoredPRs.isEmpty {
                    Text("No PRs")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(authoredPRs) { pr in
                        PRRowView(pr: pr)
                            .tag(InboxItemID.pr(pr.id))
                            .contextMenu {
                                Button("Open in Browser") { openURL(pr.url) }
                            }
                    }
                }
            } header: {
                SectionHeader(title: "Your PRs", count: authoredPRs.count)
            }

            Section {
                if reviewRequestedPRs.isEmpty {
                    Text("No PRs")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(reviewRequestedPRs) { pr in
                        PRRowView(pr: pr)
                            .tag(InboxItemID.pr(pr.id))
                            .contextMenu {
                                Button("Open in Browser") { openURL(pr.url) }
                            }
                    }
                }
            } header: {
                SectionHeader(title: "Awaiting your review", count: reviewRequestedPRs.count)
            }

            Section {
                if assignedIssues.isEmpty {
                    Text("No issues")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(assignedIssues) { issue in
                        IssueRowView(issue: issue)
                            .tag(InboxItemID.issue(issue.id))
                            .contextMenu {
                                Button("Open in Browser") { openURL(issue.url) }
                            }
                    }
                }
            } header: {
                SectionHeader(title: "Assigned issues", count: assignedIssues.count)
            }
        }
        .background(ListDoubleClickHandler { openSelection() })
        .onKeyPress(.return) {
            openSelection()
            return .handled
        }
        .onKeyPress(.space) {
            openSelection()
            return .handled
        }
        .onKeyPress(.escape) {
            guard selection != nil else { return .ignored }
            selection = nil
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard selection == nil, let first = orderedItemIDs.first else { return .ignored }
            selection = first
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard selection == nil, let last = orderedItemIDs.last else { return .ignored }
            selection = last
            return .handled
        }
    }

    private var orderedItemIDs: [InboxItemID] {
        authoredPRs.map { .pr($0.id) }
        + reviewRequestedPRs.map { .pr($0.id) }
        + assignedIssues.map { .issue($0.id) }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let err = app.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            if let synced = app.lastSyncedAt {
                HStack(spacing: 4) {
                    Text("Synced")
                    Text(synced, style: .relative)
                    Text("ago")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("Not yet synced")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .onTapGesture { selection = nil }
    }

    // MARK: - Derived data

    private var authoredPRs: [PullRequest] {
        app.snapshot?.authoredPRs ?? []
    }

    private var reviewRequestedPRs: [PullRequest] {
        app.snapshot?.reviewRequestedPRs ?? []
    }

    private var assignedIssues: [Issue] {
        app.snapshot?.assignedIssues ?? []
    }

    // MARK: - Selection helpers

    private func openSelection() {
        guard let selection else { return }
        switch selection {
        case .pr(let id):
            if let pr = (authoredPRs + reviewRequestedPRs).first(where: { $0.id == id }) {
                openURL(pr.url)
            }
        case .issue(let id):
            if let issue = assignedIssues.first(where: { $0.id == id }) {
                openURL(issue.url)
            }
        }
    }
}
