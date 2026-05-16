import SwiftUI

@main
struct AgendumNeoApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup("Agendum Neo") {
            RootView(presentation: .window)
                .environment(app)
                .environment(\.uiFontScale, app.uiFontScale)
                .task { await app.bootstrap() }
        }
        .windowToolbarStyle(.unified)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Refresh") {
                    Task { await app.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Zoom In") {
                    app.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(UIFontScale.isAtMaximum(app.uiFontScale))

                Button("Zoom Out") {
                    app.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(UIFontScale.isAtMinimum(app.uiFontScale))

                Button("Actual Size") {
                    app.resetZoom()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }

        MenuBarExtra {
            RootView(presentation: .menuBar)
                .environment(app)
                .environment(\.uiFontScale, app.uiFontScale)
                .task { await app.bootstrap() }
        } label: {
            Image(systemName: "checklist")
        }
        .menuBarExtraStyle(.window)
    }
}
