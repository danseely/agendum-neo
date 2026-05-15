import SwiftUI

@main
struct AgendumNeoApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup("Agendum Neo") {
            RootView(presentation: .window)
                .environment(app)
                .task { await app.bootstrap() }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Refresh") {
                    Task { await app.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        MenuBarExtra {
            RootView(presentation: .menuBar)
                .environment(app)
                .task { await app.bootstrap() }
        } label: {
            Image(systemName: "checklist")
        }
        .menuBarExtraStyle(.window)
    }
}
