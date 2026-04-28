import Foundation
import Combine
import CoreMIDI

struct MIDISourceDescriptor: Identifiable, Equatable {
    let id: String
    let displayName: String
    let isConnected: Bool
}

protocol MIDISourceProviding {
    func currentSources() -> [MIDISourceDescriptor]
}

protocol MIDISourceChangeListening: AnyObject {
    @discardableResult
    func start(_ onChange: @escaping () -> Void) -> Bool
    func stop()
}

struct CoreMIDISourceIDResolver: MIDISourceIDResolving {
    func stableSourceID(for uniqueID: Int32) -> String {
        "coremidi:\(uniqueID)"
    }
}

enum CoreMIDISourceMetadata {
    static func uniqueID(for endpoint: MIDIEndpointRef) -> Int32? {
        var uniqueID: Int32 = 0
        let status = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
        return status == noErr ? uniqueID : nil
    }

    static func displayName(for endpoint: MIDIEndpointRef) -> String? {
        stringProperty(kMIDIPropertyDisplayName, for: endpoint)
            ?? stringProperty(kMIDIPropertyName, for: endpoint)
    }

    private static func stringProperty(_ property: CFString, for object: MIDIObjectRef) -> String? {
        var value: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(object, property, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

struct CoreMIDISourceProvider: MIDISourceProviding {
    private let resolver: MIDISourceIDResolving

    init(resolver: MIDISourceIDResolving = CoreMIDISourceIDResolver()) {
        self.resolver = resolver
    }

    func currentSources() -> [MIDISourceDescriptor] {
        let sourceCount = MIDIGetNumberOfSources()
        var sources: [MIDISourceDescriptor] = []
        sources.reserveCapacity(Int(sourceCount))

        for index in 0..<sourceCount {
            let source = MIDIGetSource(index)
            guard source != 0, let uniqueID = CoreMIDISourceMetadata.uniqueID(for: source) else { continue }

            let sourceID = resolver.stableSourceID(for: uniqueID)
            let displayName = CoreMIDISourceMetadata.displayName(for: source) ?? sourceID

            sources.append(
                MIDISourceDescriptor(
                    id: sourceID,
                    displayName: displayName,
                    isConnected: true
                )
            )
        }

        return sources.sorted {
            let comparison = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if comparison == .orderedSame {
                return $0.id < $1.id
            }
            return comparison == .orderedAscending
        }
    }
}

final class CoreMIDISourceChangeListener: MIDISourceChangeListening {
    private let stateQueue = DispatchQueue(label: "Virgo.CoreMIDISourceChangeListener.state")
    private var midiClient: MIDIClientRef = 0
    private var onChange: (() -> Void)?

    @discardableResult
    func start(_ onChange: @escaping () -> Void) -> Bool {
        stop()

        stateQueue.sync {
            self.onChange = onChange
        }

        var client: MIDIClientRef = 0
        let status = MIDIClientCreateWithBlock("VirgoMIDIDeviceRegistry" as CFString, &client) { [weak self] _ in
            self?.notifyChange()
        }

        guard status == noErr else {
            Logger.error("Failed to create CoreMIDI source-change client (status: \(status))")
            stateQueue.sync {
                self.onChange = nil
            }
            return false
        }

        stateQueue.sync {
            midiClient = client
        }
        return true
    }

    func stop() {
        let client = stateQueue.sync { () -> MIDIClientRef in
            onChange = nil
            let client = midiClient
            midiClient = 0
            return client
        }

        guard client != 0 else { return }
        MIDIClientDispose(client)
    }

    deinit {
        stop()
    }

    private func notifyChange() {
        let callback = stateQueue.sync { onChange }
        callback?()
    }
}

@MainActor
final class MIDIDeviceRegistry: ObservableObject {
    @Published private(set) var sources: [MIDISourceDescriptor] = []
    @Published private(set) var selectedSourceID: String?
    @Published private(set) var isSelectedSourceAvailable = false

    var onSelectedSourceUnavailable: ((String) -> Void)?

    private let settingsManager: InputSettingsManager
    private let sourceProvider: MIDISourceProviding
    private let sourceChangeListener: MIDISourceChangeListening
    private var isRefreshScheduled = false

    init(
        settingsManager: InputSettingsManager,
        sourceProvider: MIDISourceProviding = CoreMIDISourceProvider(),
        sourceChangeListener: MIDISourceChangeListening = CoreMIDISourceChangeListener()
    ) {
        self.settingsManager = settingsManager
        self.sourceProvider = sourceProvider
        self.sourceChangeListener = sourceChangeListener
        self.selectedSourceID = settingsManager.getSelectedMIDISource()?.id
    }

    @discardableResult
    func startMonitoring() -> Bool {
        refreshSources()
        let didStart = sourceChangeListener.start { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshSourcesOnMainActor()
            }
        }
        if !didStart {
            Logger.error("Failed to start MIDI source monitoring")
        }
        return didStart
    }

    func stopMonitoring() {
        sourceChangeListener.stop()
    }

    func refreshSources() {
        let wasAvailable = isSelectedSourceAvailable
        let oldSelectedID = selectedSourceID

        sources = Self.collapseDuplicateSources(sourceProvider.currentSources())
        selectedSourceID = settingsManager.getSelectedMIDISource()?.id

        if let selectedSourceID {
            isSelectedSourceAvailable = sources.contains {
                $0.id == selectedSourceID && $0.isConnected
            }

            if oldSelectedID == selectedSourceID && wasAvailable && !isSelectedSourceAvailable {
                onSelectedSourceUnavailable?(selectedSourceID)
            }
        } else {
            isSelectedSourceAvailable = false
        }
    }

    func selectSource(_ source: MIDISourceDescriptor) {
        settingsManager.setSelectedMIDISource(id: source.id, displayName: source.displayName)
        selectedSourceID = source.id
        isSelectedSourceAvailable = sources.contains {
            $0.id == source.id && $0.isConnected
        }
    }

    func displayName(for sourceID: String) -> String {
        if let liveSource = sources.first(where: { $0.id == sourceID }) {
            return liveSource.displayName
        }

        if let selectedSource = settingsManager.getSelectedMIDISource(),
           selectedSource.id == sourceID {
            return selectedSource.displayName
        }

        return "Unknown MIDI Source"
    }

    private func refreshSourcesOnMainActor() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                refreshSources()
            }
        } else {
            guard !isRefreshScheduled else { return }
            isRefreshScheduled = true
            Task { @MainActor in
                isRefreshScheduled = false
                refreshSources()
            }
        }
    }

    private static func collapseDuplicateSources(_ sources: [MIDISourceDescriptor]) -> [MIDISourceDescriptor] {
        var orderedIDs: [String] = []
        var dedupedSources: [String: MIDISourceDescriptor] = [:]
        orderedIDs.reserveCapacity(sources.count)

        for source in sources {
            if let existing = dedupedSources[source.id] {
                if !existing.isConnected && source.isConnected {
                    dedupedSources[source.id] = source
                }
                continue
            }

            orderedIDs.append(source.id)
            dedupedSources[source.id] = source
        }

        return orderedIDs.compactMap { dedupedSources[$0] }
    }
}
