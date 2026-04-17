import Foundation
import Combine
import CoreMIDI

protocol MIDIPreviewPacketListening: AnyObject {
    @discardableResult
    func start(_ onPackets: @escaping (UnsafePointer<MIDIPacketList>, Int32, String) -> Void) -> Bool
    func stop()
}

final class CoreMIDIPreviewPacketListener: MIDIPreviewPacketListening {
    private final class SourceConnectionContext {
        let uniqueID: Int32
        let displayName: String

        init(uniqueID: Int32, displayName: String) {
            self.uniqueID = uniqueID
            self.displayName = displayName
        }
    }

    private var midiClient: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var connectionContexts: [MIDIEndpointRef: Unmanaged<SourceConnectionContext>] = [:]
    private let connectionQueue = DispatchQueue(label: "Virgo.MIDIPreview.connections")
    private let callbackDrain = NSCondition()
    private var activeCallbackCount = 0
    private var callbacksPaused = false

    @discardableResult
    func start(_ onPackets: @escaping (UnsafePointer<MIDIPacketList>, Int32, String) -> Void) -> Bool {
        connectionQueue.sync {
            startLocked(onPackets)
        }
    }

    func stop() {
        connectionQueue.sync {
            stopLocked()
        }
    }

    deinit {
        stop()
    }

    private func startLocked(_ onPackets: @escaping (UnsafePointer<MIDIPacketList>, Int32, String) -> Void) -> Bool {
        stopLocked()

        var client: MIDIClientRef = 0
        var status = MIDIClientCreateWithBlock("VirgoMIDIPreviewMonitor" as CFString, &client) { [weak self] _ in
            self?.connectionQueue.async { [weak self] in
                self?.refreshConnectionsLocked()
            }
        }
        guard status == noErr else {
            Logger.error("Failed to create MIDIPreviewMonitor MIDI client (status: \(status))")
            return false
        }

        var port: MIDIPortRef = 0
        status = MIDIInputPortCreateWithBlock(
            client,
            "VirgoMIDIPreviewInput" as CFString,
            &port
        ) { [weak self] packetList, srcConnRefCon in
            guard let self, let context = self.beginCallback(refCon: srcConnRefCon) else { return }
            defer { self.endCallback() }
            onPackets(packetList, context.uniqueID, context.displayName)
        }

        guard status == noErr else {
            Logger.error("Failed to create MIDIPreviewMonitor input port (status: \(status))")
            MIDIClientDispose(client)
            return false
        }

        midiClient = client
        inputPort = port
        refreshConnectionsLocked()
        return true
    }

    private func stopLocked() {
        disconnectAllSources()

        if inputPort != 0 {
            MIDIPortDispose(inputPort)
            inputPort = 0
        }

        if midiClient != 0 {
            MIDIClientDispose(midiClient)
            midiClient = 0
        }

        releaseConnectionContexts()
    }

    private func connectToAllSources() {
        let sourceCount = MIDIGetNumberOfSources()

        for index in 0..<sourceCount {
            let source = MIDIGetSource(index)
            guard source != 0, let uniqueID = CoreMIDISourceMetadata.uniqueID(for: source) else { continue }
            guard connectionContexts[source] == nil else { continue }

            let context = Unmanaged.passRetained(
                SourceConnectionContext(
                    uniqueID: uniqueID,
                    displayName: CoreMIDISourceMetadata.displayName(for: source) ?? "Unknown MIDI Source"
                )
            )

            let sourceName = CoreMIDISourceMetadata.displayName(for: source) ?? "Unknown MIDI Source"
            let status = MIDIPortConnectSource(inputPort, source, context.toOpaque())
            guard status == noErr else {
                Logger.error(
                    "Failed to connect MIDIPreviewMonitor to source \(sourceName) (status: \(status))"
                )
                context.release()
                continue
            }

            connectionContexts[source] = context
        }
    }

    private func disconnectAllSources() {
        pauseCallbacks()

        let retainedContexts = connectionContexts
        connectionContexts.removeAll()
        var contextsToRelease: [Unmanaged<SourceConnectionContext>] = []

        for (source, context) in retainedContexts {
            guard inputPort != 0 else {
                contextsToRelease.append(context)
                continue
            }

            let status = MIDIPortDisconnectSource(inputPort, source)
            if status == noErr {
                contextsToRelease.append(context)
            } else {
                Logger.error(
                    "Failed to disconnect MIDIPreviewMonitor from source \(context.takeUnretainedValue().displayName) (status: \(status))"
                )
                connectionContexts[source] = context
            }
        }

        waitForCallbacksToDrain()

        for context in contextsToRelease {
            context.release()
        }
    }

    private func refreshConnectionsLocked() {
        defer { resumeCallbacks() }
        disconnectAllSources()

        guard inputPort != 0 else { return }
        connectToAllSources()
    }

    private func beginCallback(refCon: UnsafeMutableRawPointer?) -> SourceConnectionContext? {
        guard let refCon else { return nil }

        callbackDrain.lock()
        guard !callbacksPaused else {
            callbackDrain.unlock()
            return nil
        }
        activeCallbackCount += 1
        callbackDrain.unlock()

        return Unmanaged<SourceConnectionContext>.fromOpaque(refCon).takeUnretainedValue()
    }

    private func endCallback() {
        callbackDrain.lock()
        activeCallbackCount -= 1
        if activeCallbackCount == 0 {
            callbackDrain.broadcast()
        }
        callbackDrain.unlock()
    }

    private func pauseCallbacks() {
        callbackDrain.lock()
        callbacksPaused = true
        callbackDrain.unlock()
    }

    private func resumeCallbacks() {
        callbackDrain.lock()
        callbacksPaused = false
        callbackDrain.unlock()
    }

    private func waitForCallbacksToDrain() {
        callbackDrain.lock()
        while activeCallbackCount > 0 {
            callbackDrain.wait()
        }
        callbackDrain.unlock()
    }

    private func releaseConnectionContexts() {
        let retainedContexts = connectionContexts
        connectionContexts.removeAll()

        for (_, context) in retainedContexts {
            context.release()
        }
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

    @discardableResult
    func start() -> Bool {
        let didStart = packetListener.start { [weak self] packetList, sourceUniqueID, sourceDisplayName in
            self?.handle(
                packetList: packetList,
                sourceUniqueID: sourceUniqueID,
                sourceDisplayName: sourceDisplayName
            )
        }
        if !didStart {
            Logger.error("Failed to start MIDI preview packet listener")
        }
        return didStart
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
        let events = eventRouter.decodeEvents(from: packets, sourceID: sourceID)
        guard !events.isEmpty else { return }

        if Thread.isMainThread {
            publish(events: events, sourceDisplayName: sourceDisplayName)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.publish(
                    events: events,
                    sourceDisplayName: sourceDisplayName
                )
            }
        }
    }

    private func publish(
        events: [MIDINoteEvent],
        sourceDisplayName: String
    ) {
        for event in events {
            publish(event: event, sourceDisplayName: sourceDisplayName)
        }
    }

    private func publish(event: MIDINoteEvent, sourceDisplayName: String) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                onEvent?(event)
                diagnosticsStore.record(
                    event: event,
                    mappedDrumType: settingsManager.getMidiMappings()[event.note],
                    sourceDisplayName: sourceDisplayName
                )
            }
        } else {
            Task { @MainActor in
                self.onEvent?(event)
                diagnosticsStore.record(
                    event: event,
                    mappedDrumType: self.settingsManager.getMidiMappings()[event.note],
                    sourceDisplayName: sourceDisplayName
                )
            }
        }
    }

}
