import SwiftUI
import PhotosUI
import CoreGraphics
import ImageIO

/// Picking a source and watching it come in.
///
/// **The two phases are deliberately different.** Reading a recording has a real percentage.
/// Stitching does not — the work is data-dependent and finishes when the seams are found — so
/// it runs indeterminate and says so in words. A bar there would be a lie about how far along
/// the work is, which is why `ProgressNote` takes an optional value at all.
struct ImportSheet: View {
    enum Source { case video, photos }

    let source: Source
    let model: CaptureModel
    let onClose: () -> Void

    @State private var videoSelection: PhotosPickerItem?
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var pickError: String?
    @State private var started = false
    /// True for the WHOLE of a pick, from the tap to the import returning.
    ///
    /// `CaptureModel`'s two published flags do not cover the whole job, and inferring "finished"
    /// from their absence claimed success before the work began: `importPhotos` never sets
    /// `importProgress` at all, and neither flag is up during `MediaImporter.write`. So picking
    /// six screenshots showed a green "✓ Stitched." with a Done button for the entire decode and
    /// write, then flipped back to "Stitching…". A false success is the one thing this app's
    /// error handling exists to prevent — it cannot be a gap between two other flags.
    @State private var running = false

    private var isVideo: Bool { source == .video }
    private var reading: Double? { model.importProgress }
    private var stitching: Bool { model.isAssemblingNewArrival }
    private var working: Bool { running || reading != nil || stitching }

    var body: some View {
        SheetChrome(title: isVideo ? "From Video" : "From Photos") {
            if working { SeamlyButton("Cancel", variant: .plain, size: .small, action: onClose) }
        } trailing: {
            if !working && started { SeamlyButton("Done", variant: .plain, size: .small, action: onClose) }
        } content: {
            VStack(alignment: .leading, spacing: SeamlySpace.s5) {
                if let message = model.importError ?? pickError {
                    failure(message)
                } else if working {
                    progress
                } else if started {
                    finished
                } else {
                    picker
                }
            }
            .padding(.horizontal, SeamlySpace.gutterCompact)
            .padding(.top, SeamlySpace.s6)
            .padding(.bottom, SeamlySpace.s8)
        }
        .onChange(of: videoSelection) { _, item in
            guard let item else { return }
            Task { await loadVideo(item) }
        }
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPhotos(items) }
        }
    }

    // MARK: - States

    private var picker: some View {
        Group {
            if isVideo {
                PhotosPicker(selection: $videoSelection, matching: .videos) {
                    importLabel(symbol: "film", title: "Choose a screen recording",
                                detail: "Only the frames that moved are kept")
                }
            } else {
                PhotosPicker(selection: $photoSelection, maxSelectionCount: 20, matching: .images) {
                    importLabel(symbol: "photo.on.rectangle", title: "Choose overlapping screenshots",
                                detail: "Pick at least two")
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: SeamlySpace.s5) {
            ProgressNote(label: reading != nil ? "Reading video…" : "Stitching…", value: reading)
            Text(reading != nil
                 ? "Decoding the recording into keyframes. Only frames that moved are kept."
                 : "Matching each frame against the last. This has no percentage — it finishes when the seams are found.")
                .font(SeamlyFont.footnote)
                .foregroundStyle(SeamlyColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var finished: some View {
        HStack(spacing: SeamlySpace.s3) {
            Image(systemName: "checkmark").foregroundStyle(SeamlyColor.markOK)
            Text("Stitched.").font(SeamlyFont.body).foregroundStyle(SeamlyColor.ink)
        }
    }

    /// Non-accusatory, and it asks rather than blames. The message already came through
    /// `CaptureCondition.message(for:)`; the raw error is in `Diagnostics`.
    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: SeamlySpace.s5) {
            Text(message)
                .font(SeamlyFont.footnote)
                .foregroundStyle(SeamlyColor.markError)
                .fixedSize(horizontal: false, vertical: true)
                .padding(SeamlySpace.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SeamlyColor.washError)
                .seamlyCorners(SeamlyRadius.xs)
            HStack(spacing: SeamlySpace.s4) {
                SeamlyButton("Cancel", variant: .outline, action: onClose)
                    .frame(maxWidth: .infinity)
                SeamlyButton("Try again") {
                    model.clearImportError()
                    pickError = nil
                    started = false
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // `nonisolated` against the usual rule for views: `PhotosPicker`'s `label:` closure is not
    // MainActor-isolated, so a main-actor-isolated helper called from inside it fails Sendability
    // under Swift 6. Every token it touches is already `nonisolated`, so nothing is lost.
    nonisolated private func importLabel(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: SeamlySpace.s4) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(SeamlyColor.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(SeamlyFont.headline).foregroundStyle(SeamlyColor.ink)
                Text(detail).font(SeamlyFont.caption).foregroundStyle(SeamlyColor.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    // MARK: - Picking

    private func loadVideo(_ item: PhotosPickerItem) async {
        pickError = nil
        // Clear up front, not on the success branch: `PhotosPickerItem` is `Equatable` and
        // `.onChange` only fires on a *change*, so a selection still standing when we return
        // makes re-picking the same video a no-op and the row looks dead.
        videoSelection = nil
        started = true
        running = true
        defer { running = false }
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                pickError = "That video couldn't be read."
                return
            }
            await model.importVideo(movie.url)
        } catch {
            pickError = CaptureCondition.message(for: error)
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        pickError = nil
        photoSelection = []
        started = true
        running = true
        defer { running = false }
        var images: [CGImage] = []
        for (i, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    pickError = "Couldn't read photo \(i + 1)."
                    return
                }
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    pickError = "Photo \(i + 1) isn't a decodable image."
                    return
                }
                images.append(image)
            } catch {
                pickError = CaptureCondition.message(for: error)
                return
            }
        }
        guard images.count >= 2 else {
            pickError = "Pick at least two overlapping screenshots."
            return
        }
        await model.importPhotos(images)
    }
}

extension ImportSheet.Source: Identifiable {
    var id: String { self == .video ? "video" : "photos" }
}
