//
//  InputSettingsManager.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//

import Foundation
import Combine

class InputSettingsManager: ObservableObject {
    @Published private var keyboardMappings: [String: DrumType] = [:]
    @Published private var midiMappings: [UInt8: DrumType] = [:]
    
    private let userDefaults = UserDefaults.standard
    private let keyboardMappingsKey = "InputSettingsKeyboardMappings"
    private let midiMappingsKey = "InputSettingsMidiMappings"
    
    // Default mappings
    private let defaultKeyboardMappings: [String: DrumType] = [
        "space": .kick,      // Kick drum
        "f": .snare,         // Snare
        "j": .hiHat,         // Hi-hat
        "d": .tom1,          // High tom
        "k": .tom2,          // Mid tom  
        "s": .tom3,          // Low tom
        "l": .crash,         // Crash
        "semicolon": .ride,  // Ride
        "g": .cowbell        // Cowbell
    ]
    
    private let defaultMidiMappings: [UInt8: DrumType] = [
        36: .kick,        // Bass Drum 1
        38: .snare,       // Acoustic Snare
        42: .hiHat,       // Closed Hi-Hat
        44: .hiHatPedal,  // Pedal Hi-Hat
        47: .tom2,        // Low-Mid Tom
        48: .tom1,        // Hi-Mid Tom
        45: .tom3,        // Low Tom
        49: .crash,       // Crash Cymbal 1
        51: .ride,        // Ride Cymbal 1
        56: .cowbell      // Cowbell
    ]
    
    init() {
        loadSettings()
    }
    
    // MARK: - Public Methods
    
    func loadSettings() {
        loadKeyboardMappings()
        loadMidiMappings()
    }
    
    func saveSettings() {
        saveKeyboardMappings()
        saveMidiMappings()
    }
    
    func resetToDefaults() {
        keyboardMappings = defaultKeyboardMappings
        midiMappings = defaultMidiMappings
        saveSettings()
    }
    
    // MARK: - Keyboard Mapping Methods
    
    func getKeyBinding(for drumType: DrumType) -> String? {
        return keyboardMappings.first { $0.value == drumType }?.key
    }
    
    func setKeyBinding(_ key: String, for drumType: DrumType) {
        // Remove any existing mapping for this drum type
        keyboardMappings = keyboardMappings.filter { $0.value != drumType }
        
        // Remove any existing mapping for this key
        keyboardMappings.removeValue(forKey: key)
        
        // Add the new mapping
        keyboardMappings[key] = drumType
        saveKeyboardMappings()
    }
    
    func removeKeyBinding(for drumType: DrumType) {
        keyboardMappings = keyboardMappings.filter { $0.value != drumType }
        saveKeyboardMappings()
    }
    
    func getKeyboardMappings() -> [String: DrumType] {
        return keyboardMappings
    }
    
    // MARK: - MIDI Mapping Methods
    
    func getMidiMapping(for drumType: DrumType) -> UInt8? {
        return midiMappings.first { $0.value == drumType }?.key
    }
    
    func setMidiMapping(_ note: UInt8, for drumType: DrumType) {
        // Remove any existing mapping for this drum type
        midiMappings = midiMappings.filter { $0.value != drumType }
        
        // Remove any existing mapping for this MIDI note
        midiMappings.removeValue(forKey: note)
        
        // Add the new mapping
        midiMappings[note] = drumType
        saveMidiMappings()
    }
    
    func removeMidiMapping(for drumType: DrumType) {
        midiMappings = midiMappings.filter { $0.value != drumType }
        saveMidiMappings()
    }
    
    func getMidiMappings() -> [UInt8: DrumType] {
        return midiMappings
    }
    
    // MARK: - Private Persistence Methods
    
    private func loadKeyboardMappings() {
        if let data = userDefaults.data(forKey: keyboardMappingsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            // Convert string representations back to DrumType
            keyboardMappings = decoded.compactMapValues { DrumType.fromString($0) }
        } else {
            // Use default mappings if no saved mappings exist
            keyboardMappings = defaultKeyboardMappings
            saveKeyboardMappings()
        }
    }
    
    private func saveKeyboardMappings() {
        // Convert DrumType to string representations for JSON encoding
        let encodable = keyboardMappings.mapValues { $0.description }
        if let data = try? JSONEncoder().encode(encodable) {
            userDefaults.set(data, forKey: keyboardMappingsKey)
        }
    }
    
    private func loadMidiMappings() {
        if let data = userDefaults.data(forKey: midiMappingsKey),
           let decoded = try? JSONDecoder().decode([UInt8: String].self, from: data) {
            // Convert string representations back to DrumType
            midiMappings = decoded.compactMapValues { DrumType.fromString($0) }
        } else {
            // Use default mappings if no saved mappings exist
            midiMappings = defaultMidiMappings
            saveMidiMappings()
        }
    }
    
    private func saveMidiMappings() {
        // Convert DrumType to string representations for JSON encoding
        let encodable = midiMappings.mapValues { $0.description }
        if let data = try? JSONEncoder().encode(encodable) {
            userDefaults.set(data, forKey: midiMappingsKey)
        }
    }
}

// MARK: - DrumType String Conversion Extension

extension DrumType {
    static func fromString(_ string: String) -> DrumType? {
        switch string {
        case "kick": return .kick
        case "snare": return .snare
        case "hiHat": return .hiHat
        case "hiHatPedal": return .hiHatPedal
        case "crash": return .crash
        case "ride": return .ride
        case "tom1": return .tom1
        case "tom2": return .tom2
        case "tom3": return .tom3
        case "cowbell": return .cowbell
        default: return nil
        }
    }
}
