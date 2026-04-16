import Testing
import Foundation
import CoreMIDI
@testable import Virgo

@Suite("MIDIPreviewMonitor Tests", .serialized)
@MainActor
struct MIDIPreviewMonitorTests {
    final class StubMIDISourceIDResolver: MIDISourceIDResolving {
        var idsByUniqueID: [Int32: String]

        init(idsByUniqueID: [Int32: String] = [:]) {
            self.idsByUniqueID = idsByUniqueID
        }

        func stableSourceID(for uniqueID: Int32) -> String {
            idsByUniqueID[uniqueID] ?? "coremidi:\(uniqueID)"
        }
    }

    final class StubMIDIPreviewPacketListener: MIDIPreviewPacketListening {
        private var onPackets: ((UnsafePointer<MIDIPacketList>, Int32, String) -> Void)?
        private(set) var startCallCount = 0
        private(set) var stopCallCount = 0
        var startResult = true

        func start(_ onPackets: @escaping (UnsafePointer<MIDIPacketList>, Int32, String) -> Void) -> Bool {
            startCallCount += 1
            self.onPackets = onPackets
            return startResult
        }

        func stop() {
            stopCallCount += 1
            onPackets = nil
        }

        func emit(timestamp: UInt64, bytes: [UInt8], sourceUniqueID: Int32, sourceDisplayName: String) {
            withSinglePacketList(timestamp: timestamp, bytes: bytes) { packetList in
                onPackets?(packetList, sourceUniqueID, sourceDisplayName)
            }
        }

        private func withSinglePacketList(
            timestamp: UInt64,
            bytes: [UInt8],
            body: (UnsafePointer<MIDIPacketList>) -> Void
        ) {
            let bufferSize = MemoryLayout<MIDIPacketList>.size
            let buffer = UnsafeMutableRawPointer.allocate(
                byteCount: bufferSize,
                alignment: MemoryLayout<MIDIPacketList>.alignment
            )
            defer { buffer.deallocate() }

            let packetListPointer = buffer.bindMemory(to: MIDIPacketList.self, capacity: 1)
            let initialPacket = MIDIPacketListInit(packetListPointer)
            var mutableBytes = bytes
            guard MIDIPacketListAdd(
                packetListPointer,
                bufferSize,
                initialPacket,
                timestamp,
                mutableBytes.count,
                &mutableBytes
            ) != nil else {
                Issue.record("Failed to create MIDIPacketList for test input")
                return
            }

            body(UnsafePointer(packetListPointer))
        }
    }

    @Test("preview monitor forwards idle events into diagnostics")
    func previewMonitorForwardsIdleEventsIntoDiagnostics() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDIPreviewMonitorTests.previewMonitorForwardsIdleEventsIntoDiagnostics"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        settings.setSelectedMIDISource(id: "coremidi:2", displayName: "TD-17")
        settings.setMidiMapping(40, for: .snare)

        let diagnostics = MIDIDiagnosticsStore()
        let monitor = MIDIPreviewMonitor(
            eventRouter: MIDIEventRouter(),
            diagnosticsStore: diagnostics,
            settingsManager: settings
        )

        monitor.handle(
            packets: [.init(timestamp: 10, bytes: [0x99, 40, 120])],
            sourceID: "coremidi:2",
            sourceDisplayName: "TD-17"
        )

        #expect(diagnostics.lastEvent?.sourceID == "coremidi:2")
        #expect(diagnostics.lastEvent?.sourceDisplayName == "TD-17")
        #expect(diagnostics.lastEvent?.note == 40)
        #expect(diagnostics.lastEvent?.mappedDrumType == .snare)
    }

    @Test("start and stop delegate live preview listening through the injected listener")
    func startAndStopDelegateLivePreviewListening() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDIPreviewMonitorTests.startAndStopDelegateLivePreviewListening"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        settings.setMidiMapping(38, for: .snare)

        let diagnostics = MIDIDiagnosticsStore()
        let listener = StubMIDIPreviewPacketListener()
        let resolver = StubMIDISourceIDResolver(idsByUniqueID: [17: "coremidi:17"])
        let monitor = MIDIPreviewMonitor(
            diagnosticsStore: diagnostics,
            settingsManager: settings,
            sourceIDResolver: resolver,
            packetListener: listener
        )

        monitor.start()
        listener.emit(timestamp: 10, bytes: [0x99, 38, 100], sourceUniqueID: 17, sourceDisplayName: "TD-17")
        monitor.stop()

        #expect(listener.startCallCount == 1)
        #expect(listener.stopCallCount == 1)
        #expect(diagnostics.lastEvent?.sourceID == "coremidi:17")
        #expect(diagnostics.lastEvent?.sourceDisplayName == "TD-17")
        #expect(diagnostics.lastEvent?.note == 38)
        #expect(diagnostics.lastEvent?.mappedDrumType == .snare)
    }

    @Test("start reports injected listener startup failure")
    func startReportsInjectedListenerStartupFailure() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDIPreviewMonitorTests.startReportsInjectedListenerStartupFailure"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let diagnostics = MIDIDiagnosticsStore()
        let listener = StubMIDIPreviewPacketListener()
        listener.startResult = false
        let monitor = MIDIPreviewMonitor(
            diagnosticsStore: diagnostics,
            settingsManager: settings,
            packetListener: listener
        )

        let didStart = monitor.start()

        #expect(didStart == false)
        #expect(listener.startCallCount == 1)
    }

    @Test("preview monitor forwards decoded events through the optional callback")
    func previewMonitorForwardsDecodedEventsThroughTheOptionalCallback() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDIPreviewMonitorTests.previewMonitorForwardsDecodedEventsThroughTheOptionalCallback"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        settings.setMidiMapping(36, for: .kick)

        let diagnostics = MIDIDiagnosticsStore()
        let monitor = MIDIPreviewMonitor(
            diagnosticsStore: diagnostics,
            settingsManager: settings
        )

        var receivedEvent: MIDINoteEvent?
        monitor.onEvent = { event in
            receivedEvent = event
        }

        monitor.handle(
            packets: [.init(timestamp: 25, bytes: [0x90, 36, 96])],
            sourceID: "coremidi:99",
            sourceDisplayName: "Practice Kit"
        )

        #expect(receivedEvent?.sourceID == "coremidi:99")
        #expect(receivedEvent?.note == 36)
        #expect(receivedEvent?.velocity == 96)
        #expect(diagnostics.lastEvent?.mappedDrumType == .kick)
    }
}
