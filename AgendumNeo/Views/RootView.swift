import AppKit
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

    /// How (if at all) to surface an access restriction in the UI.
    enum RestrictionDisplay: Equatable {
        /// Don't surface anything (no restriction, or a personal `.user`
        /// namespace where the org-SSO copy makes no sense).
        case none
        /// Replace the inbox with the full-screen restriction message (the
        /// restricted namespace returned an empty inbox).
        case fullScreen
        /// Show the partial-results banner above a non-empty list.
        case banner
    }

    /// Pure, testable decision for whether and how to surface an access
    /// restriction. The org-SSO copy only applies to `.org` namespaces; a
    /// `.user` namespace never shows it (an SSO "authorize" prompt is
    /// nonsensical for a personal account), regardless of any restriction.
    static func shouldShowRestriction(
        kind: Namespace.Kind?,
        restriction: AccessRestriction?,
        inboxEmpty: Bool
    ) -> RestrictionDisplay {
        guard kind == .org, restriction != nil else { return .none }
        return inboxEmpty ? .fullScreen : .banner
    }

    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.uiFontScale) private var uiFontScale

    @State private var selection: InboxItemID?
    @State private var lockedIdealHeight: CGFloat?
    @FocusState private var isInboxFocused: Bool

    var presentation: Presentation = .window

    var body: some View {
        Group {
            if showLoadingScreen {
                loadingContent
            } else if app.namespaces.isEmpty {
                unavailableContent
            } else if restrictionDisplay == .fullScreen, let restriction = app.accessRestriction {
                restrictionContent(restriction)
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
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if let err = app.lastError {
                    bannerText(err, color: .red)
                }
                // Partial results still render the list; warn above it. The
                // empty case is handled by `restrictionContent` instead.
                if restrictionDisplay == .banner, let restriction = app.accessRestriction {
                    bannerText(restriction.bannerText(owner: ownerName), color: .orange)
                }
            }
        }
        // Browser-style zoom. .scaleEffect alone scales the rendered output
        // but NOT the layout bounds — at scale > 1.0 the Table lays out
        // against the full window width, then renders at width * scale, so
        // the right edge spills outside the window with no horizontal
        // scroll. BrowserZoomEffect wraps the content in a GeometryReader
        // and compensates the inner frame to `bounds / scale` so layout is
        // computed against the smaller pixel space, then scales the result
        // back up. Table's column auto-sizing and internal NSScrollView see
        // real, compensated bounds — both scroll axes work, columns
        // compress instead of overflowing.
        //
        // At identity (1.0) we return the content untouched so SwiftUI
        // doesn't install a CATransform layer that would block scroll-wheel
        // hit testing on the Table's NSScrollView.
        .modifier(BrowserZoomEffect(scale: uiFontScale))
        .onChange(of: app.hasCompletedFirstSync, initial: true) { _, completed in
            guard completed else { return }
            if presentation == .window, lockedIdealHeight == nil {
                let target = computeIdealContentHeight()
                lockedIdealHeight = target
                resizeWindowHeight(to: target)
            }
            // Hand the Table first-responder status so arrow keys engage
            // without a prior mouse click (issue #26). Deferred by a
            // run-loop tick so the Table has been mounted by the time we
            // set focus on it.
            DispatchQueue.main.async {
                isInboxFocused = true
            }
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

            // Clamp against the screen the window currently lives on (falling
            // back to main, then to the current frame as a no-op). Without
            // this, a remembered position near the screen bottom would push
            // the resized window's bottom edge off-screen — see #29.
            let visibleFrame =
                window.screen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? currentFrame
            let newFrame = WindowResizeClamp.clampedFrame(
                currentFrame: currentFrame,
                targetFrameHeight: targetFrame.height,
                visibleFrame: visibleFrame
            )

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
            reviewRequestedPRCount: app.reviewSection.count,
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
                    .padding(.leading, 6)
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

    /// Shown in place of an empty list when the active namespace returned no
    /// results because the token can't access it (e.g. unauthorized SSO org).
    private func restrictionContent(_ restriction: AccessRestriction) -> some View {
        ContentUnavailableView {
            Label(restriction.title(owner: ownerName), systemImage: "lock.shield")
        } description: {
            Text(restriction.detail(owner: ownerName))
        } actions: {
            if let url = restriction.authorizationURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Authorize Access", systemImage: "checkmark.shield")
                }
            }
            Button {
                Task { await app.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(app.isLoading)
        }
    }

    private func bannerText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
    }

    private var ownerName: String {
        app.activeNamespace?.owner ?? "this account"
    }

    private var isInboxEmpty: Bool {
        authoredPRs.isEmpty && reviewSection.isEmpty && assignedIssues.isEmpty
    }

    private var restrictionDisplay: RestrictionDisplay {
        Self.shouldShowRestriction(
            kind: app.activeNamespace?.kind,
            restriction: app.accessRestriction,
            inboxEmpty: isInboxEmpty
        )
    }

    // MARK: - List

    private var inboxList: some View {
        Table(of: InboxItem.self, selection: $selection) {
            TableColumn("Status") { item in
                StatusPill(text: item.statusText, color: item.statusColor)
            }
            .width(min: 110, ideal: 130, max: 170)

            TableColumn("Title") { item in
                HStack(spacing: 6) {
                    Text(item.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if item.isDraftPR {
                        DraftBadge()
                    }
                }
                .help(item.title)
            }
            // No max: Title absorbs leftover horizontal space (e.g. when zoomed in).
            .width(min: 100, ideal: 280)

            TableColumn("Author") { item in
                Text(item.author)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80, max: 130)

            TableColumn("Repo") { item in
                Text(repoShortName(item.repository))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120, max: 200)

            TableColumn("Link") { item in
                HStack {
                    Spacer(minLength: 0)
                    Link("#\(item.number)", destination: item.url)
                        .pointerStyle(.link)
                        .font(.callout)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .width(min: 48, ideal: 56, max: 70)
        } rows: {
            Section {
                ForEach(authoredItems) { item in
                    TableRow(item)
                        .contextMenu { linkContextMenu(url: item.url) }
                }
            } header: {
                SectionHeader(title: "Your PRs", count: authoredPRs.count)
            }

            Section {
                ForEach(reviewItems) { item in
                    TableRow(item)
                        .contextMenu { linkContextMenu(url: item.url) }
                }
            } header: {
                SectionHeader(title: "Awaiting your review", count: reviewSection.count)
            }

            Section {
                ForEach(issueItems) { item in
                    TableRow(item)
                        .contextMenu { linkContextMenu(url: item.url) }
                }
            } header: {
                SectionHeader(title: "Assigned issues", count: assignedIssues.count)
            }
        }
        .focused($isInboxFocused)
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
        + reviewSection.map { .pr($0.id) }
        + assignedIssues.map { .issue($0.id) }
    }

    // MARK: - Table input rows

    private var authoredItems: [InboxItem] {
        authoredPRs.map(InboxItem.authoredPR)
    }

    private var reviewItems: [InboxItem] {
        reviewSection.map(InboxItem.reviewPR)
    }

    private var issueItems: [InboxItem] {
        assignedIssues.map { InboxItem.issue($0, viewerLogin: viewerLogin) }
    }

    // MARK: - Derived data

    private var authoredPRs: [PullRequest] {
        app.snapshot?.authoredPRs ?? []
    }

    private var reviewSection: [ReviewInboxPR] {
        app.reviewSection
    }

    private var assignedIssues: [Issue] {
        app.snapshot?.assignedIssues ?? []
    }

    private var viewerLogin: String? {
        app.activeNamespace?.accountLogin
    }

    // MARK: - Row context menu

    @ViewBuilder
    private func linkContextMenu(url: URL) -> some View {
        Button("Open in Browser") { openURL(url) }
        Button("Copy Link") {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url.absoluteString, forType: .string)
        }
        Divider()
        ShareLink(item: url)
    }

    // MARK: - Selection helpers

    // MARK: - Browser-style zoom modifier

    /// Browser-style zoom: lay content out against a frame of `bounds / scale`,
    /// then scale the rendered output back up. This way Table's column
    /// auto-sizing and the internal NSScrollView see real, compensated layout
    /// bounds — columns compress instead of overflowing off-screen, and both
    /// scroll axes work.
    ///
    /// At identity (1.0) we return the content untouched. SwiftUI's
    /// `.scaleEffect(1.0, …)` still installs a CATransform layer that
    /// interferes with scroll-wheel hit testing on the `NSScrollView` backing
    /// `Table`, so the identity passthrough is load-bearing for default zoom.
    private struct BrowserZoomEffect: ViewModifier {
        let scale: CGFloat

        func body(content: Content) -> some View {
            if abs(scale - 1.0) < 0.001 {
                content
            } else {
                GeometryReader { proxy in
                    content
                        .frame(
                            width: proxy.size.width / scale,
                            height: proxy.size.height / scale
                        )
                        .scaleEffect(scale, anchor: .topLeading)
                }
            }
        }
    }

    private func openSelection() {
        guard let selection else { return }
        switch selection {
        case .pr(let id):
            let reviewPRs = reviewSection.map(\.pullRequest)
            if let pr = (authoredPRs + reviewPRs).first(where: { $0.id == id }) {
                openURL(pr.url)
            }
        case .issue(let id):
            if let issue = assignedIssues.first(where: { $0.id == id }) {
                openURL(issue.url)
            }
        }
    }
}
