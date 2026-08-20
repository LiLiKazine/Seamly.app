import CoreGraphics

/// Where anything sits on, or beside, a capture on screen.
///
/// The Paper direction's one real weakness is that a thin rule over white captured content is
/// easy to miss, so findability moves to the margin — which only works if the margin marker and
/// the rule on the sheet land on the same row. That alignment is the whole point, so the
/// arithmetic is one function in one place rather than two similar expressions in two views.
///
/// On screen a mark is at `atPct * contentHeight - scrollY`. The kit writes this as
/// `atPct * zoom - top` in units of the sheet's own height, which is correct for a mock whose
/// sheet crops the image; a real 1:40 capture needs the capture's own height in the term.
///
/// `nonisolated` because this app target defaults new declarations to `@MainActor`, and
/// coordinate arithmetic has no business being pinned to an actor.
nonisolated struct CaptureGeometry: Equatable {
    let sheetWidth: CGFloat
    let viewportHeight: CGFloat
    /// The whole capture, in source pixels.
    let captureSize: CGSize
    let zoom: CGFloat
    let scrollY: CGFloat

    init(sheetWidth: CGFloat, viewportHeight: CGFloat, captureSize: CGSize, zoom: CGFloat, scrollY: CGFloat) {
        self.sheetWidth = max(0, sheetWidth)
        self.viewportHeight = max(0, viewportHeight)
        self.captureSize = captureSize
        self.zoom = max(zoom, 0.001)
        self.scrollY = scrollY
    }

    /// `zoom == 1` means *fill the sheet's width at natural aspect and scroll down* — not
    /// *shrink 15 000 px until all of it fits*, at which size nothing in it is legible.
    var contentHeight: CGFloat {
        guard captureSize.width > 0 else { return 0 }
        return sheetWidth * zoom * (captureSize.height / captureSize.width)
    }

    var maxScrollY: CGFloat { max(0, contentHeight - viewportHeight) }

    /// The screen Y of a mark at `atPct` down the whole capture.
    func y(atPct: Double) -> CGFloat { CGFloat(atPct) * contentHeight - scrollY }

    /// Slack, so a marker leaving the viewport fades out one step past the edge rather than
    /// vanishing exactly at it.
    func isVisible(_ y: CGFloat, slack: CGFloat = 24) -> Bool {
        y >= -slack && y <= viewportHeight + slack
    }

    /// Where the viewport's top edge sits in the whole capture, for the position scale.
    var viewportTopPct: Double {
        guard contentHeight > 0 else { return 0 }
        return Double(scrollY / contentHeight)
    }

    /// How much of the whole capture the viewport covers.
    var viewportPct: Double {
        guard contentHeight > 0 else { return 1 }
        return Double(min(1, viewportHeight / contentHeight))
    }

    /// The scroll offset that puts `atPct` `fraction` of the way down the viewport, clamped so
    /// a jump never asks for a position past either end.
    func scrollY(toShow atPct: Double, at fraction: CGFloat) -> CGFloat {
        let target = CGFloat(atPct) * contentHeight - viewportHeight * fraction
        return min(max(0, target), maxScrollY)
    }

    /// The inverse, for scrubbing the position scale.
    func pct(forViewportY y: CGFloat) -> Double {
        guard viewportHeight > 0 else { return 0 }
        return Double(min(max(0, y / viewportHeight), 1))
    }
}
