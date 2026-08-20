import Testing
import CoreGraphics
@testable import Seamly

/// The one formula the whole Paper direction rests on. A margin marker and the rule on the
/// sheet must land on the same row, or "findability lives in the margin" stops being true —
/// so the arithmetic lives here, in one place, tested without a view.
struct CaptureGeometryTests {

    /// 400 pt wide, 800 pt tall viewport, onto a 1000 × 10 000 px capture (aspect 10).
    private func geometry(zoom: CGFloat = 1, scrollY: CGFloat = 0) -> CaptureGeometry {
        CaptureGeometry(
            sheetWidth: 400,
            viewportHeight: 800,
            captureSize: CGSize(width: 1000, height: 10_000),
            zoom: zoom,
            scrollY: scrollY
        )
    }

    @Test func oneTimesZoomFillsTheWidthAtNaturalAspect() {
        // NOT "shrink 10 000 px until it fits" — at that size nothing in it is legible.
        #expect(geometry().contentHeight == 4000)
        #expect(geometry(zoom: 3).contentHeight == 12_000)
    }

    @Test func aMarkSitsAtItsFractionOfTheContent() {
        #expect(geometry().y(atPct: 0) == 0)
        #expect(geometry().y(atPct: 0.5) == 2000)
        #expect(geometry().y(atPct: 1) == 4000)
    }

    @Test func scrollingMovesEveryMarkByTheSameAmount() {
        let g = geometry(scrollY: 500)
        #expect(g.y(atPct: 0) == -500)
        #expect(g.y(atPct: 0.5) == 1500)
    }

    @Test func zoomingScalesPositionAndScrollTogether() {
        let g = geometry(zoom: 3, scrollY: 600)
        // #expect over a bare `literal - literal` on the RHS of `==` against a CGFloat
        // mis-evaluates under this toolchain's macro expansion — bind it first, as with
        // the project's other #expect/rethrows gotcha (see CLAUDE.md, "Gotchas").
        let expected: CGFloat = 6000 - 600
        #expect(g.y(atPct: 0.5) == expected)
    }

    @Test func visibilityAllowsALittleSlackSoAMarkerFadesRatherThanPops() {
        let g = geometry(scrollY: 0)
        #expect(g.isVisible(0))
        #expect(g.isVisible(800))
        #expect(g.isVisible(-10))
        #expect(!g.isVisible(-40))
        #expect(!g.isVisible(900))
    }

    @Test func theViewportBracketDescribesWhereWeAreInTheWholeCapture() {
        let g = geometry(scrollY: 1000)
        #expect(abs(g.viewportTopPct - 0.25) < 1e-9)   // 1000 / 4000
        #expect(abs(g.viewportPct - 0.20) < 1e-9)      //  800 / 4000
    }

    @Test func jumpingPutsTheMarkWhereItWasAskedFor() {
        let g = geometry(zoom: 3)
        // atPct 0.5 is at 6000; put it 40% of the way down an 800 pt viewport.
        let expected: CGFloat = 6000 - 320
        #expect(g.scrollY(toShow: 0.5, at: 0.4) == expected)
    }

    @Test func jumpingNeverScrollsPastEitherEnd() {
        let g = geometry(zoom: 3)
        #expect(g.scrollY(toShow: 0, at: 0.4) == 0)
        #expect(g.scrollY(toShow: 1, at: 0.4) == g.maxScrollY)
        let expectedMaxScrollY: CGFloat = 12_000 - 800
        #expect(g.maxScrollY == expectedMaxScrollY)
    }

    @Test func scrubbingTheScaleReadsBackAsAFraction() {
        let g = geometry()
        #expect(abs(g.pct(forViewportY: 0) - 0) < 1e-9)
        #expect(abs(g.pct(forViewportY: 400) - 0.5) < 1e-9)
        #expect(abs(g.pct(forViewportY: 800) - 1) < 1e-9)
    }

    /// A capture shorter than the viewport, and a degenerate zero-width sheet, must not
    /// divide by zero or hand back a negative scroll extent.
    @Test func degenerateSizesStayFinite() {
        let tiny = CaptureGeometry(
            sheetWidth: 400, viewportHeight: 800,
            captureSize: CGSize(width: 1000, height: 100), zoom: 1, scrollY: 0
        )
        #expect(tiny.maxScrollY == 0)
        #expect(tiny.scrollY(toShow: 1, at: 0.4) == 0)

        let empty = CaptureGeometry(
            sheetWidth: 0, viewportHeight: 0,
            captureSize: .zero, zoom: 1, scrollY: 0
        )
        #expect(empty.contentHeight == 0)
        #expect(empty.viewportTopPct == 0)
        #expect(empty.viewportPct == 1)
        #expect(empty.pct(forViewportY: 10) == 0)
    }
}
