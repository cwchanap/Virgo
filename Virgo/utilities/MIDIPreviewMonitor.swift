import Foundation
import Combine
import CoreMIDI

protocol MIDIPreviewPacketListening: AnyObject {
    func start(_ onPackets: @escaping (UnsafePointer<MIDIPacketList>, Int32, String) -> Void)
    func stop()
}

final class CoreMIDIPreviewPacketListener: MIDIPreviewPacketListening {
    private struct SourceConnectionContext {
        let uniqueID: Int32
        let displayName: String
    }

    private var midiClient: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var connectionContexts: [MIDIEndpointRef: UnsafeMutablePointer<SourceConnectionContext>] = [:]

    func start(_ onPackets: @escaping (UnsafePointer<MIDIPacketList>, Int32, String) -> Void) {
        stop()

        var client: MIDIClientRef = 0
        var status = MIDIClientCreateWithBlock("VirgoMIDIPreviewMonitor" as CFString, &client) { [weak self] _ in
            self?.refreshConnections()
        }
        guard status == noErr else { return }

        var port: MIDIPortRef = 0
        status = MIDIInputPortCreateWithBlock(client, "VirgoMIDIPreviewInput" as CFString, &port) { packetList, srcConnRefCon in
            guard let srcConnRefCon else { return }

            let context = srcConnRefCon.assumingMemoryBound(to: SourceConnectionContext.self).pointee
            onPackets(packetList, context.uniqueID, context.displayName)
        }

        guard status == noErr else {
            MIDIClientDispose(client)
            return
        }

        midiClient = client
        inputPort = port
        refreshConnections()
    }

    func stop() {
        disconnectAllSources()

        if inputPort != 0 {
            MIDIPortDispose(inputPort)
            inputPort = 0
        }

        if midiClient != 0 {
            MIDIClientDispose(midiClient)
            midiClient = 0
        }
    }

    deinit {
        stop()
    }

    private func connectToAllSources() {
        let sourceCount = MIDIGetNumberOfSources()

        for index in 0..<sourceCount {
            let source = MIDIGetSource(index)
            guard source != 0, let uniqueID = CoreMIDISourceMetadata.uniqueID(for: source) else { continue }

            let contextPointer = UnsafeMutablePointer<SourceConnectionContext>.allocate(capacity: 1)
            contextPointer.initialize(
                to: SourceConnectionContext(
                    uniqueID: uniqueID,
                    displayName: CoreMIDISourceMetadata.displayName(for: source) ?? "Unknown MIDI Source"
                )
            )

            let status = MIDIPortConnectSource(inputPort, source, contextPointer)
            guard status == noErr else {
                contextPointer.deinitialize(count: 1)
                contextPointer.deallocate()
                continue
            }

            connectionContexts[source] = contextPointer
        }
    }

    private func disconnectAllSources() {
        for (source, contextPointer) in connectionContexts {
            if inputPort != 0 {
                MIDIPortDisconnectSource(inputPort, source)
            }

            contextPointer.deinitialize(count: 1)
            contextPointer.deallocate()
        }

        connectionContexts.removeAll()
    }

    private func refreshConnections() {
        disconnectAllSources()

        guard inputPort != 0 else { return }
        connectToAllSources()
    }
}

final class MIDIPreviewMonitor: ObservableObject {
    private let eventRouter: MIDIEventRouter
    private let diagnosticsStore: MIDIDiagnosticsStore
    private let settingsManager: InputSettingsManager
    private let sourceIDResolver: MIDISourceIDResolving
    private let packetListener: MIDIPreviewPacketListening

    var onEvent: ((MIDINoteEvent) -> Void)?

    init(
        eventRouter: MIDIEventRouter = MIDIEventRouter(),
        diagnosticsStore: MIDIDiagnosticsStore,
        settingsManager: InputSettingsManager,
        sourceIDResolver: MIDISourceIDResolving = CoreMIDISourceIDResolver(),
        packetListener: MIDIPreviewPacketListening = CoreMIDIPreviewPacketListener()
    ) {
        self.eventRouter = eventRouter
        self.diagnosticsStore = diagnosticsStore
        self.settingsManager = settingsManager
        self.sourceIDResolver = sourceIDResolver
        self.packetListener = packetListener
    }

    deinit {
        stop()
    }

    func start() {
        packetListener.start { [weak self] packetList, sourceUniqueID, sourceDisplayName in
            self?.handle(
                packetList: packetList,
                sourceUniqueID: sourceUniqueID,
                sourceDisplayName: sourceDisplayName
            )
        }
    }

    func stop() {
        packetListener.stop()
    }

    func handle(packetList: UnsafePointer<MIDIPacketList>, sourceUniqueID: Int32, sourceDisplayName: String) {
        let sourceID = sourceIDResolver.stableSourceID(for: sourceUniqueID)
        let packets = eventRouter.convertPacketList(packetList)
        handle(packets: packets, sourceID: sourceID, sourceDisplayName: sourceDisplayName)
    }

    func handle(packets: [MIDIPacketBytes], sourceID: String, sourceDisplayName: String) {
        let mappings = settingsManager.getMidiMappings()

        for event in eventRouter.decodeEvents(from: packets, sourceID: sourceID) {
            publish(
                event: event,
                mappedDrumType: mappings[event.note],
                sourceDisplayName: sourceDisplayName
            )
        }
    }

    private func publish(event: MIDINoteEvent, mappedDrumType: DrumType?, sourceDisplayName: String) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                diagnosticsStore.record(
                    event: event,
                    mappedDrumType: mappedDrumType,
                    sourceDisplayName: sourceDisplayName
                )
                onEvent?(event)
            }
        } else {
            Task { @MainActor in
                diagnosticsStore.record(
                    event: event,
                    mappedDrumType: mappedDrumType,
                    sourceDisplayName: sourceDisplayName
                )
                onEvent?(event)
            }
        }
    }
}
