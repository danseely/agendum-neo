import Testing
import Foundation
@testable import AgendumNeo

@Suite("Model")
struct ModelTests {

    @Test("Namespace id format")
    func namespaceIDFormat() {
        let ns = Namespace(
            host: "github.com",
            accountLogin: "danseely",
            owner: "adadaptedinc",
            kind: .org
        )
        #expect(ns.id == "github.com/danseely/adadaptedinc")
        #expect(ns.displayName == "adadaptedinc")
    }

    @Test("ReviewState round-trips through JSON")
    func reviewStateCodable() throws {
        let states: [ReviewState] = [.waiting, .approved, .changesRequested, .commented]
        let encoded = try JSONEncoder().encode(states)
        let decoded = try JSONDecoder().decode([ReviewState].self, from: encoded)
        #expect(decoded == states)
    }
}
