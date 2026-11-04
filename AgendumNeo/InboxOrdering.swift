import Foundation

/// Display order applied to every inbox section.
///
/// Rows are grouped by repository: repos sort alphabetically by name
/// (case-insensitive, owner as the tiebreak), and rows keep their incoming
/// order within a repo. Pure so it can be unit-tested, and the place to add
/// further groupings later.
enum InboxOrdering {
    static func groupedByRepository<Item>(_ items: [Item], repository: (Item) -> String) -> [Item] {
        items.enumerated()
            .sorted { lhs, rhs in
                let left = repository(lhs.element)
                let right = repository(rhs.element)
                let byName = repoShortName(left).localizedCaseInsensitiveCompare(repoShortName(right))
                if byName != .orderedSame { return byName == .orderedAscending }
                let byFullName = left.localizedCaseInsensitiveCompare(right)
                if byFullName != .orderedSame { return byFullName == .orderedAscending }
                // Equal repos: keep the incoming order (Swift's sort isn't stable).
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
