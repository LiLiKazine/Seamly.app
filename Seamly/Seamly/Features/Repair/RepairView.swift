import SwiftUI
import CoreGraphics
import StitchKit

/// Lining up one join, by dragging the lower half until the two halves meet.
///
/// The boundary is pinned to the middle of the screen and never moves; what moves is the lower
/// frame's content, tracking the finger one-to-one in displayed pixels. That is the entire
/// interaction. There is no offset field, no bar control, no per-join list, and nothing here says
/// "seam", "chrome" or "confidence" — the words the user reads all come from `CaptureCondition`.
///
/// Pinch is also the precision mechanism: at 1× a point is roughly three source pixels on this
/// hardware, so pixel-exact work needs magnification rather than a second, finer control. There is
/// deliberately **no panning** — one finger always means "line it up" — so at high zoom only the
/// middle of the frame's width is visible.
struct RepairView: View {
    let captureID: UUID
    let model: CaptureModel
    /// Where to start, from `RepairableJoins.opening(in:flaggedOnly:)`.
    let openingJoin: Int

    @Environment(\.dismiss) private var dismiss

    @State private var joins: [Int]
    @State private var position: Int
    @State private var frames: (upper: CGImage, lower: CGImage)?
    @State private var alignment: JoinAlignment?
    /// Offsets the user has changed, by join index. Empty means nothing to write.
    @State private var edited: [Int: Int] = [:]
    /// The offset this drag started from, so a cumulative translation maps to an absolute offset.
    /// `@GestureState`, not `@State`: SwiftUI resets it to `nil` automatically whenever the
    /// gesture ends *or is cancelled/interrupted* — a plain `@State` var cleared only in
    /// `onEnded` can't promise that (SwiftUI does not guarantee `onEnded` fires on every
    /// interruption), and a stale baseline would make the next drag jump by the previous drag's
    /// translation.
    @GestureState private var dragStart: Int?
    @State private var zoom = ZoomState()
    @State private var loadError: String?
    /// Set when `commit()`'s write fails or the capture it was writing to has vanished. Separate
    /// from `loadError`: a save failure shouldn't blank out the canvas the user was just looking
    /// at (and might retry Done against) the way a load failure blanks out an unloadable join.
    @State private var saveError: String?
    @State private var busy = false
    /// Bumped at the top of every `load()` call; a load only commits its result if this still
    /// matches when its `await` returns. Needed because `model.joinFrames` reads through an
    /// independent `Task.detached`, which does not observe `.task(id: position)`'s cancellation —
    /// so a slow load can resolve after a faster, later one. Comparing *tokens* rather than join
    /// indices matters here: paging away from a join and back to it is a legitimate way to reach
    /// the same join index twice, and a stale load for the first visit must not be allowed to
    /// overwrite state a fresh second visit (and a drag on top of it) already produced.
    @State private var loadToken = 0

    /// `joins`/`position` are seeded here, synchronously, rather than in a `.task`: both depend
    /// only on `model`/`captureID`, which are already available, so there is nothing to await.
    /// That leaves exactly one place that starts a load — `.task(id: position)` below — instead
    /// of two tasks racing over whether `joins` is populated yet. A separate seeding `.task`
    /// racing an id-keyed one is exactly the shape that strands this screen: the id-keyed task
    /// can run first, see an empty `joins`, bail out, and never re-fire once seeding finishes,
    /// because setting `position` to the same default value isn't a *change*.
    init(captureID: UUID, model: CaptureModel, openingJoin: Int) {
        self.captureID = captureID
        self.model = model
        self.openingJoin = openingJoin
        let session = model.captures.first { $0.id == captureID }?.session
        let walkable = session.map(RepairableJoins.walkable(in:)) ?? []
        _joins = State(initialValue: walkable)
        _position = State(initialValue: walkable.firstIndex(of: openingJoin) ?? 0)
    }

    private var session: StitchSession? {
        model.captures.first { $0.id == captureID }?.session
    }

    private var currentJoin: Int? {
        joins.indices.contains(position) ? joins[position] : nil
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(CaptureCondition.liningUpActionTitle)
                .navigationBarTitleDisplayMode(.inline)
                // The canvas behind this bar is black in both appearances (see `content`'s doc
                // comment) — a surface for judging pixel alignment, not something that should
                // follow the system's light/dark choice. Left to the system default, the title
                // (unlike `Cancel`/`Done`, which iOS 26 always renders in a legible dark capsule)
                // painted in the *system's* text color: white-on-black in dark mode, but
                // invisible black-on-black in light mode. Forcing the bar itself into the dark
                // color scheme makes its title (and any future bar content) render for the
                // content actually behind it, independent of the system appearance.
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.disabled(busy)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { commit() }.disabled(busy)
                    }
                }
                .safeAreaInset(edge: .bottom) { positionBar }
        }
        .task(id: position) { await load() }
        .alert(
            "Couldn't save",
            isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let loadError {
            ContentUnavailableView {
                Label("Can't show this join", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            }
        } else if let frames, let alignment {
            GeometryReader { viewport in
                halves(in: viewport.size, frames: frames, alignment: alignment)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(in: viewport.size, frames: frames))
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { zoom.update(magnification: $0.magnification) }
                            .onEnded { _ in withAnimation(.snappy) { zoom.end() } }
                    )
                    .accessibilityIdentifier("repair-canvas")
                    .accessibilityLabel("The two halves of this join")
                    .accessibilityHint("Drag up or down to line them up. Pinch to zoom in.")
            }
            .background(.black)
            .ignoresSafeArea(edges: .horizontal)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The upper frame's tail above a pinned boundary, the lower frame's head below it. Each half
    /// is a clipped window onto a full-resolution frame, offset so the right source row lands on
    /// the boundary — so what the user sees is exactly the placement `JoinAlignment` describes and
    /// `Compositor` will draw.
    private func halves(in size: CGSize, frames: (upper: CGImage, lower: CGImage), alignment: JoinAlignment) -> some View {
        let scale = pointsPerSourcePixel(in: size, frames: frames)
        let boundary = size.height / 2
        return VStack(spacing: 0) {
            window(
                frames.upper,
                width: size.width * zoom.scale,
                offsetY: boundary - CGFloat(alignment.upperContentBottom) * scale,
                size: CGSize(width: size.width, height: boundary)
            )
            window(
                frames.lower,
                width: size.width * zoom.scale,
                offsetY: -CGFloat(alignment.lowerSourceStart) * scale,
                size: CGSize(width: size.width, height: size.height - boundary)
            )
        }
    }

    /// A clipped window onto one frame, offset so a chosen source row lands where it belongs.
    ///
    /// Shared by both halves, but the two behave differently under a drag. The **upper** window's
    /// offset (`alignment.upperContentBottom`) never depends on `dy`, so it always shows the same
    /// fixed slice of the upper frame no matter where the join sits. Half a screen is on the order
    /// of a *thousand* source pixels at 1× on this hardware — roughly 1200, not "a few hundred" —
    /// but a frame is thousands of pixels tall, so that fixed slice sits well inside the frame's
    /// body, nowhere near its own top bar.
    ///
    /// The **lower** window's offset (`alignment.lowerSourceStart`) does move with `dy`, and near
    /// the low end of `JoinAlignment.dyRange` it approaches the lower frame's own content-bottom
    /// edge — so the lower window *can* show that frame's own bottom bar, and past it, black
    /// beyond the image's actual pixels. That is honest, not a bug: for the segment's last join,
    /// `Compositor.plan` draws exactly that. For an interior join dragged to that same extreme,
    /// the finished strip instead continues into the *next* frame down, which this preview — only
    /// ever showing the two frames either side of one join — has no way to draw. The discrepancy
    /// is confined to the last sliver of an already-degenerate drag position, not anything a
    /// normal "line it up" drag reaches.
    private func window(_ image: CGImage, width: CGFloat, offsetY: CGFloat, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: width, height: width * CGFloat(image.height) / CGFloat(max(image.width, 1)))
                .offset(y: offsetY)
        }
        // `.top`, not `.topLeading`: the image inside is `zoom.scale`× wider than this frame once
        // zoomed in, so whichever edge this aligns to is the *only* slice the user can see (there
        // is deliberately no panning to reach the rest). `.topLeading` showed the leftmost ~17% of
        // the frame's width at 6× and nothing else — `.top` centres the zoomed slice horizontally
        // while leaving the vertical placement, which `offsetY` already computes exactly, alone.
        .frame(width: size.width, height: max(size.height, 0), alignment: .top)
        .clipped()
    }

    /// Displayed points per source pixel at the current zoom.
    private func pointsPerSourcePixel(in size: CGSize, frames: (upper: CGImage, lower: CGImage)) -> CGFloat {
        size.width * zoom.scale / CGFloat(max(frames.upper.width, 1))
    }

    private func dragGesture(in size: CGSize, frames: (upper: CGImage, lower: CGImage)) -> some Gesture {
        // The 1× ratio; `JoinAlignment` divides by the zoom itself.
        let sourcePixelsPerPoint = CGFloat(frames.upper.width) / max(size.width, 1)
        return DragGesture(minimumDistance: 1)
            .updating($dragStart) { _, state, _ in
                // Captures the offset this drag began from, once, the first time this fires for a
                // fresh gesture. `onChanged` below still falls back to `alignment.dy` if this
                // hasn't landed yet for the very first event of a drag, so the relative firing
                // order between this closure and `onChanged` for the same event doesn't matter.
                if state == nil { state = alignment?.dy }
            }
            .onChanged { value in
                guard var alignment, let join = currentJoin else { return }
                let start = dragStart ?? alignment.dy
                let next = alignment.dy(
                    draggedBy: value.translation.height,
                    from: start,
                    sourcePixelsPerPoint: sourcePixelsPerPoint,
                    zoom: zoom.scale
                )
                alignment.setDy(next)
                self.alignment = alignment
                edited[join] = next
            }
    }

    /// Where the user is, not a menu of places to go: chevrons and a count, so a join we never
    /// flagged is still reachable without building a picker.
    @ViewBuilder
    private var positionBar: some View {
        if joins.count > 1 {
            HStack(spacing: 24) {
                Button {
                    position -= 1
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(position == 0 || busy)
                .accessibilityLabel("Previous join")

                Text("\(position + 1) of \(joins.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    position += 1
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(position >= joins.count - 1 || busy)
                .accessibilityLabel("Next join")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    /// The single load path, driven only by `.task(id: position)`. Every exit sets either
    /// `loadError` or (`frames` and `alignment`) together — never leaves the screen on the
    /// `ProgressView` fallback with nothing in flight to end it. That covers not just a missing
    /// pair of keyframes, but a capture that has vanished out from under this screen (deleted
    /// elsewhere) and a session with no walkable join at all, however unreachable that should be
    /// given `RepairableJoins.opening` gates whether this screen opens in the first place.
    private func load() async {
        loadToken += 1
        let token = loadToken
        guard let session else {
            loadError = CaptureCondition.message(for: CaptureModel.CaptureError.notFound)
            return
        }
        guard let join = currentJoin else {
            loadError = "There's nothing here to line up."
            return
        }
        loadError = nil
        zoom.reset()
        frames = nil
        var next = JoinAlignment(session: session, joinIndex: join)
        // Carry an unsaved edit across a move between joins, so paging away and back does not
        // silently discard the user's work.
        if let dy = edited[join] { next?.setDy(dy) }
        guard let resolved = next else {
            loadError = "This part of the capture is missing, so there's nothing to line up."
            return
        }
        do {
            let loaded = try await model.joinFrames(captureID, joinIndex: join)
            // See `loadToken`'s doc comment: a slow, now-stale load must not overwrite what a
            // newer load (or a drag on top of it) has already put on screen.
            guard token == loadToken else { return }
            frames = loaded
            alignment = resolved
        } catch {
            guard token == loadToken else { return }
            // The model logged the raw error; this is the sentence a person can read.
            loadError = CaptureCondition.message(for: error)
        }
    }

    private func commit() {
        guard !edited.isEmpty else { dismiss(); return }
        guard let stored = session else {
            // The capture disappeared out from under this screen (e.g. deleted elsewhere) while
            // edits were still pending. There is nothing left to write them to — unlike the
            // "nothing changed" case above, this drop is not silent: it reads like any other
            // failed save instead of the screen just vanishing.
            saveError = CaptureCondition.message(for: CaptureModel.CaptureError.notFound)
            return
        }
        var session = stored
        busy = true
        Task {
            defer { busy = false }
            for (join, dy) in edited {
                guard let index = session.seams.firstIndex(where: { $0.fromIndex == join }) else {
                    // Unreachable: `edited[join]` is only ever set by `dragGesture`, which
                    // requires a `JoinAlignment` to exist for `join`, and `JoinAlignment.init?`
                    // itself requires the matching seam to be present. If the seam is somehow
                    // missing anyway, skipping just this one join's edit is the least-bad response
                    // to manifest data this code did not expect to see — better than discarding
                    // every other edit in the same batch over it.
                    continue
                }
                session.seams[index].provisionalDy = dy
                // The user has now looked at this join with their own eyes. Leaving it flagged
                // would put "a join may not line up" back on the result screen over a join they
                // just lined up themselves. This also drops the flag's other meaning, a nonzero
                // horizontal component — which `Compositor` never applies, so nothing is lost but
                // the badge.
                session.seams[index].isLowConfidence = false
            }
            do {
                try await model.update(session)
                dismiss()
            } catch {
                // The model logged the raw error; this is the sentence a person can read. Staying
                // on screen (not dismissing) keeps `edited` intact so Done can be tried again —
                // the user must never be led to believe a repair saved when it didn't.
                saveError = CaptureCondition.message(for: error)
            }
        }
    }
}
