import Testing
import Foundation
import AVFoundation
@testable import Virgo

private struct LoaderCountWaiter {
    let count: Int
    let continuation: CheckedContinuation<Void, Never>
}

@MainActor
final class ControlledPlayerLoader {
    private var pending: [String: [CheckedContinuation<AVAudioPlayer, Error>]] = [:]
    private var requestWaiters: [String: [LoaderCountWaiter]] = [:]
    private var settlementCounts: [String: Int] = [:]
    private var settlementWaiters: [String: [LoaderCountWaiter]] = [:]
    private(set) var requests: [String] = []

    func load(_ url: URL) async throws -> AVAudioPlayer {
        let key = url.standardizedFileURL.path
        requests.append(key)
        resumeSatisfiedRequestWaiters(for: key)
        defer {
            // Run after this MainActor task returns from `load`, so its caller
            // completes the synchronous post-load success/error path first.
            Task { @MainActor in
                self.recordSettlement(for: key)
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending[key, default: []].append(continuation)
        }
    }

    func waitForRequest(path: String, count: Int = 1) async {
        let key = canonical(path)
        if requestCount(for: key) >= count { return }

        await withCheckedContinuation { continuation in
            if requestCount(for: key) >= count {
                continuation.resume()
            } else {
                requestWaiters[key, default: []].append(
                    LoaderCountWaiter(count: count, continuation: continuation)
                )
            }
        }
    }

    func succeed(path: String, player: AVAudioPlayer) async {
        let key = canonical(path)
        let settlementCount = nextSettlementCount(for: key)
        guard let continuation = takePendingContinuation(path: path) else { return }
        continuation.resume(returning: player)
        await waitForSettlement(path: key, count: settlementCount)
    }

    func fail(path: String, error: Error) async {
        let key = canonical(path)
        let settlementCount = nextSettlementCount(for: key)
        guard let continuation = takePendingContinuation(path: path) else { return }
        continuation.resume(throwing: error)
        await waitForSettlement(path: key, count: settlementCount)
    }

    private func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func requestCount(for key: String) -> Int {
        requests.lazy.filter { $0 == key }.count
    }

    private func nextSettlementCount(for key: String) -> Int {
        (settlementCounts[key] ?? 0) + 1
    }

    private func resumeSatisfiedRequestWaiters(for key: String) {
        let count = requestCount(for: key)
        resumeWaiters(
            requestWaiters.removeValue(forKey: key) ?? [],
            for: key,
            count: count,
            in: &requestWaiters
        )
    }

    private func waitForSettlement(path: String, count: Int) async {
        let key = canonical(path)
        if (settlementCounts[key] ?? 0) >= count { return }

        await withCheckedContinuation { continuation in
            if (settlementCounts[key] ?? 0) >= count {
                continuation.resume()
            } else {
                settlementWaiters[key, default: []].append(
                    LoaderCountWaiter(count: count, continuation: continuation)
                )
            }
        }
    }

    private func recordSettlement(for key: String) {
        let count = (settlementCounts[key] ?? 0) + 1
        settlementCounts[key] = count
        resumeWaiters(
            settlementWaiters.removeValue(forKey: key) ?? [],
            for: key,
            count: count,
            in: &settlementWaiters
        )
    }

    private func resumeWaiters(
        _ registered: [LoaderCountWaiter],
        for key: String,
        count: Int,
        in waiters: inout [String: [LoaderCountWaiter]]
    ) {
        var remaining: [LoaderCountWaiter] = []

        for waiter in registered {
            if count >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }

        if !remaining.isEmpty {
            waiters[key] = remaining
        }
    }

    private func takePendingContinuation(
        path: String
    ) -> CheckedContinuation<AVAudioPlayer, Error>? {
        let key = canonical(path)
        guard var queue = pending[key], !queue.isEmpty else {
            Issue.record("No pending preview load for \(key)")
            return nil
        }

        let continuation = queue.removeFirst()
        if queue.isEmpty {
            pending.removeValue(forKey: key)
        } else {
            pending[key] = queue
        }
        return continuation
    }
}

enum TestError: Error {
    case loadFailed
}

@MainActor
private final class FailureObserver {
    var didEnterErrorPath = false
}

extension AudioPlaybackServiceTests {
    @Test("loader settlement prevents stale-state assertions after a successful resolution")
    func loaderSettlementPreventsStaleStateAssertionsAfterSuccess() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let previewPath = "/tmp/virgo-controlled-load-\(UUID().uuidString).wav"
            let song = Song(
                title: "Settled",
                artist: "Test Artist",
                bpm: 120.0,
                duration: "1:00",
                genre: "DTX Import",
                previewFilePath: previewPath
            )
            TestContainer.shared.context.insert(song)
            let player = try makeSettlementPlayer()

            service.playPreview(for: song)
            await loader.waitForRequest(path: previewPath)
            await loader.succeed(path: previewPath, player: player)

            #expect(service.currentlyPlaying == song.id)
        }
    }

    @Test("loader failure settlement waits for the resumed caller to enter its error path")
    func loaderFailureSettlementWaitsForErrorPath() async {
        let loader = ControlledPlayerLoader()
        let observer = FailureObserver()
        let previewPath = "/tmp/virgo-controlled-load-\(UUID().uuidString).wav"
        let loadTask = Task { @MainActor in
            do {
                _ = try await loader.load(URL(fileURLWithPath: previewPath))
            } catch {
                observer.didEnterErrorPath = true
            }
        }

        await loader.waitForRequest(path: previewPath)
        await loader.fail(path: previewPath, error: TestError.loadFailed)

        #expect(observer.didEnterErrorPath)
        await loadTask.value
    }

    private func makeSettlementPlayer() throws -> AVAudioPlayer {
        let sampleRate: UInt32 = 8_000
        let sampleCount: UInt32 = 800
        let dataSize = sampleCount * 2
        var data = Data()

        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }

        data.append("RIFF".data(using: .ascii)!)
        append(UInt32(36) + dataSize)
        data.append("WAVEfmt ".data(using: .ascii)!)
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(sampleRate)
        append(sampleRate * 2)
        append(UInt16(2))
        append(UInt16(16))
        data.append("data".data(using: .ascii)!)
        append(dataSize)
        data.append(Data(repeating: 0, count: Int(dataSize)))
        return try AVAudioPlayer(data: data)
    }
}
