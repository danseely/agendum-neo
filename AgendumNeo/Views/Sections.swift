import SwiftUI

struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Text("(\(count))")
                .foregroundStyle(.secondary)
        }
        .font(.headline)
    }
}
