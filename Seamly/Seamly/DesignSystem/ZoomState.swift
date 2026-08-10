import CoreGraphics

/// Pinch-zoom that accumulates across gestures.
///
/// `MagnifyGesture.magnification` is relative to the *start of the current gesture*, so
/// assigning it to the scale directly resets the zoom every time the user lifts their
/// fingers. The committed scale is multiplied by the in-flight magnification instead, and
/// only the clamped product is banked on `end()` — otherwise a hard pinch would store a
/// scale far outside the range and the next gesture would start from it.
///
/// `nonisolated` because this app target defaults new declarations to `@MainActor`
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`); without it this type — and everything
/// below that touches it — would only be usable from the main actor, defeating the point.
nonisolated struct ZoomState: Equatable {
    static let minScale: CGFloat = 1
    static let maxScale: CGFloat = 6

    private var committed: CGFloat = ZoomState.minScale
    private var gesture: CGFloat = 1

    var scale: CGFloat { Self.clamp(committed * gesture) }

    mutating func update(magnification: CGFloat) {
        gesture = magnification
    }

    mutating func end() {
        committed = Self.clamp(committed * gesture)
        gesture = 1
    }

    mutating func reset() {
        committed = Self.minScale
        gesture = 1
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }
}
