import Foundation

enum SyncStatusLabel {
    static func text(synced: Date, now: Date) -> String {
        let minutes = Calendar.current.dateComponents([.minute], from: synced, to: now).minute ?? 0
        if minutes < 1 {
            return "Synced just now"
        } else if minutes == 1 {
            return "Synced 1 minute ago"
        } else {
            return "Synced \(minutes) minutes ago"
        }
    }
}
