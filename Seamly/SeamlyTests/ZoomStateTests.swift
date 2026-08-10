import Testing
import CoreGraphics
@testable import Seamly

/// `MagnifyGesture.magnification` is relative to the start of the *current* gesture. The
/// harness UI assigned it directly, so lifting your fingers reset the zoom. These pin the
/// accumulating behaviour a tall-image viewer needs.
struct ZoomStateTests {

    @Test func startsUnzoomed() {
        #expect(ZoomState().scale == 1)
    }

    @Test func tracksMagnificationDuringAGesture() {
        var zoom = ZoomState()
        zoom.update(magnification: 2)
        #expect(zoom.scale == 2)
    }

    /// The regression: a second gesture must build on the first, not replace it.
    @Test func accumulatesAcrossGestures() {
        var zoom = ZoomState()
        zoom.update(magnification: 3)
        zoom.end()
        #expect(zoom.scale == 3)

        zoom.update(magnification: 1.5)
        #expect(zoom.scale == 4.5)
        zoom.end()
        #expect(zoom.scale == 4.5)
    }

    @Test func clampsToMaximum() {
        var zoom = ZoomState()
        zoom.update(magnification: 100)
        #expect(zoom.scale == ZoomState.maxScale)
        zoom.end()
        zoom.update(magnification: 100)
        #expect(zoom.scale == ZoomState.maxScale)
    }

    /// Pinching in past 1× must not let the image shrink below fit, and must not bank a
    /// sub-1 committed scale that a later gesture would multiply from.
    @Test func clampsToMinimum() {
        var zoom = ZoomState()
        zoom.update(magnification: 0.1)
        #expect(zoom.scale == ZoomState.minScale)
        zoom.end()
        zoom.update(magnification: 2)
        #expect(zoom.scale == 2)
    }

    @Test func resetReturnsToFit() {
        var zoom = ZoomState()
        zoom.update(magnification: 4)
        zoom.end()
        zoom.reset()
        #expect(zoom.scale == 1)
    }
}
