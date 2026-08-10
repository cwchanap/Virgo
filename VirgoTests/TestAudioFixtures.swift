import Foundation

/// A temporary audio file created by `TestAudioFixtures.makeTemporaryAudioFile`,
/// exposing the file URL and a `cleanup()` that removes it. `cleanup()` is safe
/// to call after the file is already gone (e.g. when a parent-directory cleanup
/// ran first), so callers that clean up a whole directory may skip calling it.
struct TemporaryAudioFile {
    let url: URL
    private let remove: () -> Void

    init(url: URL, remove: @escaping () -> Void) {
        self.url = url
        self.remove = remove
    }

    func cleanup() { remove() }
}

/// Creates temporary audio files for tests that exercise file-backed song
/// deletion paths. Each call writes a file at
/// `<parent>/virgo-test-<label>-<UUID>.<ext>` and returns its URL plus a
/// `cleanup()` that removes the file.
enum TestAudioFixtures {
    static func makeTemporaryAudioFile(
        in parent: URL = FileManager.default.temporaryDirectory,
        label: String,
        extension ext: String,
        contents: Data
    ) throws -> TemporaryAudioFile {
        let url = parent.appendingPathComponent("virgo-test-\(label)-\(UUID().uuidString).\(ext)")
        try contents.write(to: url)
        return TemporaryAudioFile(url: url, remove: { try? FileManager.default.removeItem(at: url) })
    }
}
