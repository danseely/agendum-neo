import SwiftUI

enum InboxItemID: Hashable {
    case pr(String)
    case issue(String)
}

struct RootView: View {
    enum Presentation {
        case window
        case menuBar
    }

    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    @State private var selection: InboxItemID?
    @State private var lockedIdealHeight: CGFloat?

    var presentation: Presentation = .window

    var body: some View {
        Group {
            if showLoadingScreen {
                loadingContent
            } else if app.namespaces.isEmpty {
                unavailableContent
            } else {
                inboxList
            }
        }
        .frame(
            minWidth: 620,
            idealWidth: 720,
            minHeight: 320,
            idealHeight: currentIdealHeight
        )
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
        }
        .onChange(of: app.hasCompletedFirstSync, initial: true) { _, completed in
            guard presentation == .window, lockedIdealHeight == nil, completed else { return }
            let target = computeIdealContentHeight()
            lockedIdealHeight = target
            resizeWindowHeight(to: target)
        }
    }

    /// Resize the live NSWindow to the target content height, anchored to the
    /// window's current top edge so the title bar stays put. SwiftUI's
    /// `.windowResizability(.contentSize)` only honors `idealHeight` at window
    /// creation, so once the window is on-screen we drive AppKit directly.
    /// Deferred a few frames so the loading-state transition completes before
    /// the resize animation kicks in.
    private func resizeWindowHeight(to targetContentHeight: CGFloat) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let window = NSApp.windows.first(where: {
                $0.styleMask.contains(.titled) && $0.contentView != nil
            }) else { return }

            let currentFrame = window.frame
            let currentContent = window.contentRect(forFrameRect: currentFrame)
            let targetContentRect = NSRect(
                x: currentContent.origin.x,
                y: currentContent.origin.y,
                width: currentContent.width,
                height: targetContentHeight
            )
            let targetFrame = window.frameRect(forContentRect: targetContentRect)
            var newFrame = currentFrame
            newFrame.size.height = targetFrame.height
            newFrame.origin.y = currentFrame.maxY - targetFrame.height

            window.setFrame(newFrame, display: true, animate: true)
        }
    }

    private var currentIdealHeight: CGFloat {
        if presentation == .menuBar { return 520 }
        return lockedIdealHeight ?? loadingIdealHeight
    }

    private var loadingIdealHeight: CGFloat { 320 }

    // MARK: - First-sync gating / sizing

    private var showLoadingScreen: Bool {
        // Before the first sync completes, show a blank loading screen instead
        // of empty section headers or the "sign-in required" empty state.
        !app.hasCompletedFirstSync && app.lastError == nil
    }

    private var loadingContent: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.regular)
                Text("Loading...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Compute the window's ideal content height from the current snapshot.
    /// With `.windowResizability(.contentSize)` the `WindowGroup` follows this
    /// value, so we apply it once on first-sync completion to grow the window
    /// to fit the loaded data. Capped at 80% of the screen's visible height.
    private func computeIdealContentHeight() -> CGFloat {
        let screenHeight =
            NSScreen.main?.visibleFrame.height
            ?? InboxWindowHeight.fallbackScreenHeight
        return InboxWindowHeight.compute(
            authoredPRCount: app.snapshot?.authoredPRs.count ?? 0,
            reviewRequestedPRCount: app.snapshot?.reviewRequestedPRs.count ?? 0,
            assignedIssueCount: app.snapshot?.assignedIssues.count ?? 0,
            screenVisibleHeight: screenHeight
        )
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
                        PRRowView(pr: pr, kind: .authored)
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
                        PRRowView(pr: pr, kind: .reviewRequested)
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
                        IssueRowView(issue: issue, viewerLogin: viewerLogin)
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

    private var viewerLogin: String? {
        app.activeNamespace?.accountLogin
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
