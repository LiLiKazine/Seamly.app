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
    @State private var dragStart: Int?
    @State private var zoom = ZoomState()
    @State private var loadError: String?
    @State private var busy = false

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
    /// Shared by both halves. The upper window shows rows *above* `upperContentBottom`, which in
    /// the real strip come from the previous frame — identical content, since that is what overlap
    /// means. The lower window shows rows from `lowerSourceStart` down. The one thing that would
    /// differ in either direction is that frame's *own* bar — top for the upper frame, bottom for
    /// the lower — and neither window can reach it: each is clipped to at most half the screen,
    /// which is at most a few hundred source pixels at 1×, while a frame is thousands tall, and
    /// zooming only narrows the window further. (`JoinAlignment.lowerPixelHeight`'s doc comment
    /// says the strip keeps the lower frame's bottom chrome, which is only true when that frame is
    /// the segment's last — but this view never gets close enough to that row for it to matter.)
    private func window(_ image: CGImage, width: CGFloat, offsetY: CGFloat, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: width, height: width * CGFloat(image.height) / CGFloat(max(image.width, 1)))
                .offset(y: offsetY)
        }
        .frame(width: size.width, height: max(size.height, 0), alignment: .topLeading)
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
            .onChanged { value in
                guard var alignment, let join = currentJoin else { return }
                let start = dragStart ?? alignment.dy
                dragStart = start
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
            .onEnded { _ in dragStart = nil }
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
            // `model.joinFrames` reads through an independent `Task.detached`, which does not
            // observe this `.task(id: position)`'s cancellation — so a rapid chevron tap can
            // start a second load before this one's disk read finishes, and the two can then
            // complete in either order. Without this check, a slow, now-stale load landing after
            // a faster, newer one would silently overwrite the screen with the wrong join's
            // pixels while `position` already points elsewhere.
            guard join == currentJoin else { return }
            frames = loaded
            alignment = resolved
        } catch {
            guard join == currentJoin else { return }
            // The model logged the raw error; this is the sentence a person can read.
            loadError = CaptureCondition.message(for: error)
        }
    }

    private func commit() {
        guard !edited.isEmpty, let stored = session else { dismiss(); return }
        var session = stored
        busy = true
        Task {
            defer { busy = false }
            for (join, dy) in edited {
                guard let index = session.seams.firstIndex(where: { $0.fromIndex == join }) else { continue }
                session.seams[index].provisionalDy = dy
                // The user has now looked at this join with their own eyes. Leaving it flagged
                // would put "a join may not line up" back on the result screen over a join they
                // just lined up themselves. This also drops the flag's other meaning, a nonzero
                // horizontal component — which `Compositor` never applies, so nothing is lost but
                // the badge.
                session.seams[index].isLowConfidence = false
            }
            await model.update(session)
            dismiss()
        }
    }
}
