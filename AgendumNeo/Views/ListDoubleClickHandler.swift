import AppKit
import SwiftUI

struct ListDoubleClickHandler: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
        DispatchQueue.main.async {
            attachIfNeeded(from: nsView, coordinator: context.coordinator)
        }
    }

    private func attachIfNeeded(from probe: NSView, coordinator: Coordinator) {
        guard let root = probe.window?.contentView else { return }
        guard let table = firstTableView(in: root) else { return }
        guard table !== coordinator.installedOn else { return }
        table.action = nil
        table.target = coordinator
        table.doubleAction = #selector(Coordinator.invoke(_:))
        coordinator.installedOn = table
    }

    private func firstTableView(in view: NSView) -> NSTableView? {
        if let t = view as? NSTableView { return t }
        for sub in view.subviews {
            if let t = firstTableView(in: sub) { return t }
        }
        return nil
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        weak var installedOn: NSTableView?
        init(action: @escaping () -> Void) { self.action = action }
        @objc func invoke(_ sender: Any?) { action() }
    }
}
