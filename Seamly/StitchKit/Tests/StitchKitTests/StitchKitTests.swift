import Foundation
import Testing
@testable import StitchKit

@Test func packageBuilds() {
    // Smoke test: the package compiles and the test target links against it.
    #expect(Bool(true))
}

@Test func orderAssumedDefaultsFalseAndRoundTrips() throws {
    var s = StitchSession(createdAt: Date(timeIntervalSince1970: 0), deviceScale: 1, orientation: .portrait)
    #expect(s.orderAssumed == false)
    s.orderAssumed = true
    let data = try JSONEncoder().encode(s)
    let back = try JSONDecoder().decode(StitchSession.self, from: data)
    #expect(back.orderAssumed == true)
}
