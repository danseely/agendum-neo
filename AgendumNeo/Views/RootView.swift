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
        Group {
            if app.namespaces.isEmpty {
                unavailableContent
            } else {
                inboxList
            }
        }
        .frame(
            minWidth: 360,
            idealWidth: 440,
            minHeight: 320,
            idealHeight: 520
        )
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if !app.namespaces.isEmpty {
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
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if app.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await app.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
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

    private var unavailableContent: some View {
        ContentUnavailableView {
            Label("GitHub Sign-In Required", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text("Run `gh auth login` and refresh Agendum Neo.")
        } actions: {
            Button {
                Task { await app.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(app.isLoading)
        }
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
                            .padding(.vertical, 3)
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
                            .padding(.vertical, 3)
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
                            .padding(.vertical, 3)
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
