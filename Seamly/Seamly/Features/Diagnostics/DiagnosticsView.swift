import SwiftUI
import StitchKit

/// A read-only view onto the shared diagnostics log (extension + app), with one-tap Share/Copy so
/// a capture that misbehaves can be reported without a Mac attached. Reads the App Group log that
/// both `SampleHandler` (category `capture`) and `LibraryModel` (category `app`) write to.
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = "(loading…)"
    @State private var clearError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
                    Spacer()
                    Button("Reload", systemImage: "arrow.clockwise") { load() }
                    Spacer()
                    Button("Clear", systemImage: "trash", role: .destructive) { clear() }
                }
            }
            .task { load() }
            .alert("Couldn't clear log", isPresented: .constant(clearError != nil)) {
                Button("OK") { clearError = nil }
            } message: {
                Text(clearError ?? "")
            }
        }
    }

    private func load() {
        guard let container = AppGroup.containerURL else {
            text = "App Group unavailable — diagnostics can't be read on this build."
            return
        }
        text = Diagnostics.readAll(containerURL: container)
    }

    private func clear() {
        guard let container = AppGroup.containerURL else { return }
        do {
            try Diagnostics.clear(containerURL: container)
            load()
        } catch {
            clearError = error.localizedDescription
        }
    }
}
