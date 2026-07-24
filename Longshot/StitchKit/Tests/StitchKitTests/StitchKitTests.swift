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

@Test func orderAssumedMissingKeyDecodesFalse() throws {
    // A manifest written before this field existed must decode, defaulting to false.
    let json = #"{"id":"\#(UUID().uuidString)","createdAt":"1970-01-01T00:00:00Z","status":"complete","deviceScale":1,"orientation":"portrait","keyframes":[],"seams":[],"segmentBreaks":[]}"#
    let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
    let s = try d.decode(StitchSession.self, from: Data(json.utf8))
    #expect(s.orderAssumed == false)
}
