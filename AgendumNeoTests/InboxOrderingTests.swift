import Testing
@testable import AgendumNeo

@Suite("InboxOrdering")
struct InboxOrderingTests {

    private struct Row: Equatable {
        let id: String
        let repo: String
    }

    private func order(_ rows: [Row]) -> [String] {
        InboxOrdering.groupedByRepository(rows, repository: \.repo).map(\.id)
    }

    @Test("Repos sort alphabetically by name")
    func alphabetical() {
        let rows = [
            Row(id: "1", repo: "acme/zeta"),
            Row(id: "2", repo: "acme/alpha"),
            Row(id: "3", repo: "acme/mid"),
        ]
        #expect(order(rows) == ["2", "3", "1"])
    }

    @Test("Rows from one repo end up together, keeping their incoming order")
    func groupedAndStable() {
        let rows = [
            Row(id: "b1", repo: "acme/beta"),
            Row(id: "a1", repo: "acme/alpha"),
            Row(id: "b2", repo: "acme/beta"),
            Row(id: "a2", repo: "acme/alpha"),
            Row(id: "b3", repo: "acme/beta"),
        ]
        #expect(order(rows) == ["a1", "a2", "b1", "b2", "b3"])
    }

    @Test("Sorting ignores case")
    func caseInsensitive() {
        let rows = [
            Row(id: "1", repo: "acme/Zed"),
            Row(id: "2", repo: "acme/apple"),
            Row(id: "3", repo: "acme/Banana"),
        ]
        #expect(order(rows) == ["2", "3", "1"])
    }

    @Test("Repo name sorts before owner; owner breaks ties")
    func nameThenOwner() {
        let rows = [
            Row(id: "1", repo: "zeta-org/app"),
            Row(id: "2", repo: "alpha-org/web"),
            Row(id: "3", repo: "alpha-org/app"),
        ]
        #expect(order(rows) == ["3", "1", "2"])
    }

    @Test("Empty input stays empty")
    func empty() {
        #expect(order([]).isEmpty)
    }
}
